import Foundation
import AppKit
import IOKit

// MARK: - Private IOHID sensor API (CPU temperature on Apple Silicon)
// These are unexported-but-stable IOKit symbols — the same route used by
// every Mac hardware-monitoring app, since macOS has no public sensor API.

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> OpaquePointer?
@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: OpaquePointer?, _ match: CFDictionary?) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: OpaquePointer?) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: OpaquePointer, _ key: CFString) -> Unmanaged<CFString>?
@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: OpaquePointer, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: OpaquePointer, _ field: Int32) -> Double

private let kIOHIDEventTypeTemperature: Int64 = 15

/// Reads the hidden HID temperature sensors (Apple Silicon). The client and
/// service list are built once and reused for every sample.
private final class HIDTemperatureReader {
    private var client: OpaquePointer?
    private var services: CFArray?

    init() {
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        guard let client else { return }
        let match = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, match)
        services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue()
    }

    /// (sensorName, °C) for every readable temperature sensor.
    func readAll() -> [(name: String, celsius: Double)] {
        guard let services else { return [] }
        var result: [(String, Double)] = []
        for i in 0..<CFArrayGetCount(services) {
            guard let raw = CFArrayGetValueAtIndex(services, i) else { continue }
            let service = OpaquePointer(raw)
            guard let eventRef = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0) else { continue }
            // takeRetainedValue → ARC releases the event when it leaves scope.
            let event = eventRef.takeRetainedValue()
            let value = IOHIDEventGetFloatValue(unsafeBitCast(event, to: OpaquePointer.self),
                                                Int32(kIOHIDEventTypeTemperature << 16))
            let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?
                .takeRetainedValue() as String? ?? ""
            result.append((name, value))
        }
        return result
    }
}

// MARK: - SMC (fan speed on all Macs; CPU temperature on Intel)

private typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

private struct SMCVersion { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0
    var reserved: UInt8 = 0; var release: UInt16 = 0 }
private struct SMCPLimitData { var version: UInt16 = 0; var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
private struct SMCKeyInfoData { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private final class SMCConnection {
    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func typeString(_ v: UInt32) -> String {
        String(bytes: [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff),
                       UInt8(v >> 8 & 0xff), UInt8(v & 0xff)], encoding: .ascii) ?? "?"
    }

    private func call(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input,
                                               MemoryLayout<SMCParamStruct>.stride,
                                               &output, &outputSize)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    /// Read a key and decode its numeric value (flt/fpe2/sp78/ui8/ui16/ui32).
    func readNumber(_ key: String) -> Double? {
        var infoInput = SMCParamStruct()
        infoInput.key = Self.fourCC(key)
        infoInput.data8 = 9 // kSMCGetKeyInfo
        guard let info = call(&infoInput) else { return nil }

        var readInput = SMCParamStruct()
        readInput.key = Self.fourCC(key)
        readInput.keyInfo.dataSize = info.keyInfo.dataSize
        readInput.data8 = 5 // kSMCReadKey
        guard let out = call(&readInput) else { return nil }

        let b = Mirror(reflecting: out.bytes).children.map { $0.value as! UInt8 }
        switch Self.typeString(info.keyInfo.dataType) {
        case "flt ":
            let raw = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
            return Double(Float(bitPattern: raw))
        case "fpe2":
            return Double((UInt16(b[0]) << 8 | UInt16(b[1])) >> 2)
        case "sp78":
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256.0
        case "ui8 ":
            return Double(b[0])
        case "ui16":
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32":
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        default:
            return nil
        }
    }
}

// MARK: - Public service

struct FanReading: Identifiable {
    let id: Int
    let rpm: Double
    let maxRPM: Double?
    var fraction: Double? { maxRPM.map { $0 > 0 ? rpm / $0 : 0 } }
}

/// CPU temperature and fan speeds, sampled on demand.
/// Temperature: Intel SMC keys first, then Apple Silicon die sensors (averaged).
/// Fans: SMC on both architectures. All values may be nil/empty on Macs
/// (or VMs) where the sensors aren't readable — the UI hides them then.
final class Sensors: ObservableObject {
    static let shared = Sensors()

    @Published var cpuTemperature: Double?
    @Published var fans: [FanReading] = []

    private lazy var smc = SMCConnection()
    private lazy var hid = HIDTemperatureReader()
    private static let intelCPUKeys = ["TC0P", "TC0E", "TC0F", "TCXC", "TC0D"]
    private var timer: Timer?

    /// Continuous sampling so the menu bar label can show live sensor bars.
    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func sample() {
        DispatchQueue.global(qos: .utility).async { [self] in
            let temp = readTemperature()
            let fanList = readFans()
            DispatchQueue.main.async {
                self.cpuTemperature = temp
                self.fans = fanList
            }
        }
    }

    private func readTemperature() -> Double? {
        // Intel: a single SMC proximity/die key is the canonical reading.
        if let smc {
            for key in Self.intelCPUKeys {
                if let v = smc.readNumber(key), v > 0, v < 120 { return v }
            }
        }
        // Apple Silicon: average the CPU die sensors.
        let all = hid.readAll()
        var dies = all.filter { $0.name.lowercased().contains("tdie") }.map(\.celsius)
        if dies.isEmpty {
            dies = all.filter { $0.name.contains("ACC MTR Temp") }.map(\.celsius)
        }
        let valid = dies.filter { $0 > 0 && $0 < 120 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private func readFans() -> [FanReading] {
        guard let smc, let count = smc.readNumber("FNum"), count > 0 else { return [] }
        return (0..<Int(count)).compactMap { i in
            guard let rpm = smc.readNumber("F\(i)Ac") else { return nil }
            return FanReading(id: i, rpm: rpm, maxRPM: smc.readNumber("F\(i)Mx"))
        }
    }
}
