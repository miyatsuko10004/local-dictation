import DictationCore
import SwiftUI
import AppKit
import Carbon

struct SettingsView: View {
    @ObservedObject var controller: DictationController
    @Environment(\.dismiss) private var dismiss
    @State private var recordingShortcut = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("設定と辞書").font(.title2.bold())
            GroupBox("マイクとヘッドセット") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("マイク", selection: Binding(get: { controller.preferences.microphoneUID ?? "" }, set: { controller.preferences.microphoneUID = $0.isEmpty ? nil : $0 })) {
                            Text("システム標準").tag("")
                            ForEach(controller.microphones) { microphone in Text(microphone.name).tag(microphone.uid) }
                            if let uid = controller.preferences.microphoneUID, !controller.microphones.contains(where: { $0.uid == uid }) { Text("選択したマイク（未接続）").tag(uid) }
                        }
                        Button("再読込") { controller.refreshMicrophones() }
                    }
                    if !controller.microphoneListError.isEmpty { Text(controller.microphoneListError).foregroundStyle(.red) }
                    Toggle("headset-typelessから録音を開始・停止", isOn: $controller.preferences.headsetEnabled)
                    Text(controller.headsetStatus).font(.caption)
                    Text("ヘッドセットのボタンは押すたびに開始・停止します。未接続の指定マイクでは録音を始めません。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8).disabled(controller.recording || controller.busy)
            }
            GroupBox("操作") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("録音ショートカット"); Spacer(); Text(controller.shortcutName).font(.headline)
                        Button("変更") { recordingShortcut.toggle() }
                    }
                    if recordingShortcut {
                        ShortcutRecorder(cancelled: { recordingShortcut = false }) { code, modifiers in
                            controller.setShortcut(code: code, modifiers: modifiers); recordingShortcut = false
                        }.frame(height: 40)
                        Text("Command・Option・Controlのいずれかとキーを押してください。Escで中止。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("⌘⌥ Space") { controller.setShortcut(code: 49, modifiers: UInt32(cmdKey | optionKey)) }
                        Button("⌃⌥ Space") { controller.setShortcut(code: 49, modifiers: UInt32(controlKey | optionKey)) }
                        Button("F2") { controller.setShortcut(code: 120, modifiers: 0) }
                    }
                    Toggle("押している間だけ録音", isOn: $controller.preferences.pushToTalk)
                    Stepper("録音上限: \(controller.preferences.maxRecordingSeconds)秒", value: $controller.preferences.maxRecordingSeconds, in: 30...600, step: 30)
                    Stepper("モデル解放: 無操作\(controller.preferences.idleUnloadSeconds)秒後", value: $controller.preferences.idleUnloadSeconds, in: 1...120, step: 5)
                    Toggle("ログイン時に起動", isOn: Binding(get: { controller.loginEnabled }, set: { controller.setLogin($0) }))
                }.padding(8)
            }
            GroupBox("AI") {
                HStack {
                    Text("ローカルモデル"); TextField(LocalModelDefaults.cleanup, text: $controller.preferences.cleanupModel)
                }.padding(8)
            }
            Text("単語辞書").font(.headline)
            Text("正しい表記と、聞き間違えやすい読みを登録します。読みはカンマ区切り。引用・コード・URLの中は変更しません。")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach($controller.dictionary) { $entry in
                    HStack {
                        TextField("正しい表記", text: $entry.word).frame(width: 160)
                        TextField("読み、別の読み", text: Binding(get: { entry.readings.joined(separator: ", ") }, set: { entry.readings = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }))
                        Button { controller.dictionary.removeAll { $0.id == entry.id } } label: { Image(systemName: "minus.circle") }
                    }
                }
            }.frame(minHeight: 120)
            HStack {
                Button("単語を追加") { controller.addDictionaryEntry() }
                Spacer()
                Button("保存して閉じる") { controller.saveSettings(); dismiss() }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 610, height: 800).onAppear { controller.refreshMicrophones() }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    var cancelled: () -> Void
    var captured: (UInt32, UInt32) -> Void
    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView(); view.captured = captured; view.cancelled = cancelled; return view
    }
    func updateNSView(_ view: KeyRecorderView, context: Context) { view.captured = captured; view.cancelled = cancelled }
}
final class KeyRecorderView: NSView {
    var captured: ((UInt32, UInt32) -> Void)?
    var cancelled: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); dirtyRect.fill()
        ("ここで新しいキーを押す" as NSString).draw(at: NSPoint(x: 12, y: 10), withAttributes: [.foregroundColor: NSColor.labelColor])
    }
    override func flagsChanged(with event: NSEvent) {
        if event.keyCode == 60 && RightShiftShortcut.isPressed(keyCode: UInt32(event.keyCode), flags: UInt64(event.modifierFlags.rawValue)) { captured?(60, 0) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelled?(); return }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 || event.keyCode == 120 else { NSSound.beep(); return }
        captured?(UInt32(event.keyCode), modifiers)
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: DictationController?
    func applicationWillTerminate(_ notification: Notification) { controller?.shutdown() }
}
