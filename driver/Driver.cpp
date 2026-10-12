// Sotto HAL audio-server plug-in.
//
// Presents two devices:
//   "Sotto Microphone" — visible input; call apps read cleaned audio here.
//   "Sotto Bridge"     — hidden output; only the authorized Sotto app writes
//                        cleaned audio here, which the driver loops to the mic.
//
// The app writes processed audio to the bridge; the driver stores it in a
// sample-time-indexed ring and serves it to any app reading the mic, delayed by
// one 10 ms frame. Both devices advance on the host clock at 48 kHz.

#include <aspl/Driver.hpp>

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>

#include <atomic>
#include <memory>

#include "auth.hpp"
#include "bridge_ring.hpp"

#include <mach/mach_time.h>
#include <cmath>

namespace {

// A single clock anchor shared by both devices so their sample-time timelines are
// phase-locked: for the same host time, both return the same sample time. This is
// what lets the bridge (writer) and mic (reader) use one shared, time-indexed ring.
struct SharedClock {
    uint64_t anchorHost;
    double ticksPerFrame;
    SharedClock() {
        mach_timebase_info_data_t tb;
        mach_timebase_info(&tb);
        double ticksPerSec = 1.0e9 * (double)tb.denom / (double)tb.numer;
        ticksPerFrame = ticksPerSec / 48000.0;
        anchorHost = mach_absolute_time();
    }
};

} // namespace

namespace {

constexpr UInt32 kSampleRate = 48000;
constexpr Float64 kFrameDelay = 480.0; // one 10 ms frame of bridge->mic latency
constexpr char kMicUID[] = "SottoMicrophone";
constexpr char kBridgeUID[] = "SottoBridge";

constexpr AudioObjectPropertySelector kPropRunning = 'sRun';
constexpr AudioObjectPropertySelector kPropBridge = 'sBrg';
constexpr AudioObjectPropertySelector kPropHidden = 'sHid';

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

// Shared across both devices' handlers.
struct SottoState {
    BridgeRing ring{8192};
    std::atomic<pid_t> authorizedPid{0};  // the Sotto app's pid, once it connects
    std::atomic<bool> bridgeConnected{false};
    std::atomic<int> micClients{0};       // non-Sotto apps reading the mic
    std::atomic<bool> micHidden{false};
};

// Bridge: receives the app's cleaned audio and stores it in the ring.
class BridgeHandler : public aspl::ControlRequestHandler, public aspl::IORequestHandler {
public:
    explicit BridgeHandler(std::shared_ptr<SottoState> s) : state_(std::move(s)) {}

    std::shared_ptr<aspl::Client> OnAddClient(const aspl::ClientInfo& info) override {
        if (sotto::is_authorized_client(info.ProcessID, info.BundleID)) {
            state_->authorizedPid.store(info.ProcessID, std::memory_order_release);
            state_->bridgeConnected.store(true, std::memory_order_release);
        }
        return nullptr; // let libASPL create the default Client
    }

    void OnRemoveClient(std::shared_ptr<aspl::Client> client) override {
        if (client && client->GetProcessID() == state_->authorizedPid.load()) {
            state_->bridgeConnected.store(false, std::memory_order_release);
            state_->authorizedPid.store(0, std::memory_order_release);
        }
    }

    void OnWriteClientOutput(const std::shared_ptr<aspl::Client>& client,
                             const std::shared_ptr<aspl::Stream>&,
                             Float64 /*zeroTs*/, Float64 timestamp,
                             const Float32* frames, UInt32 frameCount,
                             UInt32 /*channelCount*/) override {
        if (client && client->GetProcessID() == state_->authorizedPid.load(std::memory_order_acquire)) {
            state_->ring.store((int64_t)timestamp, frames, frameCount);
        }
    }

private:
    std::shared_ptr<SottoState> state_;
};

// Mic: serves the ring (delayed by one frame) to any reading app.
class MicHandler : public aspl::ControlRequestHandler, public aspl::IORequestHandler {
public:
    explicit MicHandler(std::shared_ptr<SottoState> s) : state_(std::move(s)) {}

