import Foundation

public enum TextRules {
    // Quoted text, URLs and identifiers are opaque to all cleanup rules.
    private static let protectedPattern = #"```[\s\S]*?```|`[^`\n]*`|「[^」]*」|『[^』]*』|\"[^\"\n]*\"|(?<![A-Za-z0-9])'[^'\n]*'(?![A-Za-z0-9])|https?://[^\s、。]+|[A-Za-z][A-Za-z0-9_./:+@?=&%#-]*"#
    public static func protectedParts(_ text: String) -> [String] {
        let re = try! NSRegularExpression(pattern: protectedPattern)
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
            String(text[Range($0.range, in: text)!])
        }
    }
    public static func mapUnprotected(_ text: String, protectIdentifiers: Bool = true, protectNumbers: Bool = false, transform: (String) -> String) -> String {
        let pattern = protectIdentifiers ? protectedPattern : #"```[\s\S]*?```|`[^`\n]*`|「[^」]*」|『[^』]*』|\"[^\"\n]*\"|(?<![A-Za-z0-9])'[^'\n]*'(?![A-Za-z0-9])|https?://[^\s、。]+"#
        let re = try! NSRegularExpression(pattern: protectNumbers ? pattern + #"|[0-9０-９]+(?:[.,．，][0-9０-９]+)*"# : pattern)
        var output = "", cursor = text.startIndex
        for match in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let range = Range(match.range, in: text)!
            output += transform(String(text[cursor..<range.lowerBound])) + text[range]
            cursor = range.upperBound
        }
        return output + transform(String(text[cursor...]))
    }
    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        let re = try! NSRegularExpression(pattern: pattern)
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
    public static func clean(_ text: String) -> String {
        mapUnprotected(text) { input in
            var result = input
            // Both sides must delimit the filler; lexical occurrences are preserved.
            for _ in 0..<3 {
                result = replace(result, #"(^|[、,\s])(?:えーっと|えー|ええと|えっと|あのー|うーん)(?:[、,\s]+|$)"#, "$1")
            }
            result = replace(result, #"([月火水木金土日]曜(?:日)?)[、,\s]*(?:いや|ではなくて)[、,\s]*([月火水木金土日]曜(?:日)?)"#, "$2")
            // The old and new quantities must explicitly have the same entire unit.
            result = replace(result, #"(?<![0-9０-９.．+＋−-])([0-9０-９]+(?:[.．][0-9０-９]+)?)(万円|億円|円|件|個|人|台|秒間|分間|時間|日間|月間|年間|週間|秒|分|日|月|年|キロ|メートル|kg|km|%|％)[、,\s]*(?:いや|ではなくて)[、,\s]*([0-9０-９]+(?:[.．][0-9０-９]+)?)\2(?![A-Za-z\p{Han}ァ-ヺー])"#, "$3$2")
            return result
        }.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var word: String
    public var readings: [String]
    public init(id: UUID = UUID(), word: String, readings: [String]) {
        self.id = id; self.word = word; self.readings = readings
    }
}
public final class DictionaryStore {
    private let file: URL
    public var entries: [DictionaryEntry]
    public static let defaults: [DictionaryEntry] = [
        .init(word: "Claude Code", readings: ["クロードコード", "ClaudeCode", "クロード・コード", "Claudeコード", "Claude code"]),
        .init(word: "Claude", readings: ["クロード"]),
        .init(word: "Codex", readings: ["コーデックス"]),
        .init(word: "Gemini", readings: ["ジェミニ"]),
        .init(word: "NotebookLM", readings: ["ノートブックエルエム", "ノートブックLM", "Notebook LM"]),
        .init(word: "Google Workspace", readings: ["グーグルワークスペース", "Googleワークスペース", "GoogleWorkspace"]),
        .init(word: "Typeless", readings: ["タイプレス"]),
        .init(word: "Antigravity", readings: ["アンチグラビティ", "アンティグラビティ", "AntiGravity"]),
        .init(word: "ChatGPT", readings: ["チャットジーピーティー", "チャットGPT", "Chat GPT"])
    ]
    public static var defaultEntries: [DictionaryEntry] { defaults }
    public init(base: URL = DictationPaths.base) {
        file = base.appendingPathComponent("dictionary.json")
        entries = (try? JSONDecoder().decode([DictionaryEntry].self, from: Data(contentsOf: file))) ?? Self.defaults
    }
    public func load() throws { entries = try JSONDecoder().decode([DictionaryEntry].self, from: Data(contentsOf: file)) }
    public func save() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: file, options: .atomic)
    }
    public static func normalize(_ text: String, entries: [DictionaryEntry]) -> String {
        let variants = entries.flatMap { entry in entry.readings.filter { !$0.isEmpty }.map { ($0, entry.word) } }
            .sorted { $0.0.count > $1.0.count }
        guard !variants.isEmpty else { return text }
        // One pass ensures replacement words are never rewritten by another entry.
        let alternatives = variants.enumerated().map { index, item in
            let escaped = NSRegularExpression.escapedPattern(for: item.0)
            let latin = item.0.range(of: #"[A-Za-z0-9]"#, options: .regularExpression) != nil
            let katakana = item.0.range(of: #"[ァ-ヺー]"#, options: .regularExpression) != nil
            let boundary = (latin || katakana) ? "A-Za-z0-9０-９_" + (katakana ? "ァ-ヺー" : "") : ""
            return boundary.isEmpty ? "(\(escaped))" : "(?<![\(boundary)])(\(escaped))(?![\(boundary)])"
        }.joined(separator: "|")
        let re = try! NSRegularExpression(pattern: alternatives, options: .caseInsensitive)
        return TextRules.mapUnprotected(text, protectIdentifiers: false) { segment in
            var result = segment
            for match in re.matches(in: segment, range: NSRange(segment.startIndex..., in: segment)).reversed() {
                guard let i = (1..<match.numberOfRanges).first(where: { match.range(at: $0).location != NSNotFound }), let range = Range(match.range, in: result) else { continue }
                result.replaceSubrange(range, with: variants[i - 1].1)
            }
            return result
        }
    }
    public static func prompt(entries: [DictionaryEntry]) -> String {
        var text = ""
        for entry in entries where !entry.word.isEmpty {
            let addition = (text.isEmpty ? "" : "、") + entry.word
            if text.count + addition.count <= 150 { text += addition }
        }
        return text
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var microphoneUID: String? = nil
    public var headsetEnabled = false
    public var cleanupEnabled = false
    public var pushToTalk = false
    public var autoPaste = true
    public var hotKeyCode: UInt32 = 49
    public var hotKeyModifiers: UInt32 = 2304
    public var maxRecordingSeconds = 600
    public var idleUnloadSeconds = 30
    public var cleanupModel = LocalModelDefaults.cleanup
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case cleanupEnabled, pushToTalk, autoPaste, hotKeyCode, hotKeyModifiers
        case maxRecordingSeconds, idleUnloadSeconds, cleanupModel, microphoneUID, headsetEnabled
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        microphoneUID = try values.decodeIfPresent(String.self, forKey: .microphoneUID)
        headsetEnabled = try values.decodeIfPresent(Bool.self, forKey: .headsetEnabled) ?? false
        cleanupEnabled = try values.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? cleanupEnabled
        pushToTalk = try values.decodeIfPresent(Bool.self, forKey: .pushToTalk) ?? false
        autoPaste = try values.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? autoPaste
        hotKeyCode = try values.decodeIfPresent(UInt32.self, forKey: .hotKeyCode) ?? hotKeyCode
        hotKeyModifiers = try values.decodeIfPresent(UInt32.self, forKey: .hotKeyModifiers) ?? hotKeyModifiers
        maxRecordingSeconds = try values.decodeIfPresent(Int.self, forKey: .maxRecordingSeconds) ?? maxRecordingSeconds
        idleUnloadSeconds = try values.decodeIfPresent(Int.self, forKey: .idleUnloadSeconds) ?? idleUnloadSeconds
        cleanupModel = try values.decodeIfPresent(String.self, forKey: .cleanupModel) ?? cleanupModel
    }
    public func validated() -> Preferences {
        var result = self
        result.maxRecordingSeconds = min(600, max(1, maxRecordingSeconds))
        result.idleUnloadSeconds = min(3600, max(1, idleUnloadSeconds))
        if !CleanupPolicy.isLocalModel(cleanupModel) { result.cleanupModel = LocalModelDefaults.cleanup }
        if hotKeyCode > 127 { result.hotKeyCode = 49 }
        result.hotKeyModifiers &= 0x1F00
        let functionKeys: Set<UInt32> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        if result.hotKeyModifiers & 0x1900 == 0 && !functionKeys.contains(result.hotKeyCode) && !(result.hotKeyCode == 60 && result.hotKeyModifiers == 0) {
            result.hotKeyModifiers = 2304
        }
        return result
    }
}
public final class PreferencesStore {
    private let file: URL
    public var preferences: Preferences
    public init(base: URL = DictationPaths.base) {
        file = base.appendingPathComponent("preferences.json")
        preferences = ((try? JSONDecoder().decode(Preferences.self, from: Data(contentsOf: file))) ?? Preferences()).validated()
    }
    public func save() throws {
        preferences = preferences.validated()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(preferences).write(to: file, options: .atomic)
    }
}

public enum RightShiftShortcut {
    /// NX_DEVICERSHIFTKEYMASK from macOS IOLLEvent.h.
    public static func isPressed(keyCode: UInt32, flags: UInt64) -> Bool {
        keyCode == 60 && flags & 0x4 != 0
    }
}
