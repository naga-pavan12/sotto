import Foundation
import Observation
import SottoCore

protocol CaptureEngine: AnyObject {
    var strength: Int { get set }
    var bypass: Bool { get set }
    func start(micUID: String) throws
    func stop()
}

extension AudioEngine: CaptureEngine {}

@MainActor
@Observable
final class AppModel {
    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "enabled")
            if !enabled { comparing = false }
            updateBypass()
        }
    }
    var strength: Int {
        didSet {
            defaults.set(strength, forKey: "strength")
            engine?.strength = strength
        }
    }

    private(set) var selectedMicUID: String
    private(set) var inputs: [MicDevice]
    private var engine: CaptureEngine?
    private(set) var microphoneUses: [String] = []
    private var startError: String?
    private var comparing = false
    private let system: AudioSystem
    private let monitor: DeviceMonitor
    private let defaults: UserDefaults
    private let makeEngine: () -> CaptureEngine?

    var isCapturing: Bool { engine != nil }

    var statusLine: String {
        if let startError { return startError }
        guard !selectedMicUID.isEmpty else { return "No microphone available for Sotto" }
        guard isCapturing else { return "Sotto Microphone is idle" }
        return enabled && !comparing ? "Sotto Microphone · cleaning audio" : "Sotto Microphone · original audio"
    }

    init(system: AudioSystem = CoreAudioSystem(), defaults: UserDefaults = .standard,
         makeEngine: @escaping () -> CaptureEngine? = { AudioEngine() }) {
        self.system = system
        self.defaults = defaults
        self.makeEngine = makeEngine
        let monitor = DeviceMonitor(system: system)
        self.monitor = monitor
        if let saved = defaults.string(forKey: "selectedMicUID") { monitor.select(uid: saved) }
        selectedMicUID = monitor.selectedUID ?? ""
        inputs = monitor.physicalInputs
        strength = defaults.object(forKey: "strength") as? Int ?? 90
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        monitor.onChange = { [weak self] change in
            guard let self else { return }
            if change == .serviceRestarted { self.stop() }
            if change != .microphoneActivity {
                self.inputs = self.monitor.physicalInputs
                self.startError = nil
            }
            self.reconcile()
            self.refreshMicrophoneUses()
        }
        reconcile()
        refreshMicrophoneUses()
    }

    func selectMic(_ uid: String) {
        monitor.select(uid: uid)
        defaults.set(monitor.selectedUID, forKey: "selectedMicUID")
        reconcile()
    }

    func compareOriginal(_ pressed: Bool) {
        comparing = enabled && pressed
        updateBypass()
    }

    private func updateBypass() { engine?.bypass = !enabled || comparing }

    private func refreshMicrophoneUses() {
        let uses = system.activeMicrophoneUses().map { use in
            switch use {
            case let .app(app, microphone?): "\(app) is using \(microphone)"
            case let .app(app, nil): "\(app) is using a microphone"
            case let .device(name, hasOutput: true): "\(name) is active (input or output)"
            case let .device(name, hasOutput: false): "\(name) is in use"
            }
        }
        microphoneUses = Set(uses).sorted()
    }

    private func reconcile() {
        let uid = monitor.selectedUID ?? ""
        if selectedMicUID != uid {
            stop()
            selectedMicUID = uid
        }
        guard !uid.isEmpty, system.isSottoMicrophoneInUse else {
            stop()
            return
        }
        guard engine == nil, startError == nil else { return }
        guard let candidate = makeEngine() else { startError = "Denoiser failed to load"; return }
        candidate.strength = strength
        candidate.bypass = !enabled || comparing
        do {
            try candidate.start(micUID: uid)
            engine = candidate
            startError = nil
        } catch {
            candidate.stop()
            startError = "Start failed: \(error)"
        }
    }

    private func stop() {
        engine?.stop()
        engine = nil
        startError = nil
    }

    func willQuit() {
        monitor.onChange = nil
        stop()
        system.setSottoMicrophoneHidden(true)
    }
}
