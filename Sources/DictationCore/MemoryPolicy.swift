import Foundation
public enum MemoryPressure: Sendable { case normal, warning, critical }
public enum MemoryPolicy {
    public static func shouldSkipOptionalLLM(pressure: MemoryPressure, availableBytes: UInt64?) -> Bool {
        return pressure != .normal || availableBytes.map { $0 < 2 * 1024 * 1024 * 1024 } == true
    }
}
