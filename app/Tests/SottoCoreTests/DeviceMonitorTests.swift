import Testing
@testable import SottoCore

private final class FakeAudioSystem: AudioSystem {
    var devices: [MicDevice]
    var defaultInputUID: String
    var listener: (() -> Void)?
    init(devices: [MicDevice], defaultInputUID: String) {
        self.devices = devices
        self.defaultInputUID = defaultInputUID
    }
    func inputDevices() -> [MicDevice] { devices }
    func defaultInputDeviceUID() -> String { defaultInputUID }
    func onDevicesChanged(_ cb: @escaping () -> Void) { listener = cb }
    func simulateChange() { listener?() }
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
    var rebuilt: [MicDevice] = []
    m.onNeedRebuild = { rebuilt.append($0) }
    // AirPods disconnect; default is the built-in mic.
    sys.devices = [builtin, sotto]
    sys.simulateChange()
    #expect(rebuilt.count == 1)
    #expect(rebuilt.first?.uid == "BuiltInMic")
    #expect(m.selectedUID == "BuiltInMic")
}
