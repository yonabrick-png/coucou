#if !APPSTORE
import AppKit
import CoreAudio
import AudioToolbox

// MARK: - Volume and brightness keys → the notch (GitHub build only)

/// Catches the volume, mute and brightness keys, changes the level itself and shows a bar in
/// the notch instead of macOS's own box. Anything it can't handle — no Accessibility, an output
/// without a volume control, an external display, the island open — goes on to macOS untouched,
/// so the keys never stop working. Steps of 1/16 like macOS, 1/64 with ⇧⌥.
@MainActor
final class MediaKeys {
    static let shared = MediaKeys()

    private var tap: CFMachPort?
    private var trustTimer: Timer?

    // NX_KEYTYPE_* (IOKit/hidsystem/ev_keymap.h)
    nonisolated private static let soundUp: Int32 = 0
    nonisolated private static let soundDown: Int32 = 1
    nonisolated private static let brightnessUp: Int32 = 2
    nonisolated private static let brightnessDown: Int32 = 3
    nonisolated private static let mute: Int32 = 7

    private init() {}

    /// Installs the key tap; without Accessibility, checks again every 10 s until it's granted.
    func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            trustTimer?.invalidate()
            trustTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
                Task { @MainActor in
                    guard AXIsProcessTrusted() else { return }
                    MediaKeys.shared.trustTimer?.invalidate()
                    MediaKeys.shared.trustTimer = nil
                    MediaKeys.shared.start()
                }
            }
            return
        }
        let mask = CGEventMask(1 << 14)   // NX_SYSDEFINED: media and brightness keys
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: mediaKeyCallback, userInfo: nil) else { return }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    /// macOS turns a slow tap off: turn it back on.
    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns true when the key was handled (and must not reach macOS).
    fileprivate func handle(key: Int32, down: Bool, fine: Bool) -> Bool {
        // The island is open, or hidden by Meeting / Night: let macOS show its own box
        guard AppState.shared.mode != .expanded, !NotchModes.shared.hidesIsland else { return false }
        switch key {
        case Self.soundUp, Self.soundDown, Self.mute:
            guard let device = Volume.defaultOutput(), Volume.hasVolume(device) else { return false }
            if down {
                if key == Self.mute {
                    Volume.setMuted(device, !Volume.isMuted(device))
                } else {
                    let step: Float = fine ? 1.0 / 64 : 1.0 / 16
                    let now = Volume.get(device)
                    let next = min(1, max(0, now + (key == Self.soundUp ? step : -step)))
                    Volume.set(device, next)
                    if key == Self.soundUp { Volume.setMuted(device, false) }
                }
                showVolume(device)
            }
            return true
        case Self.brightnessUp, Self.brightnessDown:
            guard let display = Brightness.builtinDisplay(), let now = Brightness.get(display) else { return false }
            if down {
                let step: Float = fine ? 1.0 / 64 : 1.0 / 16
                let next = min(1, max(0, now + (key == Self.brightnessUp ? step : -step)))
                guard Brightness.set(display, next) else { return false }
                DeviceHUD.shared.show(DeviceHUD.HUD(
                    id: "brightness",
                    icon: next < 0.34 ? "sun.min.fill" : "sun.max.fill",
                    value: "\(Int((next * 100).rounded()))%", tint: "#FBBF24",
                    detail: String(localized: "Brightness"), level: Double(next)), for: 1.4)
            }
            return true
        default:
            return false
        }
    }

    private func showVolume(_ device: AudioDeviceID) {
        let muted = Volume.isMuted(device)
        let level = muted ? 0 : Volume.get(device)
        let icon: String
        switch level {
        case 0:        icon = "speaker.slash.fill"
        case ..<0.34:  icon = "speaker.wave.1.fill"
        case ..<0.67:  icon = "speaker.wave.2.fill"
        default:       icon = "speaker.wave.3.fill"
        }
        DeviceHUD.shared.show(DeviceHUD.HUD(
            id: "volume", icon: icon, value: "\(Int((level * 100).rounded()))%",
            tint: muted ? "#8E939C" : "#F5F6F8", detail: String(localized: "Volume"),
            level: Double(level)), for: 1.4)
    }
}

/// The event tap callback: media keys arrive as NX_SYSDEFINED events, subtype 8.
private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { MediaKeys.shared.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
        return Unmanaged.passUnretained(event)
    }
    let data = ns.data1
    let key = Int32((data & 0xFFFF0000) >> 16)
    let state = (data & 0x0000FF00) >> 8
    let down = state == 0xA
    let fine = ns.modifierFlags.contains([.shift, .option])
    let handled = MainActor.assumeIsolated { MediaKeys.shared.handle(key: key, down: down, fine: fine) }
    return handled ? nil : Unmanaged.passUnretained(event)
}

// MARK: - Volume (CoreAudio)

private enum Volume {
    static func defaultOutput() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return err == noErr && id != 0 ? id : nil
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Some outputs (HDMI, some USB) have no volume: leave those to macOS.
    static func hasVolume(_ device: AudioDeviceID) -> Bool {
        var addr = volumeAddress
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &addr)
            && AudioObjectIsPropertySettable(device, &addr, &settable) == noErr && settable.boolValue
    }

    static func get(_ device: AudioDeviceID) -> Float {
        var addr = volumeAddress
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return value
    }

    static func set(_ device: AudioDeviceID, _ value: Float) {
        var addr = volumeAddress
        var v = Float32(value)
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        var addr = muteAddress
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return value != 0
    }

    static func setMuted(_ device: AudioDeviceID, _ muted: Bool) {
        var addr = muteAddress
        guard AudioObjectHasProperty(device, &addr) else { return }
        var v = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }
}

// MARK: - Brightness (built-in display, DisplayServices)

/// The built-in display's brightness through DisplayServices (what Control Center uses).
/// Loaded at run time; if it's missing, brightness keys simply go on to macOS.
private enum Brightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    // Loaded once and never changed: safe to read from anywhere.
    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFn: GetFn? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn: SetFn? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFn.self) }

    static func builtinDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func get(_ display: CGDirectDisplayID) -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? value : nil
    }

    static func set(_ display: CGDirectDisplayID, _ value: Float) -> Bool {
        guard let setFn else { return false }
        return setFn(display, value) == 0
    }
}
#endif
