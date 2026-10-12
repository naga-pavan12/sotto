# Krisp for macOS: architecture findings

Clean-room research notes for an independent, open-source noise-cancelling virtual microphone.

- **Target:** Krisp 3.17.9 (Electron) with KrispAudio.driver 2.1.8, Apple Silicon, analysed 2026-10-11/12.
- **Methods:**
  - file and symbol inventory (`otool`, `nm`, `strings`)
  - REA JavaScript application analysis
  - REA + Ghidra 12.1.4 decompilation of the native modules
  - Krisp's own plain-text runtime logs
- **Rules this document follows:**
  - It describes *behaviour, parameters and design*. It contains no Krisp code.
  - Krisp's encrypted models (`.kef`) were not decrypted or inspected.
  - The obfuscated JavaScript was not de-obfuscated.
  - Our implementation must be written independently and use open models.

Confidence tags: **[O]** observed in binaries or logs · **[I]** inferred.

---

## 1. Platform overview

```
┌──────────────────────── krisp.app (Electron, obfuscated JS) ─────────────────────────┐
│ UI windows: main_window · widget · notification_indicator · notification_reminder ·  │
│             companion                                                                │
│ Services (from logs): AudioService · DeviceManager · ActiveDevice · CallService ·    │
│             ProcessorManager · AudioRecordingService · WebSocketModule               │
│                                                                                      │
│ Native add-ons (N-API):                                                              │
│   kr-audio-dm      device discovery, defaults, volume sync, call detection           │
│   kr-media-sp      audio graph + on-device AI (NC, BVC, AEC, accent, ASR, diar.)     │
│   kr-ext-hub       Accessibility-based meeting-app integration (Zoom/Teams/Meet)     │
│   kr-native-utils  permissions (TCC), Keychain, process monitor, system info         │
│   kr-node-logger   logging                                                           │
└──────────────────────────────────────────────────────────────────────────────────────┘
          │ Core Audio (the app is an ordinary audio client)
┌─────────▼──────────── KrispAudio.driver (HAL AudioServerPlugIn) ─────────────────────┐
│  "krisp microphone"  (visible)   "krisp speaker" (visible)   "krisp app io" (hidden) │
└──────────────────────────────────────────────────────────────────────────────────────┘
Cloud: api.krisp.ai · cdn.krisp.ai (model downloads) · analytics.krisp.ai · Sentry
       socket.io sync events: sync_bvc_team_lists, sync_profile, sync_fraud_config,
       sync_calendar(_event), sync_activity_counter, sync_custom_vocabulary,
       meeting_ready, push_notification   [O]
```

- **Launch:** a per-user LaunchAgent runs `krisp --hidden` at login [O].
- **Privileged helper:** a gRPC `Krisp.AppService` provides `InstallService/Execute` and `HealthService/Check` [O]. [I] It probably installs the driver.
- **Driver process:** macOS loads the driver in its own process, "Core Audio Driver (KrispAudio.driver)" [O].
- **"Driverless mode":** the app logs mention it [O]. [I] It is probably a path that uses macOS process taps instead of the driver; the device manager cleans up leftover "Krisp tap" aggregate devices.

---

## 2. Virtual audio driver

**Origin:**
- The driver reports its manufacturer as **"Background Music contributors"** [O].
- It is derived from the open-source **Background Music** project (GPLv2).
- It uses Apple's public Core Audio sample classes: `CARingBuffer`, `CAVolumeCurve`, `CAMutex`, `CADispatchQueue`, `CAHostTimeBase`.
- **Implication for us:** we can build on Background Music (GPLv2) or BlackHole (MIT).

### 2.1 Objects [O]
| ID | Object | Notes |
|---|---|---|
| 1 | Plug-in | Devices 2, 12, 22 |
| 2 | **krisp microphone** (UID `KrispAudioDeviceMic`) | 1-ch input stream, volume and mute controls |
| 12 | **krisp speaker** (UID `KrispAudioDeviceSpeaker`) | 2-ch output stream, volume and mute controls |
| 22 | **krisp app io** (UID `KrispAppIODevice`) | Hidden. 2-ch input "to krisp" and 1-ch output "from krisp" |

