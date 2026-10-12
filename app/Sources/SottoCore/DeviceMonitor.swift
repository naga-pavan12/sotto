import Foundation

public struct MicDevice: Equatable, Sendable {
    public let uid: String
    public let name: String
    public init(uid: String, name: String) { self.uid = uid; self.name = name }
}

/// Audio-system access, injectable so DeviceMonitor is testable without hardware.
public protocol AudioSystem {
    func inputDevices() -> [MicDevice]
    func defaultInputDeviceUID() -> String
    func onDevicesChanged(_ cb: @escaping () -> Void)
}

/// Tracks the physical input devices and the user's selected mic. When the
/// selected mic disappears (AirPods unplug, USB removed), it falls back to the
/// system default (then the first available input) and asks for an engine rebuild.
public final class DeviceMonitor {
    private let system: AudioSystem
    private var cachedInputs: [MicDevice] = []

    public private(set) var selectedUID: String?
    public var onNeedRebuild: ((MicDevice) -> Void)?

    public init(system: AudioSystem) {
        self.system = system
        cachedInputs = Self.physicalOnly(system.inputDevices())
        system.onDevicesChanged { [weak self] in self?.handleChange() }
    }

    public var physicalInputs: [MicDevice] { cachedInputs }

    public func select(uid: String) { selectedUID = uid }

    /// Sotto's own virtual devices are never offered as a physical input.
    private static func physicalOnly(_ devices: [MicDevice]) -> [MicDevice] {
        devices.filter { !$0.uid.hasPrefix("Sotto") }
    }

    private func handleChange() {
        cachedInputs = Self.physicalOnly(system.inputDevices())
        guard let sel = selectedUID,
              !cachedInputs.contains(where: { $0.uid == sel }) else { return }
        let defaultUID = system.defaultInputDeviceUID()
        let fallback = cachedInputs.first(where: { $0.uid == defaultUID }) ?? cachedInputs.first
        if let fb = fallback {
            selectedUID = fb.uid
            onNeedRebuild?(fb)
        }
    }
}
