import Foundation
import Darwin
import DictationCore

@MainActor final class MemoryMonitor {
    private var pressure: MemoryPressure = .normal
    private let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
    init() {
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.source.data
            self.pressure = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
        }
        source.resume()
    }
    var shouldSkipOptionalLLM: Bool {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let available = result == KERN_SUCCESS
            ? (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * UInt64(vm_page_size) : nil
        return MemoryPolicy.shouldSkipOptionalLLM(pressure: pressure, availableBytes: available)
    }
    deinit { source.cancel() }
}