- **Format:** every stream is 48 kHz float32, interleaved; 48 kHz is the only rate. The rate setter is ignored.
- **Device type:** transport 'virt'; latency and safety offset are 0.

### 2.2 Custom properties (CFPropertyList) [O]
| Selector | Meaning | Access |
|---|---|---|
| `krhs` | Hidden state: the app shows or hides the mic and speaker | Settable |
| `krvc` | Volume-control enable: the driver applies gain only when this is 1 | Settable |
| `krss` | Running state: whether any client is doing IO | Read-only, notifies |
| `krac` | Active clients: an array of {PID, bundle ID} currently doing IO | Read-only, notifies |

### 2.3 Audio path [O]
- **App identification:** only Krisp's own app (bundle-ID **prefix** `ai.krisp.krispMac`) may do IO on the hidden device. Other clients get no IO or silence.
- **Mic path:**
  - The app captures the real mic itself and processes it.
  - It **writes** the processed audio into the hidden device.
  - The driver stores it in a mic ring buffer.
  - Zoom and other apps reading "krisp microphone" fetch from that ring, with mute and gain applied.
- **Speaker path:**
  - Apps play to "krisp speaker".
  - The driver stores that audio in a speaker ring buffer.
  - The app **reads** it from the hidden device, cleans it, and plays it on the real speaker.
- **No passthrough:** without the app, the mic outputs silence and speaker audio is dropped.

### 2.4 Timing [O]
- **Clock:** each device anchors to the host clock at its first StartIO and ticks at exactly 48 kHz.
  - Zero-timestamp period: mic and app io 1,280 frames; speaker 2,560 frames.
  - The devices do not drift, but they are not phase-aligned.
- **Ring buffers:** mic 4,096 frames (mono); speaker 8,192 frames (stereo). Both are indexed by sample time.
- **Phase offset handling:**
  - On the first store after a fetch, the driver learns the offset between the two timelines.
  - On an underrun or overrun it outputs silence and moves the offset by **±64 frames**.

### 2.5 Liveness and client tracking [O]
- **App watcher:**
  - A 1 s timer plus a `sysctl` PID check.
  - When the app's process is gone, the mic and speaker are hidden.
  - The first read of 'hidden' after a fresh start hides the devices until the app shows them.
- **Client tracker** (per device):
  - It records the last IO time of each client.
  - A **220 ms** poller marks a client stopped after **200 ms** without IO.
  - Every change is published through `krac`.

### 2.6 Weaknesses to improve [O]
- A mutex on the real-time path, plus syslog and printf on the IO thread.
- An unlocked client list read on the IO thread (a data race).
- Gain applied as if stereo on the mono mic buffer (a buffer overrun).
- Spoofable app identification (bundle-ID prefix only).
- 1 s polling to detect app death.
- Fixed 48 kHz.

---

## 3. Device manager (kr-audio-dm)

| Function | Behaviour |
|---|---|
| **Device lifecycle** | The virtual devices always exist in the driver. They are shown or hidden by writing `krhs`, never created or destroyed. Setup shows the device, verifies it, and retries once. A "should be loaded" flag plus a **1 s recovery timer** heals the device if it disappears. [O] |
| **coreaudiod restarts** | It listens for the ServiceRestarted notification ('srst') and clears its cache. It never restarts coreaudiod itself. [O] |
| **Device-list changes** | Listeners on the device list and the default input/output. Events are diffed and debounced ("Event stabilized"). Its own devices, aggregates and Bluetooth hands-free devices are filtered out. [O] |
| **Bluetooth** | New Bluetooth devices wait **1,000 ms** before use, to ride out AirPods profile switching. Bluetooth mute is polled every 1 s, as a workaround for unreliable listeners on Monterey. [O] |
| **Default devices** | Sets the krisp mic as the default input and the krisp speaker as both the default and system output. JavaScript restores the user's previous device on quit. The Windows-style "communication" role is unsupported on macOS. [O] |
| **Call detection** | Uses macOS **audio process objects** (PID, responsible PID, bundle ID, IsRunningInput/Output, device list). The driver's `krac` list is the alternative backend. Debounce by PID: **250 ms** before a start and **1,200 ms** before an end; a start/stop flip-flop within the window is discarded. System Settings is excluded. [O] |
| **Volume mapping** | Copies the scalar volume both ways between the real device and the Krisp device. Rounded to 3 decimals with a 0.005 deadband. The mic has a 0.1 floor. Includes loop suppression. [O] |
| **Threading** | Serial GCD queues (`ai.krisp.queue`, `hal-tracker`, `audio-tracker`). Events go to JavaScript through N-API thread-safe functions: stream clients, device list and errors. [O] |

