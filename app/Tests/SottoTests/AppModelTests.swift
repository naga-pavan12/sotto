import Foundation
import SottoCore
import Testing
@testable import Sotto

private final class TestAudioSystem: AudioSystem {
    var devices = [MicDevice(uid: "builtin", name: "Built-in"), MicDevice(uid: "usb", name: "USB")]
    var isSottoMicrophoneInUse = false
    var uses: [MicrophoneUse] = []
    func activeMicrophoneUses() -> [MicrophoneUse] { uses }
    var changed: ((AudioSystemChange) -> Void)?
    var hidden = false

    func inputDevices() -> [MicDevice] { devices }
    func defaultInputDeviceUID() -> String { "builtin" }
    func onChange(_ callback: @escaping (AudioSystemChange) -> Void) { changed = callback }
    func setSottoMicrophoneHidden(_ hidden: Bool) { self.hidden = hidden }

    func setRecording(_ value: Bool) {
        isSottoMicrophoneInUse = value
        changed?(.microphoneActivity)
    }
}

private final class TestEngine: CaptureEngine {
    var strength = 0
    var bypass = false
    var startedUID: String?
    var bypassAtStart = false
    var stopped = false

    func start(micUID: String) throws {
        startedUID = micUID
        bypassAtStart = bypass
    }
    func stop() { stopped = true }
}

@MainActor
@Test func activityControlsCaptureAndSwitchControlsOnlyCancellation() {
    let system = TestAudioSystem()
    let suite = UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var engines: [TestEngine] = []
    let model = AppModel(system: system, defaults: defaults) {
        let engine = TestEngine()
        engines.append(engine)
        return engine
    }

    system.uses = [.app("Meeting", microphone: "Built-in")]
    system.changed?(.microphoneActivity)
    #expect(model.microphoneUses == ["Meeting is using Built-in"])
    #expect(model.statusLine == "Sotto Microphone is idle")
    model.enabled = false
    model.selectMic("usb")
    #expect(engines.isEmpty)
    system.uses = [.app("Meeting", microphone: "Sotto Microphone"), .app("Recorder", microphone: "USB")]
    system.setRecording(true)
    #expect(model.microphoneUses == ["Meeting is using Sotto Microphone", "Recorder is using USB"])
    #expect(engines.count == 1)
    #expect(engines.first?.startedUID == "usb")
    #expect(engines.first?.bypassAtStart == true)
    model.enabled = true
    #expect(engines.first?.bypass == false)
    model.compareOriginal(true)
    #expect(engines.first?.bypass == true)
    model.enabled = false
    model.compareOriginal(false)
    #expect(engines.first?.bypass == true)
    system.setRecording(true)
    #expect(engines.count == 1)
    #expect(engines.first?.stopped == false)

    system.setRecording(false)
    #expect(engines.first?.stopped == true)
    #expect(!model.isCapturing)
    model.enabled = true
    #expect(engines.count == 1)
    system.setRecording(true)
    #expect(engines.count == 2)
    #expect(engines.last?.bypassAtStart == false)
}

@MainActor
@Test func alreadyRecordingAtLaunchAndInputChangesRespectDemand() {
    let system = TestAudioSystem()
    system.isSottoMicrophoneInUse = true
    let suite = UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "enabled")
    var engines: [TestEngine] = []
    let model = AppModel(system: system, defaults: defaults) {
        let engine = TestEngine()
        engines.append(engine)
        return engine
    }
    #expect(model.isCapturing)
    #expect(engines.first?.bypassAtStart == true)

    model.selectMic("usb")
    #expect(engines.count == 2)
    #expect(engines.first?.stopped == true)
    #expect(engines.last?.startedUID == "usb")
    #expect(engines.last?.bypassAtStart == true)
    system.devices = []
    system.changed?(.devices)
    #expect(!model.isCapturing)
    #expect(engines.last?.stopped == true)
    system.devices = [MicDevice(uid: "builtin", name: "Built-in")]
    system.changed?(.devices)
    #expect(engines.count == 3)
    #expect(engines.last?.startedUID == "builtin")

    model.willQuit()
    #expect(system.hidden)
    #expect(engines.last?.stopped == true)
    system.setRecording(true)
    #expect(engines.count == 3)
}