    std::shared_ptr<aspl::Client> OnAddClient(const aspl::ClientInfo& info) override {
        if (info.ProcessID != state_->authorizedPid.load(std::memory_order_acquire)) {
            state_->micClients.fetch_add(1, std::memory_order_acq_rel);
        }
        return nullptr;
    }

    void OnRemoveClient(std::shared_ptr<aspl::Client> client) override {
        if (client && client->GetProcessID() != state_->authorizedPid.load(std::memory_order_acquire)) {
            if (state_->micClients.load() > 0) {
                state_->micClients.fetch_sub(1, std::memory_order_acq_rel);
            }
        }
    }

    void OnReadClientInput(const std::shared_ptr<aspl::Client>&,
                           const std::shared_ptr<aspl::Stream>&,
                           Float64 /*zeroTs*/, Float64 timestamp,
                           void* bytes, UInt32 bytesCount) override {
        UInt32 frames = bytesCount / sizeof(Float32);
        state_->ring.fetch((int64_t)(timestamp - kFrameDelay),
                           static_cast<Float32*>(bytes), frames);
    }

private:
    std::shared_ptr<SottoState> state_;
};

// Device variant that derives its zero timestamp from a shared clock anchor.
class SottoDevice : public aspl::Device {
public:
    SottoDevice(std::shared_ptr<aspl::Context> ctx,
                const aspl::DeviceParameters& params,
                std::shared_ptr<SharedClock> clock)
        : aspl::Device(std::move(ctx), params), clock_(std::move(clock)) {}

protected:
    OSStatus GetZeroTimeStampImpl(UInt32 /*clientID*/, Float64* outSampleTime,
                                  UInt64* outHostTime, UInt64* outSeed) override {
        const double period = 480.0;
        uint64_t now = mach_absolute_time();
        double elapsed = (double)(now - clock_->anchorHost);
        double framesPerPeriod = period * clock_->ticksPerFrame;
        double n = std::floor(elapsed / framesPerPeriod);
        *outSampleTime = n * period;
        *outHostTime = clock_->anchorHost + (uint64_t)llround(n * framesPerPeriod);
        *outSeed = 1;
        return kAudioHardwareNoError;
    }

private:
    std::shared_ptr<SharedClock> clock_;
};

std::shared_ptr<aspl::Driver> CreateSottoDriver() {
    auto context = std::make_shared<aspl::Context>();
    auto state = std::make_shared<SottoState>();
    auto clock = std::make_shared<SharedClock>();

    // --- Sotto Microphone (visible input) ---
    aspl::DeviceParameters micParams;
    micParams.Name = "Sotto Microphone";
    micParams.DeviceUID = kMicUID;
    micParams.SampleRate = kSampleRate;
    micParams.ChannelCount = 1;
    micParams.CanBeDefault = true;
    micParams.CanBeDefaultForSystemSounds = false;
    micParams.Latency = 480;
    micParams.ZeroTimeStampPeriod = 480; // shared period keeps the two clocks aligned
    auto micDevice = std::make_shared<SottoDevice>(context, micParams, clock);
    {
        aspl::StreamParameters sp;
        sp.Direction = aspl::Direction::Input;
        sp.Format = MonoFloat48();
        micDevice->AddStreamWithControlsAsync(sp);
    }
    auto micHandler = std::make_shared<MicHandler>(state);
    micDevice->SetControlHandler(micHandler);
    micDevice->SetIOHandler(micHandler);
    micDevice->RegisterCustomProperty(
        kPropRunning,
        [state]() -> CFPropertyListRef { return MakeBool(state->micClients.load() > 0); });
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
    bridgeParams.ZeroTimeStampPeriod = 480;
    auto bridgeDevice = std::make_shared<SottoDevice>(context, bridgeParams, clock);
    bridgeDevice->SetIsHidden(true);
    {
        aspl::StreamParameters sp;
        sp.Direction = aspl::Direction::Output;
        sp.Format = MonoFloat48();
        bridgeDevice->AddStreamAsync(sp);
    }
    auto bridgeHandler = std::make_shared<BridgeHandler>(state);
    bridgeDevice->SetControlHandler(bridgeHandler);
    bridgeDevice->SetIOHandler(bridgeHandler);
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
