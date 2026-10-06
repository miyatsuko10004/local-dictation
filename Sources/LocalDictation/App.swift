import SwiftUI
import AppKit

@main struct LocalDictationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = DictationController()
    var body: some Scene {
        WindowGroup("Local Dictation") { DictationView(controller: controller).onAppear { appDelegate.controller = controller } }
            .defaultSize(width: 620, height: 650)
        MenuBarExtra("Local Dictation", systemImage: controller.recording ? "mic.fill" : "waveform") {
            Text(controller.status)
            Button(controller.recording ? "録音を停止" : "録音を開始") { controller.toggle() }
                .disabled(controller.busy || !controller.prepared)
            Button("中止") { controller.cancel() }.disabled(controller.preparing || controller.inserting || (!controller.busy && !controller.recording))
            Divider()
            Button("画面を開く") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.title == "Local Dictation" }?.makeKeyAndOrderFront(nil)
            }
            Button("終了") { controller.shutdown(); NSApp.terminate(nil) }
        }
    }
}

struct DictationView: View {
    @ObservedObject var controller: DictationController
    @State private var settings = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill").font(.system(size: 44)).foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Local Dictation").font(.title2.bold())
                    Text("声から、あなたの文章へ。").foregroundStyle(.secondary)
                }
                Spacer()
                Label("端末内処理", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle().fill(controller.recording ? Color.red : (controller.busy ? Color.orange : Color.green))
                        .frame(width: 8, height: 8)
                    Text(controller.status).font(.headline)
                    Spacer()
                    if controller.recording { Text("\(controller.seconds)秒").monospacedDigit() }
                    if controller.busy { ProgressView().controlSize(.small) }
                }
                Text(controller.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if controller.recording { ProgressView(value: Double(controller.level)).tint(.red) }
                HStack {
                    Button(controller.recording ? "停止して文字にする" : "録音する") { controller.toggle() }
                        .buttonStyle(.borderedProminent).disabled(controller.busy || !controller.prepared)
                    Button("中止") { controller.cancel() }
                        .disabled(controller.preparing || controller.inserting || (!controller.busy && !controller.recording))
                    Spacer()
                    Text(controller.shortcutName).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                }
            }.padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Toggle("AIで句読点も整える", isOn: $controller.preferences.cleanupEnabled)
                Toggle("元の入力欄へ自動入力", isOn: $controller.preferences.autoPaste)
            }.disabled(controller.busy || controller.recording)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("入力する文章").font(.headline)
                    Spacer()
                    if controller.processingSeconds > 0 {
                        Text(String(format: "処理 %.1f秒", controller.processingSeconds)).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("AI推敲") { controller.makePreview() }.disabled(controller.busy || controller.recording || controller.resultText.isEmpty)
                    Button("コピー") { controller.copyResult() }.disabled(controller.resultText.isEmpty)
                }
                TextEditor(text: $controller.resultText).font(.system(size: 15)).frame(minHeight: 135)
                    .padding(6).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                DisclosureGroup("文字起こし原文") {
                    ScrollView { Text(controller.rawText.isEmpty ? "録音後に表示します" : controller.rawText)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 75)
                }.font(.callout)
            }
            if !controller.previewText.isEmpty {
                DisclosureGroup("推敲プレビュー（自動入力しません）") {
                    Text(controller.previewText).textSelection(.enabled)
                    Button("この文章を採用") { controller.adoptPreview() }
                }
            }
            Divider()
            HStack {
                Label(controller.prepared ? "音声モデル準備済み" : "音声モデル未準備", systemImage: controller.prepared ? "checkmark.circle" : "arrow.down.circle")
                Spacer()
                Button("設定・辞書") { settings = true }.disabled(controller.busy || controller.recording)
                Button("音声モデルを準備") { controller.prepare() }.disabled(controller.busy || controller.recording)
            }.font(.callout)
            HStack {
                Text("マイク: \(controller.microphoneGranted ? "許可済み" : "録音時に確認")")
                Text("自動入力: \(controller.accessibilityGranted ? "許可済み" : "権限が必要")")
                Spacer()
                Button("自動入力を許可") { controller.requestAccessibility() }
                Button { controller.refreshPermissions() } label: { Image(systemName: "arrow.clockwise") }
            }.font(.caption)
            Text("初回モデル取得後、音声認識と整形はこのMacで処理します。履歴は自動保存しません。整形に失敗した場合は原文を保持します。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 580, minHeight: 610)
            .onAppear { controller.refreshPermissions() }
            .sheet(isPresented: $settings) { SettingsView(controller: controller) }
            .onChange(of: controller.preferences.cleanupEnabled) { _, _ in controller.saveSettings() }
            .onChange(of: controller.preferences.autoPaste) { _, _ in controller.saveSettings() }
    }
}
