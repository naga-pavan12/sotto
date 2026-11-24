import AppKit
import CoreAudio
import Foundation

/// Observes input routes and virtual microphone demand on the main queue.
public final class CoreAudioSystem: AudioSystem {
    private var callback: ((AudioSystemChange) -> Void)?
    private var systemListeners: [PropertyListener] = []
    private var activityListener: PropertyListener?
    private var inputListeners: [AudioObjectID: [PropertyListener]] = [:]
    private var hasProcessList = false
    private var microphoneID: AudioDeviceID?

    public init() {
        installListeners()
        observeMicrophone()
        observeInputClients()
    }

    public func inputDevices() -> [MicDevice] {
        deviceIDs().compactMap { id in
            guard hasStreams(id, scope: kAudioObjectPropertyScopeInput) else { return nil }
            guard let uid = stringProp(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = stringProp(id, kAudioObjectPropertyName) ?? uid
            return MicDevice(uid: uid, name: name)
        }
    }

    public func defaultInputDeviceUID() -> String {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return stringProp(id, kAudioDevicePropertyDeviceUID) ?? ""
    }

    public func onChange(_ callback: @escaping (AudioSystemChange) -> Void) {
        self.callback = callback
    }

    // Only call apps run I/O on the virtual input. Our own output uses Sotto Bridge.
    public var isSottoMicrophoneInUse: Bool {
        guard let microphoneID else { return false }
        return uintProperty(microphoneID, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
    }

    public func activeMicrophoneUses() -> [MicrophoneUse] {
        if !hasProcessList {
            // A running duplex device may be playing sound without capturing input.
            return inputListeners.keys.compactMap { id in
                guard uintProperty(id, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1,
                      let name = stringProp(id, kAudioObjectPropertyName) else { return nil }
                return .device(name, hasOutput: hasStreams(id, scope: kAudioObjectPropertyScopeOutput))
            }
        }
        var uses: [MicrophoneUse] = []
        for process in inputListeners.keys {
            guard uintProperty(process, kAudioProcessPropertyIsRunningInput) == 1,
                  let pid = uintProperty(process, kAudioProcessPropertyPID), pid != UInt32(getpid())
            else { continue }
            let name = NSRunningApplication(processIdentifier: pid_t(bitPattern: pid))?.localizedName
                ?? stringProp(process, kAudioProcessPropertyBundleID)
            let app = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Process \(pid)"
            let devices = objectIDs(process, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)
            let names = (devices ?? []).compactMap { stringProp($0, kAudioObjectPropertyName) }
            if names.isEmpty { uses.append(.app(app, microphone: nil)) }
            uses += names.map { .app(app, microphone: $0) }
        }
        return uses
    }

    public func setSottoMicrophoneHidden(_ hidden: Bool) {
        guard let microphoneID else { return }
        var address = Self.address(0x73486964) // 'sHid'
        var value: CFPropertyList = NSNumber(value: hidden ? 1 : 0)
        withUnsafePointer(to: &value) {
            _ = AudioObjectSetPropertyData(microphoneID, &address, 0, nil,
                                           UInt32(MemoryLayout<CFPropertyList>.size), $0)
        }
    }

    // MARK: - HAL helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private final class PropertyListener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock

        init?(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
              scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
              _ block: @escaping AudioObjectPropertyListenerBlock) {
            self.object = object
            self.address = CoreAudioSystem.address(selector, scope: scope)
            self.block = block
            guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr
            else { return nil }
        }

        deinit { AudioObjectRemovePropertyListenerBlock(object, &address, .main, block) }
    }

    private func installListeners() {
        var selectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
                         kAudioHardwarePropertyServiceRestarted]
        var processList = Self.address(kAudioHardwarePropertyProcessObjectList)
        hasProcessList = AudioObjectHasProperty(AudioObjectID(kAudioObjectSystemObject), &processList)
        if hasProcessList { selectors.append(kAudioHardwarePropertyProcessObjectList) }
        systemListeners = selectors.compactMap { selector in
            PropertyListener(AudioObjectID(kAudioObjectSystemObject), selector) { [weak self] _, _ in
                guard let self else { return }
                if selector == kAudioHardwarePropertyProcessObjectList {
                    self.observeInputClients()
                    self.callback?(.microphoneActivity)
                    return
                }
                let restarted = selector == kAudioHardwarePropertyServiceRestarted
                if restarted {
                    self.systemListeners.removeAll()
                    self.inputListeners.removeAll()
                    self.activityListener = nil
                    self.installListeners()
                }
                self.observeMicrophone()
                self.observeInputClients()
                self.callback?(restarted ? .serviceRestarted : .devices)
            }
        }
    }

    private func observeMicrophone() {
        let id = AudioEngine.deviceID(uid: "SottoMicrophone")
        guard id != microphoneID || activityListener == nil else { return }
        activityListener = nil
        microphoneID = id
        guard let id else { return }
        activityListener = PropertyListener(id, kAudioDevicePropertyDeviceIsRunningSomewhere) {
            [weak self] _, _ in self?.callback?(.microphoneActivity)
        }
        setSottoMicrophoneHidden(false)
    }

    private func observeInputClients() {
        let objects: [AudioObjectID]
        if hasProcessList {
            objects = objectIDs(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) ?? []
        } else {
            objects = deviceIDs().filter { hasStreams($0, scope: kAudioObjectPropertyScopeInput) }
        }
        let current = Set(objects)
        inputListeners = inputListeners.filter { current.contains($0.key) }
        let changed: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.callback?(.microphoneActivity) }
        for id in current where inputListeners[id] == nil {
            if hasProcessList {
                inputListeners[id] = [
                    PropertyListener(id, kAudioProcessPropertyIsRunningInput, changed),
                    PropertyListener(id, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeWildcard, changed),
                ].compactMap { $0 }
            } else {
                inputListeners[id] = [PropertyListener(id, kAudioDevicePropertyDeviceIsRunningSomewhere, changed)].compactMap { $0 }
            }
        }
    }

    private func deviceIDs() -> [AudioDeviceID] {
        objectIDs(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices) ?? []
    }

    private func objectIDs(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                           scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID]? {
        var address = Self.address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return nil }
        guard size > 0 else { return [] }
        let stride = MemoryLayout<AudioObjectID>.stride
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / stride)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &ids) == noErr else { return nil }
        return Array(ids.prefix(Int(size) / stride))
    }

    private func uintProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = Self.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func hasStreams(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var size: UInt32 = 0
        var address = Self.address(kAudioDevicePropertyStreams, scope: scope)
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private func stringProp(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: ref))
        var address = Self.address(selector)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &ref) == noErr else { return nil }
        return ref?.takeRetainedValue() as String?
    }
}
