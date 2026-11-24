import Foundation

public struct MicDevice: Equatable, Sendable {
    public let uid: String
    public let name: String
    public init(uid: String, name: String) { self.uid = uid; self.name = name }
}

public enum AudioSystemChange {
    case devices, serviceRestarted, microphoneActivity
}

/// Input routes reported by Core Audio. Older systems expose device activity only.
public enum MicrophoneUse: Hashable {
    case app(String, microphone: String?)
    case device(String, hasOutput: Bool)
}

public protocol AudioSystem {
    func inputDevices() -> [MicDevice]
    func defaultInputDeviceUID() -> String
    var isSottoMicrophoneInUse: Bool { get }
    func activeMicrophoneUses() -> [MicrophoneUse]
    func setSottoMicrophoneHidden(_ hidden: Bool)
    func onChange(_ callback: @escaping (AudioSystemChange) -> Void)
}

/// Tracks the selected physical input and falls back to an available mic on disconnect.
public final class DeviceMonitor {
    private let system: AudioSystem
    public private(set) var physicalInputs: [MicDevice] = []
    public private(set) var selectedUID: String?
    public var onChange: ((AudioSystemChange) -> Void)?

    public init(system: AudioSystem) {
        self.system = system
        refreshInputs()
        system.onChange { [weak self] change in
            guard let self else { return }
            if change != .microphoneActivity { self.refreshInputs() }
            self.onChange?(change)
        }
    }

    public func select(uid: String) {
        if physicalInputs.contains(where: { $0.uid == uid }) { selectedUID = uid }
    }

    private func refreshInputs() {
        physicalInputs = system.inputDevices().filter { !$0.uid.hasPrefix("Sotto") }
        if physicalInputs.contains(where: { $0.uid == selectedUID }) { return }
        let defaultUID = system.defaultInputDeviceUID()
        selectedUID = (physicalInputs.first { $0.uid == defaultUID } ?? physicalInputs.first)?.uid
    }
}
