import Foundation
import DictationCore
import DictationSpeech

@main struct DictationCheck {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        do {
            guard let command = args.first else { printHelp(); return }
            let start = Date()
            switch command {
            case "microphones":
                let devices = try MicrophoneDevices.available()
                emit(["devices": devices.map { ["id": $0.id, "uid": $0.uid, "name": $0.name] as [String: Any] }, "defaultID": try MicrophoneDevices.currentDefaultID()])
            case "prepare":
                print("Preparing and verifying selected local speech model. Initial setup only.")
                try await service().prepare()
                emit(["prepared": true, "model": try service().identifier, "seconds": Date().timeIntervalSince(start)])
            case "transcribe":
                guard args.count == 2 else { throw DictationError.message("transcribe AUDIO_FILE") }
                let text = try await service().transcribe(file: URL(fileURLWithPath: args[1]))
                emit(["text": text, "seconds": Date().timeIntervalSince(start)])
            case "batch":
                guard args.count == 2 else { throw DictationError.message("batch FIXTURE_JSON") }
                let entries = DictionaryStore.defaults
                let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [[String: Any]]
                let speech = try service()
                var rows: [[String: Any]] = []
                for item in cases {
                    let begin = Date()
                    let raw = try await speech.transcribe(file: URL(fileURLWithPath: item["audio"] as! String), prompt: item["prompt"] as? String ?? DictionaryStore.prompt(entries: entries))
                    let text = TextRules.clean(DictionaryStore.normalize(raw, entries: entries))
                    let elapsed = Date().timeIntervalSince(begin)
                    rows.append(["id": item["id"]!, "raw": raw, "text": text, "seconds": elapsed])
                    FileHandle.standardError.write(Data(("ASR \(item["id"]!) \(elapsed)s\n").utf8))
                }
                emit(["model": speech.identifier, "rows": rows])
            case "cleanup":
                guard args.count >= 2 else { throw DictationError.message("cleanup TEXT") }
                let result = try await OllamaClient().cleanup(args.dropFirst().joined(separator: " "))
                emit(["text": result.text, "changed": result.changed, "rejected": result.rejected,
                      "seconds": Date().timeIntervalSince(start)])
            case "cleanup-batch":
                guard args.count == 3 else { throw DictationError.message("cleanup-batch FIXTURE_JSON LOCAL_MODEL") }
                let cases = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
                let client = OllamaClient()
                var rows: [[String: Any]] = []
                for text in cases {
                    let begin = Date()
                    do {
                        let result = try await client.cleanup(text, model: args[2])
                        rows.append(["input": text, "text": result.text, "changed": result.changed, "rejected": result.rejected, "seconds": Date().timeIntervalSince(begin)])
                    } catch {
                        rows.append(["input": text, "error": error.localizedDescription, "seconds": Date().timeIntervalSince(begin)])
                    }
                }
                emit(["model": args[2], "rows": rows])
            case "smoke":
                emit(["app": "LocalDictation", "model": SpeechService.modelName,
                      "prepared": SpeechService.isPrepared(), "dataDirectory": DictationPaths.base.path])
            case "--help", "help": printHelp()
            default: throw DictationError.message("Unknown command")
            }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
    static func service() throws -> SpeechService {
        guard let identifier = ProcessInfo.processInfo.environment["LOCAL_DICTATION_BENCHMARK_MODEL"] else { return SpeechService() }
        guard let model = SpeechService.Model(rawValue: identifier), DictationPaths.base.lastPathComponent.hasPrefix("benchmark-") else {
            throw DictationError.message("Benchmark model must be supported and LOCAL_DICTATION_DATA must name a separate benchmark-* directory")
        }
        return SpeechService(model: model, backend: .coreML)
    }
    static func printHelp() { print("dictation-check prepare | transcribe AUDIO_FILE | batch FIXTURE_JSON | cleanup TEXT | microphones | smoke") }
    static func emit(_ result: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
