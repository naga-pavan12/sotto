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

v0.2: automatic default-device switching, per-app call detection, Bluetooth handling.
Later: incoming-audio cleaning, background-voice isolation, Windows and Linux.

## License

MIT. Built on [libASPL](https://github.com/gavv/libASPL) (MIT) and
[DeepFilterNet](https://github.com/Rikorose/DeepFilterNet) (MIT/Apache-2.0).
Sotto is an independent project and is not affiliated with any commercial noise-cancellation vendor.
