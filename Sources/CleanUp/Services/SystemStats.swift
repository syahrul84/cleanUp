import Foundation
import Darwin

/// Live CPU and memory usage, sampled on a timer (Mach host statistics —
/// the same source Activity Monitor uses).
final class SystemStats: ObservableObject {
    static let shared = SystemStats()

    @Published var cpuPercent: Double = 0
    @Published var memUsed: Int64 = 0
    let memTotal = Int64(ProcessInfo.processInfo.physicalMemory)

    var memFraction: Double { Double(memUsed) / Double(max(memTotal, 1)) }

    private var previousLoad = host_cpu_load_info()
    private var hasPrevious = false
    private var timer: Timer?

    func start() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hasPrevious = false
    }

    private func sample() {
        // CPU: percentage of non-idle ticks since the previous sample.
        let load = currentCPULoad()
        if hasPrevious {
            let user = Double(load.cpu_ticks.0 &- previousLoad.cpu_ticks.0)
            let system = Double(load.cpu_ticks.1 &- previousLoad.cpu_ticks.1)
            let idle = Double(load.cpu_ticks.2 &- previousLoad.cpu_ticks.2)
            let nice = Double(load.cpu_ticks.3 &- previousLoad.cpu_ticks.3)
            let total = user + system + idle + nice
            if total > 0 { cpuPercent = (user + system + nice) / total * 100 }
        }
        previousLoad = load
        hasPrevious = true

        // Memory: approximately Activity Monitor's "Memory Used"
        // (app/active + wired + compressed).
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let pageSize = Int64(vm_kernel_page_size)
        memUsed = Int64(vm.active_count &+ vm.wire_count &+ vm.compressor_page_count) * pageSize
    }

    private func currentCPULoad() -> host_cpu_load_info {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return info
    }
}
