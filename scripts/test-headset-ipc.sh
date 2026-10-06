#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
cat > "$test_dir/main.swift" <<'SWIFT'
import Foundation
let args = CommandLine.arguments
if args.count == 4 && args[1] == "--send" {
    let center = DistributedNotificationCenter.default()
    for _ in 0..<2 { center.postNotificationName(Notification.Name(args[2]), object: args[3], userInfo: nil, deliverImmediately: true) }
} else {
    let topic = HeadsetIntegration.notificationName + ".test." + UUID().uuidString
    let identifier = UUID().uuidString
    var gate = HeadsetEventGate(), events = 0, accepted = 0
    let observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(topic), object: nil, queue: .main) { notification in
        guard let id = notification.object as? String else { return }
        events += 1
        if gate.accept(id, now: ProcessInfo.processInfo.systemUptime) { accepted += 1 }
    }
    let sender = Process()
    sender.executableURL = URL(fileURLWithPath: args[0])
    sender.arguments = ["--send", topic, identifier]
    try sender.run()
    let deadline = Date().addingTimeInterval(5)
    while events < 2 && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    sender.waitUntilExit()
    DistributedNotificationCenter.default().removeObserver(observer)
    precondition(sender.terminationStatus == 0 && events == 2 && accepted == 1, "IPC/duplicate delivery failed")
    print("PASS: isolated two-process notification delivery and duplicate suppression")
}
SWIFT
swiftc -module-cache-path "$task_root/.build/clang-cache" "$test_dir/main.swift" "$task_root/Sources/DictationCore/Headset.swift" -o "$test_dir/test"
"$test_dir/test"
