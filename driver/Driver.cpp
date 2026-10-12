// Sotto HAL audio-server plug-in.
//
// Presents two devices:
//   "Sotto Microphone" — visible input; call apps read cleaned audio here.
//   "Sotto Bridge"     — hidden output; only the authorized Sotto app writes
//                        cleaned audio here, which the driver loops to the mic.
//
// Task 7 builds the skeleton (devices, formats, custom-property registration).
// The bridge->mic audio path and live property values land in Task 8.

#include <aspl/Driver.hpp>

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>

#include <atomic>
#include <memory>

#include "auth.hpp"

namespace {

constexpr UInt32 kSampleRate = 48000;
constexpr char kMicUID[] = "SottoMicrophone";
constexpr char kBridgeUID[] = "SottoBridge";

// Custom property selectors (FourCharCodes).
constexpr AudioObjectPropertySelector kPropRunning = 'sRun';
constexpr AudioObjectPropertySelector kPropBridge = 'sBrg';
constexpr AudioObjectPropertySelector kPropHidden = 'sHid';

// 48 kHz mono float32, packed, native endian.
AudioStreamBasicDescription MonoFloat48() {
    AudioStreamBasicDescription f = {};
    f.mSampleRate = kSampleRate;
    f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian |
                     kAudioFormatFlagIsPacked;
    f.mBitsPerChannel = 32;
    f.mChannelsPerFrame = 1;
    f.mBytesPerFrame = 4;
    f.mFramesPerPacket = 1;
    f.mBytesPerPacket = 4;
    return f;
}

CFPropertyListRef MakeBool(bool v) {
    int n = v ? 1 : 0;
    return CFNumberCreate(nullptr, kCFNumberIntType, &n);
}

// Shared driver state. Task 8 fills these with real IO.
struct SottoState {
    std::atomic<bool> bridgeConnected{false};
    std::atomic<bool> micRunning{false};
    std::atomic<bool> micHidden{false};
};

std::shared_ptr<aspl::Driver> CreateSottoDriver() {
    auto context = std::make_shared<aspl::Context>();
    auto state = std::make_shared<SottoState>();

    // --- Sotto Microphone (visible input) ---
    aspl::DeviceParameters micParams;
    micParams.Name = "Sotto Microphone";
    micParams.DeviceUID = kMicUID;
    micParams.SampleRate = kSampleRate;
    micParams.ChannelCount = 1;
    micParams.CanBeDefault = true;
    micParams.CanBeDefaultForSystemSounds = false;
    micParams.Latency = 480; // one 10 ms frame of buffering, reported to the HAL
    auto micDevice = std::make_shared<aspl::Device>(context, micParams);
    {
        aspl::StreamParameters sp;
        sp.Direction = aspl::Direction::Input;
        sp.Format = MonoFloat48();
        micDevice->AddStreamWithControlsAsync(sp);
    }
    micDevice->RegisterCustomProperty(
        kPropRunning,
        [state]() -> CFPropertyListRef { return MakeBool(state->micRunning.load()); });
    micDevice->RegisterCustomProperty(
        kPropHidden,
        [state]() -> CFPropertyListRef { return MakeBool(state->micHidden.load()); },
        [state, micDevice](CFPropertyListRef value) {
            int n = 0;
            if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
                CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &n);
            }
            state->micHidden.store(n != 0);
            micDevice->SetIsHidden(n != 0);
        });

    // --- Sotto Bridge (hidden output, app-only) ---
    aspl::DeviceParameters bridgeParams;
    bridgeParams.Name = "Sotto Bridge";
    bridgeParams.DeviceUID = kBridgeUID;
    bridgeParams.SampleRate = kSampleRate;
    bridgeParams.ChannelCount = 1;
    bridgeParams.CanBeDefault = false;
    bridgeParams.CanBeDefaultForSystemSounds = false;
    auto bridgeDevice = std::make_shared<aspl::Device>(context, bridgeParams);
    bridgeDevice->SetIsHidden(true);
    {
        aspl::StreamParameters sp;
        sp.Direction = aspl::Direction::Output;
        sp.Format = MonoFloat48();
        bridgeDevice->AddStreamAsync(sp);
    }
    bridgeDevice->RegisterCustomProperty(
        kPropBridge,
        [state]() -> CFPropertyListRef { return MakeBool(state->bridgeConnected.load()); });

    auto plugin = std::make_shared<aspl::Plugin>(context);
    plugin->AddDevice(micDevice);
    plugin->AddDevice(bridgeDevice);

    return std::make_shared<aspl::Driver>(context, plugin);
}

} // namespace

extern "C" void* SottoEntryPoint(CFAllocatorRef /*allocator*/, CFUUIDRef typeUUID) {
    if (!CFEqual(typeUUID, kAudioServerPlugInTypeUUID)) {
        return nullptr;
    }
    static std::shared_ptr<aspl::Driver> driver = CreateSottoDriver();
    return driver->GetReference();
}
