import AVFoundation
import AudioToolbox
import DictationSpeech
import DictationCore

final class StreamingCapture: @unchecked Sendable {
    let writer: AudioChunkWriter
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private enum Phase { case stopped, starting, running, recovering }
    private var phase: Phase = .stopped
    private var tapGeneration = 0
    private var receivedBuffer = false
    private var meterValue: Float = 0
    private var conversionError: Error?
    private var configurationObserver: NSObjectProtocol?
    private var startupTimeout: DispatchWorkItem?
    private var selectedUID: String?
    private var recoveryBudget = AudioRecoveryBudget()
    private var recoveryDeadline: Double?
    private var interrupted = false
    private var tapInstalled = false
    var onInterruption: (@Sendable () -> Void)?
    var onRecovery: (@Sendable () -> Void)?
    private(set) var microphoneName = ""
    init(directory: URL) throws { writer = try AudioChunkWriter(directory: directory) }
    var level: Float { lock.lock(); defer { lock.unlock() }; return meterValue }

    func start(microphoneUID: String?) throws {
        precondition(Thread.isMainThread)
        let selected = try MicrophoneDevices.selected(uid: microphoneUID)
        selectedUID = selected.uid // Pin even the current system default for this recording.
        microphoneName = selected.name
        lock.lock(); phase = .starting; lock.unlock()
        do { try configureAndStart(selected) }
        catch { suspendEngine(); throw error }
    }
    private func configureAndStart(_ selected: MicrophoneDevice) throws {
        let input = engine.inputNode
        guard let unit = input.audioUnit else { throw DictationError.message("マイクの入力を準備できませんでした。") }
        var deviceID = selected.id
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw DictationError.message("選択したマイクに切り替えられませんでした（\(status)）。") }
        var actualID: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &actualID, &size) == noErr, actualID == deviceID else { throw DictationError.message("選択したマイクへの切り替えを確認できませんでした。") }
        let native = input.outputFormat(forBus: 0)
        guard native.sampleRate > 0, native.channelCount > 0,
              let mono = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
              let converter = AVAudioConverter(from: native, to: mono) else {
            throw DictationError.message("マイクの音声形式を取得できませんでした。")
        }
        lock.lock(); tapGeneration += 1; let generation = tapGeneration; receivedBuffer = false; phase = .running; lock.unlock()
        input.installTap(onBus: 0, bufferSize: 2048, format: native) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / native.sampleRate) + 32)
            guard let output = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: capacity) else { return }
            var supplied = false, error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            self.lock.lock(); defer { self.lock.unlock() }
            guard self.phase == .running, self.tapGeneration == generation else { return }
            if let error { self.conversionError = error; return }
            guard output.frameLength > 0, let channel = output.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            let power = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
            let db = 10 * log10(max(power, 0.00000001))
            self.meterValue = max(0, min(1, (db + 60) / 60)); self.receivedBuffer = true
            self.writer.append(samples)
        }
        tapInstalled = true
        do { engine.prepare(); try engine.start() }
        catch { suspendEngine(); throw error }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.configurationChanged(generation: generation)
        }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock(); let missing = self.phase == .running && self.tapGeneration == generation && !self.receivedBuffer; self.lock.unlock()
            if missing { self.interruptOnce() }
        }
        startupTimeout = timeout
        let remaining = recoveryDeadline.map { max(0, $0 - ProcessInfo.processInfo.systemUptime) } ?? 10
        DispatchQueue.main.asyncAfter(deadline: .now() + min(10, remaining), execute: timeout)
    }
    private func configurationChanged(generation: Int) {
        precondition(Thread.isMainThread)
        lock.lock(); let active = phase == .running && tapGeneration == generation; lock.unlock()
        guard active, let uid = selectedUID else { return }
        let selected = try? MicrophoneDevices.selected(uid: uid)
        let now = ProcessInfo.processInfo.systemUptime
        guard recoveryBudget.allow(selectedUID: uid, connectedUID: selected?.uid, now: now), let selected else { interruptOnce(); return }
        if recoveryDeadline == nil { recoveryDeadline = now + 10 }
        suspendEngine()
        lock.lock(); phase = .recovering; conversionError = nil; lock.unlock()
        do { try configureAndStart(selected); onRecovery?() }
        catch { interruptOnce() }
    }
    private func interruptOnce() {
        guard !interrupted else { return }
        interrupted = true; suspendEngine(); onInterruption?()
    }
    private func suspendEngine() {
        startupTimeout?.cancel(); startupTimeout = nil
        lock.lock(); phase = .stopped; tapGeneration += 1; lock.unlock()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver); self.configurationObserver = nil }
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
    }
    func stop() throws -> [AudioChunk] {
        precondition(Thread.isMainThread)
        suspendEngine()
        let chunks = try writer.finish()
        lock.lock(); let error = conversionError; lock.unlock()
        if let error { throw error }
        return chunks
    }
    deinit {
        startupTimeout?.cancel()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }
}