App layer (logs) [O]:
- A priority list of real devices, with "Selected same as system" honoured.
- Clipping detection: 2 clips within 5 intervals of 500 ms.
- An all-zeros mic check every 5 s.
- A stream-availability check every 3 s.

---

## 4. Audio engine (kr-media-sp)

### 4.1 Building blocks [O]
- **Processing graph:** `GraphManager`, `Graph`, `FrameProcessingChain`, `Capturer` (capture), `Renderer` (playback), `Resampler`, `ProcessorFactory`.
- **Processors, each with a type:** NC (noise cancellation), AEC_PROC (echo cancellation through `libaec-sdk`), AR (accent conversion), VOL, ASR and RTC_ASR (transcription), DIAR (diarization), STREAM_REC and FILE_REC (recording), FILE_PLAY.
- **In-house inference stack:** `KRISP::INFER`, `nn` and `BLAS`, plus ONNX for some models; VAD v3 and v4.
- **On-device transcription:** sentencepiece, KenLM and OpenFST, with a 588 MB English model that is forced to run on the CPU.
- **Cloud and real-time:**
  - WebSocket media gateway and real-time speech-to-text channels.
  - The Daily.co SDK (`libdaily-core-sdk`).
  - socket.io.
- **Other:**
  - ScreenCaptureKit and process audio capture for recording the far side of calls.
  - MP3 recording with audio redaction.

### 4.2 Pipeline parameters (from runtime logs) [O]
- **Mic chain, in order:**
  1. echo cancellation
  2. noise cancellation
  3. accent conversion (suspended unless enabled)
  4. volume
  5. recorders, transcription and diarization (suspended unless enabled)
- **Frames:** 10 ms each. Capture cache 10 frames, render cache 20 frames.
- **Suppression level:** 100 by default.
- **Process-delay tracking:** soft alert at 3,750 and hard alert at 7,500, with a 3 s processing-delay window. Units are not confirmed.
- **Ringtone detection:** threshold 0.96.
- **Processing runs only during calls:** the graph starts when the first client stream appears and stops when the last one ends.

### 4.3 Models [O]
| Logical name | Purpose | Internal rate | File (encrypted .kef) |
|---|---|---|---|
| `nc-outbound-mfb` | Mic noise cancellation | **32 kHz** | `c8.f.m…kef` (21 MB). A small variant `c8.f.s` is 6 MB. |
| `nc-inbound-mwb` | Incoming-audio noise cancellation | **16 kHz** | `c8.w.m…kef` (13 MB) |
| `hvc-outbound-lfb` | Background-voice cancellation | **32 kHz** | `hs.c6.f.m…berlin.kef` (14 MB); a small variant "bucharest" is 7 MB |
| `ar-outbound/inbound-wb-c` | Accent conversion | wideband (16 kHz) [I] | downloaded, 61–70 MB |
| `asr_eng_6.3.0` | English transcription | — | downloaded, 588 MB |
| `diar_2.0.0` | Diarization | — | 31 MB |

- **Model selection:** depends on the device sample rate, a "BestQuality" mode, a performance score (50 or 75) and an optional "optimized" flag.
- **Background-voice cancellation needs an approved headset:**
  - The allow-list (152 entries) and block-list (701 entries) are synced from the server.
  - Built-in laptop mics and smart speakers are blocked.

### 4.4 Orchestration: how the pipeline actually runs [O unless marked]

**Graphs**
- One graph per direction.
  - **Mic:** the physical mic is the source; the hidden `KrispAppIODevice` is the sink.
  - **Speaker:** the hidden device is the source; the physical speakers are the sink.
