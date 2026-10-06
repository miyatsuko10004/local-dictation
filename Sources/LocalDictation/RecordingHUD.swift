import AppKit
import SwiftUI

@MainActor final class RecordingHUD {
    private let panel: NSPanel
    init(controller: DictationController) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: HUDView(controller: controller))
    }
    func show() {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: area.midX - 180, y: area.minY + 40))
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
}
private struct HUDView: View {
    @ObservedObject var controller: DictationController
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: controller.recording ? "mic.fill" : "waveform").font(.title2)
                .foregroundStyle(controller.recording ? .red : .blue)
            VStack(alignment: .leading, spacing: 5) {
                Text(controller.status).font(.headline)
                if controller.recording {
                    ProgressView(value: Double(controller.level)).frame(width: 150)
                    Text("\(controller.seconds)秒 · \(controller.shortcutName)で停止").font(.caption).foregroundStyle(.secondary)
                } else { Text("このMacの中で処理しています").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button { controller.cancel() } label: { Image(systemName: "xmark.circle.fill").font(.title3) }
                .buttonStyle(.plain).disabled(controller.preparing || controller.inserting)
        }.padding(18).frame(width: 360, height: 100)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
