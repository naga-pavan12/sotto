import Foundation
import CoreAudio
import SottoCore
import Observation

/// Drives the engine from UI state and surfaces status. Starts processing only
/// while some app is reading Sotto Microphone (the driver's 'sRun' property).
@MainActor
@Observable
final class AppModel {
    var enabled = true { didSet { reconcile() } }
    var strength = 80 { didSet { engine?.strength = strength; persist() } }
    var selectedMicUID: String = ""
    var statusLine = "Idle"
    var inputs: [MicDevice] = []

    private var engine: AudioEngine?
    private let monitor = DeviceMonitor(system: CoreAudioSystem())
    private var running = false

    init() {
        strength = UserDefaults.standard.object(forKey: "strength") as? Int ?? 80
        enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        inputs = monitor.physicalInputs
        selectedMicUID = UserDefaults.standard.string(forKey: "selectedMicUID")
            ?? monitor.physicalInputs.first?.uid ?? ""
        monitor.select(uid: selectedMicUID)
        monitor.onNeedRebuild = { [weak self] dev in
            guard let self else { return }
            self.selectedMicUID = dev.uid
            self.inputs = self.monitor.physicalInputs
            if self.running { self.restart() }
        }
        setMicHidden(false)
        reconcile()
    }

    func selectMic(_ uid: String) {
        selectedMicUID = uid
        monitor.select(uid: uid)
        UserDefaults.standard.set(uid, forKey: "selectedMicUID")
        if running { restart() }
    }

    private func persist() {
        UserDefaults.standard.set(strength, forKey: "strength")
        UserDefaults.standard.set(enabled, forKey: "enabled")
    }

    private func reconcile() {
        persist()
        guard !selectedMicUID.isEmpty else { stop(); return }
        start()                          // keep the engine running whenever a mic is chosen
        engine?.bypass = !enabled        // off => pass the raw mic through, never silence
        statusLine = running
            ? (enabled ? "Active · cleaning \(micName(selectedMicUID))"
                       : "Off · passing through \(micName(selectedMicUID))")
            : statusLine
    }

    private func start() {
        guard !running else { return }
        guard let e = AudioEngine() else { statusLine = "Denoiser failed to load"; return }
        e.strength = strength
        do {
            try e.start(micUID: selectedMicUID)
            engine = e
            running = true
            statusLine = "Active · cleaning \(micName(selectedMicUID))"
        } catch {
            statusLine = "Start failed: \(error)"
        }
    }

    private func stop() {
        engine?.stop()
        engine = nil
        running = false
        statusLine = "Off"
    }

    private func restart() { stop(); start() }

    func setBypass(_ on: Bool) { engine?.bypass = on }

    private func micName(_ uid: String) -> String {
        inputs.first(where: { $0.uid == uid })?.name ?? uid
    }

    // Toggle the driver's mic-hidden custom property ('sHid').
    private func setMicHidden(_ hidden: Bool) {
        guard let dev = AudioEngine.deviceID(uid: "SottoMicrophone") else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(UInt32(bigEndian: 0x73486964)), // 'sHid'
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = hidden ? 1 : 0
        let cf = CFNumberCreate(nil, .intType, &value)
        var plist: CFPropertyList? = cf
        withUnsafeMutablePointer(to: &plist) { p in
            _ = AudioObjectSetPropertyData(dev, &addr, 0, nil,
                UInt32(MemoryLayout<CFPropertyList?>.size), p)
        }
    }

    func willQuit() { stop(); setMicHidden(true) }
}
