import Foundation
public enum HeadsetIntegration {
    public static let notificationName = "local.manyo.LocalDictation.headsetToggle.v1"
}
public struct HeadsetEventGate: Sendable {
    private var seen: [UUID] = []
    private var lastAccepted = -Double.infinity
    public init() {}
    public mutating func accept(_ identifier: String, now: Double) -> Bool {
        guard let id = UUID(uuidString: identifier), !seen.contains(id) else { return false }
        seen.append(id); if seen.count > 128 { seen.removeFirst() }
        guard now - lastAccepted >= 1 else { return false }
        lastAccepted = now; return true
    }
}

public struct AudioRecoveryBudget: Sendable {
    private var attempts = 0
    private var firstChange: Double?
    public init() {}
    public mutating func allow(selectedUID: String, connectedUID: String?, now: Double) -> Bool {
        guard selectedUID == connectedUID, attempts < 2 else { return false }
        let started = firstChange ?? now
        guard now - started <= 10 else { return false }
        firstChange = started; attempts += 1; return true
    }
}