- The JavaScript layer starts a graph when a call stream appears on a Krisp device, and stops it when the last one ends.

**Device I/O**
- Raw HAL IOProcs (`AudioDeviceCreateIOProcID`), not AudioUnits.
- The device buffer is set to one 10 ms frame (480 samples at 48 kHz).

**Threads**
- The IOProc thread only converts audio (mono, format, resampling) and pushes frames into the capture cache.
- A **separate high-priority real-time thread per graph** runs every processor in sequence:
  - It uses the time-constraint thread policy and joins an **audio os_workgroup**.
  - It waits on a condition variable for a full frame.
- The caches use a **mutex and condition variable**. They are not lock-free.

**Caches**
- Capture cache: 10 frames, overwriting the oldest when full.
- Render cache: 20 frames, zero-filled with "Not enough data" on underrun.
- There is no clock-drift correction between devices.

**Resampling**
- Uses **libsamplerate** (SINC_FASTEST) or libresample, with miniaudio for format and channel conversion. Apple's AudioConverter is not used.
- It happens at three points: device → graph, graph → model rate (48→32 kHz for mic NC, 48→16 kHz for speaker NC) and back, and graph → device.

**Processor semantics**
- Processors run in spec order.
- On error a processor **fails open**: the input passes through and a failure counter increments.
- A suspended processor passes audio through.
- Setting changes are applied on the processing thread at the next frame boundary.
- The suppression level (0–100) is passed to the NC library on every frame.

**Echo cancellation**
- One shared AEC instance ("krips_aec3"). The speaker graph feeds it the far-end signal and the mic graph cancels against it.
- Alignment between the two graphs is left to the AEC's own delay estimation.
- [I] There is a 3 s warm-up passthrough at the start.

**Overload monitoring (PDTracker)**
- It measures per-frame processing time in µs and smooths it with moving average and median filters.
- **Soft alert at 3,750 µs** (37.5% of a 10 ms frame); **hard alert at 7,500 µs** (75%).
- On alert it only *reports* to JavaScript. The engine itself never downgrades or bypasses.

**Health checks**
- No frames within 3 s raises an error.
- All-zero audio for 5 s raises an error.
- Clipping detection.
- A has-energy status at frame 20.

**Device switching**
- The graph has no listeners of its own. The JavaScript layer stops and deletes the graph and builds a new one, with freshly selected models.

**Estimated mic-path latency**
- About 30–50 ms plus the model's lookahead [I].

---

## 5. Meeting integration (kr-ext-hub)

This is how Krisp reads meeting apps without a bot joining the call. Everything goes through **macOS Accessibility**. There is no screen capture, no browser extension and no audio analysis. [O]

| Aspect | Behaviour |
|---|---|
| **API to JavaScript** | `initialize`, `executeAction`, `cancelAction`, `startObservation` and `stopObservation`, with protobuf messages. A bundled JSON resource (14 KB) holds UI labels for each app, version and language. [O] |
| **Actions** | Get meeting metadata from Zoom (two versions, selected by app-version range) and Meet; send a chat message in Zoom, Teams and Meet. [O] |
| **Observers** | **Zoom only:** meeting activity (participants and speaking) and your own mute state. [O] |
| **Finding the app** | Matches window-owner names (`zoom.us`, `microsoft teams`, `google chrome`) to get a PID, then opens that app's accessibility tree. [O] |
| **Google Meet** | Reads Chrome's **Tab menu** and matches the meeting code with a regex. Prefers windows titled "…microphone recording", which Chrome adds to tabs using the mic. [O] |
| **Who's speaking (Zoom)** | Polls Zoom's accessibility descriptions of participant tiles about every **300 ms**. Each description holds the name, role tags (me, host, co-host, guest, interpreter) and the audio state ("unmuted … active"). It builds a speech timeline for each participant. [O/I] |
| **Mute state (Zoom)** | Subscribes to accessibility structure changes. Reads your own tile and falls back to the Zoom menu ("Mute audio"/"Unmute audio"). High-frequency changes are filtered out. [O] |
| **Metadata (Zoom)** | Clicks the meeting-info button, reads title, ID, host and invite link from the popover, then closes it. This visibly flashes the UI. [O] |
| **Sending chat** | **Zoom:** sets the chat box text through Accessibility, then presses Send. **Teams and Meet:** brings the window to the front, puts the message on the **clipboard**, sends Cmd+V and then Cmd+Enter as synthetic keystrokes, and restores the clipboard afterwards. [O] |
| **Localization** | Zoom in 17 languages, Teams and Meet in English only. The language is detected from menu-bar item names. [O] |
| **Permissions** | Accessibility only; no Screen Recording. [O] |
| **Privacy** | Participant names, titles and the local user's name are logged at info level. It enumerates every Chrome tab title. [O] |

