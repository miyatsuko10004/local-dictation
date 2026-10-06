import Foundation
import AVFoundation
import DictationCore

public struct AudioChunk: Sendable {
    public let url: URL
    public let index: Int
    public let newSampleCount: Int
    public let voiced: Bool
}

/// Buffers at most one short chunk, while completed chunks are written on a serial queue.
public final class AudioChunkWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "local.dictation.audio-files")
    private let directory: URL
    private let minimum: Int, maximum: Int, overlap: Int
    private var samples: [Float] = []
    private var newSamples = 0, voicedSamples = 0, quietSamples = 0, index = 0
    private var total = 0, closed = false
    private var files: [AudioChunk] = []
    private var error: Error?
    public var onChunk: (@Sendable (AudioChunk) -> Void)?
    public init(directory: URL, minimumSeconds: Double = 12, maximumSeconds: Double = 20, overlapSeconds: Double = 0) throws {
        self.directory = directory
        minimum = max(1, Int(minimumSeconds * 16000)); maximum = max(minimum, Int(maximumSeconds * 16000))
        overlap = min(maximum / 2, max(0, Int(overlapSeconds * 16000)))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }
    public var totalSamples: Int { lock.lock(); defer { lock.unlock() }; return total }
    public var hasVoice: Bool { lock.lock(); defer { lock.unlock() }; return voicedSamples > 0 || files.contains(where: \.voiced) }
    public func append(_ input: [Float]) {
        lock.lock(); defer { lock.unlock() }
        guard !closed, !input.isEmpty else { return }
        var cursor = 0
        while cursor < input.count {
            let count = min(input.count - cursor, maximum - newSamples)
            let part = Array(input[cursor..<cursor+count])
            samples.append(contentsOf: part); newSamples += count; total += count
            let power = part.reduce(Float(0)) { $0 + $1 * $1 } / Float(count)
            if power > 0.000003 { voicedSamples += count; quietSamples = 0 }
            else { quietSamples += count }
            cursor += count
            if newSamples >= maximum || (newSamples >= minimum && quietSamples >= 8000) { flushLocked() }
        }
    }
    private func flushLocked() {
        guard newSamples > 0 else { return }
        let snapshot = samples, number = index, added = newSamples, voiced = voicedSamples > 0
        index += 1
        samples = Array(snapshot.suffix(overlap)); newSamples = 0; voicedSamples = 0; quietSamples = 0
        queue.async { [self] in
            do {
                let url = directory.appendingPathComponent(String(format: "%04d.wav", number))
                let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
                var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(snapshot.count))!
                buffer.frameLength = AVAudioFrameCount(snapshot.count)
                snapshot.withUnsafeBufferPointer { ptr in buffer.floatChannelData![0].update(from: ptr.baseAddress!, count: snapshot.count) }
                try file?.write(from: buffer)
                file = nil
                let chunk = AudioChunk(url: url, index: number, newSampleCount: added, voiced: voiced)
                lock.lock(); files.append(chunk); lock.unlock()
                onChunk?(chunk)
            } catch { lock.lock(); self.error = error; lock.unlock() }
        }
    }
    public func finish() throws -> [AudioChunk] {
        lock.lock()
        if !closed { closed = true; flushLocked() }
        lock.unlock()
        queue.sync {}
        lock.lock(); defer { lock.unlock() }
        if let error { throw error }
        return files.sorted { $0.index < $1.index }
    }
}

public enum TranscriptMerger {
    /// Production chunks contain disjoint samples. Never infer deletion from matching words.
    public static func join(_ previous: String, _ next: String) -> String { previous + next }
}
