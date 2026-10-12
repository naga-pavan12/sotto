import CoreAudio
import Foundation

/// Core Audio HAL implementation of `AudioSystem`. Lists real input devices,
/// resolves the default input, and fires on device-list / default-input changes
/// and after a coreaudiod restart.
public final class CoreAudioSystem: AudioSystem {
    private var callback: (() -> Void)?

    public init() { installListeners() }

    public func inputDevices() -> [MicDevice] {
        allDeviceIDs().compactMap { id in
            guard hasInputStreams(id) else { return nil }
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

    public func onDevicesChanged(_ cb: @escaping () -> Void) { callback = cb }

    // MARK: - HAL helpers

    private func installListeners() {
        for selector in [kAudioHardwarePropertyDevices,
                         kAudioHardwarePropertyDefaultInputDevice,
                         kAudioHardwarePropertyServiceRestarted] {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
                self?.callback?()
            }
        }
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var size = UInt32(0)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids
    }

    private func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var size = UInt32(0)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
        return size > 0
    }

    private func stringProp(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var ref: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let st = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ref)
        if st == noErr, let s = ref as String? { return s }
        return nil
    }
}