What we'd do differently:
- Use accessibility notifications instead of 300 ms polling.
- Make everything opt-in for each app, never log names, and avoid taking over the clipboard and stealing focus.
- Write our own label tables.

---

## 6. What this means for our open-source build

### 6.1 Feature map: Krisp → ours
| Krisp component | Our equivalent | Notes |
|---|---|---|
| HAL driver (derived from Background Music) with 3 devices | **Our driver**, based on BlackHole (MIT) or Background Music (GPLv2) | Keep the "hidden app-facing device + visible mic/speaker" design |
| Custom properties `krhs`/`krvc`/`krss`/`krac` | Our own property set (hidden, volume-enable, running, active-clients) | Our own selectors and names |
| Bundle-ID prefix app check | **Code-signature / team-ID** check | Krisp's check is spoofable |
| 1 s sysctl app watcher | **PROC_EXIT dispatch source** (instant) | |
| 220/200 ms client poller | Atomic per-client timestamps; poll off the real-time thread | |
| Mutex-guarded CARingBuffer, ±64-frame offset correction | **Lock-free SPSC ring**, explicit target latency, reported via the latency properties | |
| Silence when the app isn't running | **Optional raw passthrough** | Better failure mode |
| 48 kHz only | 44.1 and 48 kHz | |
| Device manager: hide/show, 1 s recovery, 'srst' listener, Bluetooth 1 s grace, default switching | Same behaviours, **plus saving the previous default to disk** so it can be restored after a crash | |
| Call detection with 250/1,200 ms debounce | Same thresholds, using process objects (macOS 14.4+) | Exclude System Settings |
| Two-way volume mapping (0.005 deadband, 0.1 mic floor) | Same | |
| HAL IOProc → mutex cache → real-time thread → render cache | IOProc → **lock-free ring** → real-time thread in an os_workgroup → lock-free ring with **drift correction** | |
| Encrypted NC models at 32 kHz (mic) and 16 kHz (speaker) | **DeepFilterNet3**: open, runs at 48 kHz natively, 10 ms hop, **no model resampling** | Must be benchmarked |
| libsamplerate SINC_FASTEST | Only when the device isn't 48 kHz (libsamplerate or soxr) | |
| Fail-open processors, suspend = passthrough, settings applied at frame boundaries | Same | Good design worth keeping |
| PDTracker (37.5% / 75% of the frame), reports only | Same thresholds, **plus automatic action**: lighter model, then bypass with a crossfade | |
| Health checks (no frames 3 s, all zeros 5 s, clipping) | Same | |
| Background-voice cancellation on approved headsets only | Later version. Needs an open voice-isolation model and our own device heuristics | |
| AEC ("krips_aec3") | Later version: WebRTC AEC3 (BSD), which the name suggests Krisp also builds on [I] | |
| Accent conversion, on-device transcription, diarization, cloud sync, meeting integration | **Out of scope for v1.** Meeting integration and transcription are already covered by open-source tools (Meetily and others) | |

### 6.2 Scope for v1 (as agreed)
- **macOS, mic only:**
  - driver with a visible mic and a hidden app device
  - menu-bar app: capture → DeepFilterNet3 → hidden device
  - call-gated processing
  - device and default management
  - overload fallback
  - health checks

### 6.3 Open questions to settle by measurement
- DeepFilterNet3's real-time CPU cost on Apple Silicon, and its lookahead latency at our settings.
- End-to-end latency target: we propose 60 ms or less; Krisp's is estimated at 30–50 ms plus its model.
- How background-voice handling on built-in laptop mics compares with Krisp's.
