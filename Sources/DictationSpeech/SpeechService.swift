import Foundation
import WhisperKit
import CryptoKit
import DictationCore

public actor SpeechService {
    public enum Model: String, Sendable {
        case compressedTurbo = "openai_whisper-large-v3-v20240930_turbo_632MB"
        case compressedLarge = "openai_whisper-large-v3_947MB"
    }
    public enum Backend: Sendable { case whisperCPP, coreML }
    public static let modelName = "ggml-large-v3-turbo-q5_0"
    public static let modelFile = modelName + ".bin"
    public static let modelSHA256 = "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
    public nonisolated let backend: Backend
    public nonisolated var identifier: String { backend == .whisperCPP ? Self.modelName : model.rawValue }
    private let executable: URL
    private let cpp: WhisperProcess
    public nonisolated let model: Model
    private let base: URL
    private var engine: WhisperKit?
    public init(base: URL = DictationPaths.base, model: Model = .compressedTurbo, backend: Backend = .whisperCPP) {
        self.base = base; self.model = model; self.backend = backend
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("whisper-cli")
        self.executable = bundled.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil } ?? base.appendingPathComponent("bin/whisper-cli")
        self.cpp = WhisperProcess(executable: self.executable, model: base.appendingPathComponent("models/" + Self.modelFile))
        // Prevent the upstream tokenizer's fallback downloader from contacting the Hub.
        setenv("HF_ENDPOINT", "http://127.0.0.1:9", 1)
    }
    public nonisolated static func isPrepared(base: URL = DictationPaths.base) -> Bool {
        FileManager.default.fileExists(atPath: base.appendingPathComponent("models/" + modelFile).path)
    }
    /// Only this explicit setup operation permits downloads. Inference never enables them.
    public func prepare() async throws {
        if backend == .whisperCPP { try await prepareCPP(); return }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        setenv("HF_ENDPOINT", "https://huggingface.co", 1)
        defer { setenv("HF_ENDPOINT", "http://127.0.0.1:9", 1) }
        let folder = try await WhisperKit.download(variant: model.rawValue, downloadBase: base,
            endpoint: "https://huggingface.co")
        let config = configuration(folder: folder, preparing: true)
        let loaded = try await WhisperKit(config)
        try Task.checkCancellation()
        try folder.path.write(to: base.appendingPathComponent("model-path.txt"), atomically: true, encoding: .utf8)
        engine = loaded
    }
    private func prepareCPP() async throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw DictationError.message("音声エンジンがありません。ビルドスクリプトを再実行してください。")
        }
        let folder = base.appendingPathComponent("models")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(Self.modelFile)
        if FileManager.default.fileExists(atPath: destination.path), try Self.checksum(destination) == Self.modelSHA256 { return }
        let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/" + Self.modelFile)!
        let (temporary, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, try Self.checksum(temporary) == Self.modelSHA256 else {
            throw DictationError.message("音声モデルの完全性検証に失敗しました。")
        }
        try Data(contentsOf: temporary, options: .mappedIfSafe).write(to: destination, options: .atomic)
    }
    private nonisolated static func checksum(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func configuration(folder: URL, preparing: Bool) -> WhisperKitConfig {
        WhisperKitConfig(model: model.rawValue, downloadBase: base,
            modelEndpoint: preparing ? "https://huggingface.co" : "http://127.0.0.1:9",
            modelFolder: folder.path, tokenizerFolder: base.appendingPathComponent("tokenizers"),
            verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
    }
    private func load() async throws -> WhisperKit {
        if let engine { return engine }
        let marker = base.appendingPathComponent("model-path.txt")
        guard let path = try? String(contentsOf: marker, encoding: .utf8),
              FileManager.default.fileExists(atPath: path) else {
            throw DictationError.message("音声モデルが未準備です。「音声モデルを準備」を実行してください。")
        }
        setenv("HF_ENDPOINT", "http://127.0.0.1:9", 1)
        let loaded = try await WhisperKit(configuration(folder: URL(fileURLWithPath: path), preparing: false))
        engine = loaded
        return loaded
    }
    public func unload() async {
        if backend == .whisperCPP { return }
        await engine?.unloadModels()
        engine = nil
    }
    /// WhisperKit has already applied its combined log-probability / silence decision.
    public nonisolated static func joinAcceptedSegments(_ segments: [TranscriptionSegment]) -> String {
        segments.map(\.text).joined()
    }
    public func transcribe(file: URL, prompt: String = "") async throws -> String {
        try Task.checkCancellation()
        if backend == .whisperCPP { return try await cpp.transcribe(file: file, prompt: prompt) }
        let loaded = try await load()
        let promptTokens = prompt.isEmpty ? nil : loaded.tokenizer?.encode(text: prompt)
        let options = DecodingOptions(language: "ja", temperatureFallbackCount: 2,
            skipSpecialTokens: true, withoutTimestamps: true, promptTokens: promptTokens, concurrentWorkerCount: 1)
        let results = try await loaded.transcribe(audioPath: file.path, decodeOptions: options)
        try Task.checkCancellation()
        return Self.joinAcceptedSegments(results.flatMap(\.segments))
    }
}
