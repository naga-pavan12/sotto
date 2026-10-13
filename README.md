# Sotto

**Local-only, open-source noise-cancelling virtual microphone for macOS.**

Sotto adds a "Sotto Microphone" to your Mac that any call app (Zoom, Google Meet,
Teams) can select. It captures your real mic, removes background noise with
[DeepFilterNet3](https://github.com/Rikorose/DeepFilterNet), and presents the clean
result — all on your machine. No account, no cloud, no telemetry.

> Status: v0.1 — working end-to-end. Captures your mic, removes background noise
> with DeepFilterNet3, and presents a "Sotto Microphone" any call app can select.
> Live quality: DNSMOS 2.7 (noise-removal BAK 3.6); see [bench/README.md](bench/README.md).
> See the [roadmap](#roadmap) for what's next.

## Build from source

Prerequisites: macOS 14+ on Apple Silicon, Xcode 16+ (or Command Line Tools),
Rust (stable), CMake, and Python 3 with [uv](https://docs.astral.sh/uv/).

```bash
make            # build denoiser, driver, and app
make install    # install the audio driver (asks for your password; restarts coreaudiod)
make app        # build Sotto.app
```

Then open `Sotto.app`, and select **Sotto Microphone** in your call app.

## How it works

See [docs/superpowers/specs/2026-10-12-sotto-v0.1-design.md](docs/superpowers/specs/2026-10-12-sotto-v0.1-design.md)
for the architecture.

## Roadmap

**v0.2**
- **Driver watches app liveness** — reset the driver and hide the device if the
  app crashes or is force-killed, instead of relying on a clean-quit callback
  (today a hard kill leaves a stale "connected" flag). Mirrors how Krisp's
  app-watcher hides its devices when the app goes away.
- Process the mic **only during calls** (detect when an app is reading Sotto
  Microphone) instead of capturing continuously while enabled.
- Automatic default-device switching and per-app call detection.
- Bluetooth/AirPods handling (grace period on profile switch).
- Tighter clock sync + drift-corrected buffering to close the live-quality gap.

**Later:** incoming-audio (speaker) cleaning, background-voice isolation,
signed/notarized installer + Homebrew cask, Windows and Linux.

## License

MIT. Built on [libASPL](https://github.com/gavv/libASPL) (MIT) and
[DeepFilterNet](https://github.com/Rikorose/DeepFilterNet) (MIT/Apache-2.0).
Sotto is an independent project and is not affiliated with any commercial noise-cancellation vendor.

## Known limitations (v0.1)

- **Bridge authorization in unsigned builds is best-effort.** A signed release
  (built with `SOTTO_TEAM_ID`) verifies the connecting app's code-signing Team ID
  via the Security framework. An unsigned local/dev build has no signing identity
  to check, so it falls back to a bundle-ID match, which a process could spoof.
  The bridge is a hidden device (not listed in normal enumeration) as
  defense-in-depth, but treat unsigned dev builds as local-trust only. Ship signed.
- **Live latency/quality gap.** The real-time path sits ~0.4 DNSMOS below the
  model's offline ceiling; the capture↔bridge↔mic hops run on independent device
  clocks. Tighter clock sync and drift-corrected buffering are the main v0.2 items.
- **48 kHz only**; low-rate device support (e.g. 16 kHz Bluetooth) is untested.
- **No automatic default-device switching or per-app call detection** yet (v0.2).
