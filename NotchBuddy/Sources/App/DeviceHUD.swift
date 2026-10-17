#if !APPSTORE
import SwiftUI
import IOKit.ps
import IOBluetooth

// MARK: - Device HUD (battery and headphones, GitHub build only)

/// A few seconds of news in the closed notch: plugged in / unplugged with the battery level,
/// low battery (20 % and 10 %, once each), and headphones connecting with their battery.
/// Event-driven only: a power-source callback and Bluetooth connect notifications.
@MainActor
final class DeviceHUD: ObservableObject {
    static let shared = DeviceHUD()

    struct HUD: Equatable {
        let id = UUID()
        let icon: String
        let value: String
        let tint: String
        let detail: String
    }

    @Published private(set) var current: HUD?

    private var hideTask: Task<Void, Never>?
    private var lastOnAC: Bool?
    private var warnedLevels: Set<Int> = []
    private let bluetooth = BluetoothWatcher()

    private init() {
        lastOnAC = Self.battery()?.onAC
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            Task { @MainActor in DeviceHUD.shared.powerChanged() }
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        bluetooth.start()
    }

    func show(_ hud: HUD, for seconds: Double = 4) {
        current = hud
        NotificationCenter.default.post(name: .hookReveal, object: nil)
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.current = nil }
        }
    }

    // MARK: Battery

    struct Battery { let percent: Int; let onAC: Bool; let charging: Bool }

    nonisolated static func battery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return Battery(percent: Int((Double(cur) / Double(max) * 100).rounded()),
                           onAC: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                           charging: d[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil   // a Mac without a battery
    }

    private func powerChanged() {
        guard let b = Self.battery() else { return }
        defer { lastOnAC = b.onAC }
        if let was = lastOnAC, was != b.onAC {
            if b.onAC { warnedLevels = [] }
            show(HUD(icon: b.onAC ? "bolt.fill" : "battery.75percent",
                     value: "\(b.percent)%",
                     tint: b.onAC ? "#22C55E" : "#F5F6F8",
                     detail: b.onAC ? String(localized: "Charging") : String(localized: "On battery")))
            return
        }
        // Low battery, once per level until plugged in again
        if !b.onAC {
            for level in [10, 20] where b.percent <= level && !warnedLevels.contains(level) {
                warnedLevels.insert(level)
                SoundEngine.shared.play("error")
                show(HUD(icon: level == 10 ? "battery.0percent" : "battery.25percent",
                         value: "\(b.percent)%", tint: level == 10 ? "#F4505E" : "#F5A524",
                         detail: String(localized: "Battery low")), for: 6)
                break
            }
        }
    }

    // MARK: Headphones

    fileprivate func headphonesConnected(name: String, address: String) {
        // macOS fills in the battery levels a moment after the connection
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            let levels = await Self.headphoneBattery(address: address, name: name)
            let value = levels.map { "\($0)%" } ?? "✓"
            show(HUD(icon: name.lowercased().contains("airpods") ? "airpods" : "headphones",
                     value: value, tint: "#F5F6F8", detail: name))
        }
    }

    /// Lowest of the earbuds' (or the headset's) battery levels, from `system_profiler`.
    nonisolated static func headphoneBattery(address: String, name: String) async -> Int? {
        await Task.detached { () -> Int? in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let top = (json["SPBluetoothDataType"] as? [[String: Any]])?.first,
                  let connected = top["device_connected"] as? [[String: Any]] else { return nil }
            let wanted = address.uppercased().replacingOccurrences(of: "-", with: ":")
            for entry in connected {
                for (devName, value) in entry {
                    guard let d = value as? [String: Any] else { continue }
                    let addr = (d["device_address"] as? String ?? "").uppercased()
                    guard addr == wanted || devName == name else { continue }
                    let keys = ["device_batteryLevelLeft", "device_batteryLevelRight", "device_batteryLevelMain"]
                    let levels = keys.compactMap { (d[$0] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
                    return levels.min()
                }
            }
            return nil
        }.value
    }
}

/// IOBluetooth delivers connect notifications to an Objective-C selector.
final class BluetoothWatcher: NSObject {
    private var token: IOBluetoothUserNotification?

    func start() {
        token = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Audio devices only (major class 0x04: headphones, earbuds, speakers)
        guard device.deviceClassMajor == 0x04 else { return }
        let name = device.name ?? "Headphones"
        let address = device.addressString ?? ""
        Task { @MainActor in DeviceHUD.shared.headphonesConnected(name: name, address: address) }
    }
}

// MARK: - Closed notch view

struct CompactDeviceHUD: View {
    let hud: DeviceHUD.HUD

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: hud.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color(hex: hud.tint))
                .symbolEffect(.pulse, options: .repeat(2))
            Text(hud.value)
                .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(Color(hex: "#F5F6F8"))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 32, height: 28)
        .help(hud.detail)
    }
}
#endif
