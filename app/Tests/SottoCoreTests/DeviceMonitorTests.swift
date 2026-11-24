import Testing
@testable import SottoCore

private final class FakeAudioSystem: AudioSystem {
    var devices: [MicDevice]
    var defaultInputUID: String
    var listener: ((AudioSystemChange) -> Void)?
    var isSottoMicrophoneInUse = false
    func activeMicrophoneUses() -> [MicrophoneUse] { [] }
    func setSottoMicrophoneHidden(_ hidden: Bool) {}
    init(devices: [MicDevice], defaultInputUID: String) {
        self.devices = devices
        self.defaultInputUID = defaultInputUID
    }
    func inputDevices() -> [MicDevice] { devices }
    func defaultInputDeviceUID() -> String { defaultInputUID }
    func onChange(_ cb: @escaping (AudioSystemChange) -> Void) { listener = cb }
    func simulateChange() { listener?(.devices) }
}

private let builtin = MicDevice(uid: "BuiltInMic", name: "MacBook Air Microphone")
private let airpods = MicDevice(uid: "AirPods", name: "AirPods Pro")
private let sotto = MicDevice(uid: "SottoMicrophone", name: "Sotto Microphone")

@Test func excludesSottoAndListsPhysicalInputs() {
    let sys = FakeAudioSystem(devices: [builtin, airpods, sotto], defaultInputUID: "BuiltInMic")
    let m = DeviceMonitor(system: sys)
    #expect(m.physicalInputs.map(\.uid) == ["BuiltInMic", "AirPods"])
}

@Test func fallsBackToDefaultWhenSelectedRemoved() {
    let sys = FakeAudioSystem(devices: [builtin, airpods, sotto], defaultInputUID: "BuiltInMic")
    let m = DeviceMonitor(system: sys)
    m.select(uid: "AirPods")
    var changes: [AudioSystemChange] = []
    m.onChange = { changes.append($0) }
    // AirPods disconnect; default is the built-in mic.
    sys.devices = [builtin, sotto]
    sys.simulateChange()
    #expect(changes == [.devices])
    #expect(m.selectedUID == "BuiltInMic")
}
