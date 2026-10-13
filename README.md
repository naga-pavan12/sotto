<div align="center">

<img src="art/icon_1024.png" alt="Sotto" width="120" />

# Sotto

**Free, on-device noise cancellation for your microphone on macOS.**

Sotto adds a virtual "Sotto Microphone" to your Mac. Pick it in any call app and
your background noise — keyboard, fan, traffic, chatter — is removed before anyone
hears it. Everything runs locally: no account, no cloud, no telemetry.

An open-source alternative to Krisp's core feature, built on
[DeepFilterNet3](https://github.com/Rikorose/DeepFilterNet).

[Quick start](#quick-start) · [How it works](#how-it-works) · [Benchmark](#benchmark) · [Roadmap](#roadmap)

![status: v0.1 developer preview](https://img.shields.io/badge/status-v0.1_preview-0FA98A)
![platform: macOS 14+ Apple Silicon](https://img.shields.io/badge/macOS-14%2B_Apple_Silicon-333)
![license: MIT](https://img.shields.io/badge/license-MIT-0FA98A)

<!-- Add a 15-second demo GIF here: hold-to-compare showing noisy → clean. -->
<!-- ![Sotto demo](docs/demo.gif) -->

</div>

---

## What it does

- **Removes background noise from your mic** in Zoom, Google Meet, Teams, Discord, OBS — anything that lets you choose a microphone.
- **Runs entirely on your Mac.** No sign-in, no servers, nothing uploaded.
- **Light on the CPU** — about 4% of one core.
- **Simple controls** — on/off, a strength slider, and hold-to-compare to hear the difference.

> **Status:** v0.1 developer preview. Mic noise removal works end-to-end. Today it's
> a source build (unsigned); a one-click signed installer is on the way. See
> [limitations](#limitations) and the [roadmap](#roadmap).

## Quick start

**Requirements:** macOS 14+ on Apple Silicon, plus [Xcode](https://developer.apple.com/xcode/)
or Command Line Tools, [Rust](https://rustup.rs), [CMake](https://cmake.org), and
[uv](https://docs.astral.sh/uv/) (only for the benchmark).

```bash
git clone https://github.com/sotto-audio/sotto.git
cd sotto
make            # build the denoiser, driver, and app
make install    # install the audio driver (asks for your password; restarts Core Audio)
make app        # build Sotto.app
open app/build/Sotto.app
```

Then in your call app, choose **“Sotto Microphone”** as the input. That's it.

To remove the driver later: `make uninstall`.

## Using it

1. Launch Sotto — it appears in the **Dock**, the **menu bar**, and opens a small control window.
2. Turn it **on**, pick your real **microphone**, and set the **strength** (default 80%).
   Hold **“Hear original”** to A/B compare.
3. Select **“Sotto Microphone”** in your call app.
4. **Quit** from the window's Quit button, `⌘Q`, or right-click the Dock icon — this
   releases your mic cleanly.

## How it works

```
Your mic ──► Sotto app ──► DeepFilterNet3 ──► Sotto Bridge ──► "Sotto Microphone" ──► your call app
            (captures)     (removes noise)    (hidden device)   (what apps select)
```

- A small **Core Audio driver** (built on [libASPL](https://github.com/gavv/libASPL))
  presents two devices: the visible "Sotto Microphone" and a hidden "Sotto Bridge".
- The **app** captures your real mic, cleans each 10 ms chunk with **DeepFilterNet3**
  on a real-time thread, and writes the result into the bridge; the driver serves it
  as "Sotto Microphone".
- Processing is **fail-open**: if anything hiccups, your original audio passes through
  rather than dropping to silence.

Architecture details: [docs/superpowers/specs/2026-10-12-sotto-v0.1-design.md](docs/superpowers/specs/2026-10-12-sotto-v0.1-design.md).

## Benchmark

Measured on a synthetic test set (6 noise types × 4 noise levels), scored with
PESQ, STOI, SI-SDR and Microsoft DNSMOS. Higher is better. Full method and
re-run instructions: [bench/README.md](bench/README.md).

| | Noise removal (DNSMOS BAK) | Overall (DNSMOS OVRL) | PESQ |
|---|---|---|---|
| Unprocessed | 2.67 | 2.44 | 1.61 |
| Classic spectral gating | 3.33 | 2.64 | 1.58 |
| **Sotto (live)** | **3.58** | **2.71** | **2.12** |
| DeepFilterNet3 (offline ceiling) | 3.93 | 3.09 | 2.79 |

Sotto removes noise well at ~4% of one CPU core. The live path currently sits a bit
below the model's offline ceiling; closing that gap is the main v0.2 item.

## Roadmap

**Toward a public release**
- Signed, notarized installer and a Homebrew cask (one-click install, no terminal).

**v0.2**
- Driver watches the app's liveness and resets cleanly if it crashes or is killed.
- Process **only during calls** instead of capturing whenever enabled.
- Automatic default-device switching and per-app call detection.
- Bluetooth / AirPods handling.
- Tighter clock sync and drift-corrected buffering to close the live-quality gap.

**Later**
- Clean *incoming* audio (the other side) too.
- Background-voice isolation (removing other people's voices, not just noise).
- Windows and Linux.

## Limitations

- **Developer preview:** source build, unsigned — on other Macs it needs manual
  approval until we ship a signed build.
- **48 kHz only** for now; low-rate Bluetooth mics are untested.
- **Live quality** trails the model's offline ceiling pending v0.2 buffering work.
- **Bridge authorization** is fully enforced only in signed builds (which verify the
  app's code-signing Team ID). Unsigned local builds fall back to a weaker check;
  the bridge is a hidden device as defense-in-depth. See the design doc.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Run `make test`
before a PR. **Clean-room rule:** Sotto is an independent implementation; do not add
code, model weights, or decompiled material from any proprietary product.

## Credits & license

Sotto is MIT-licensed. It builds on:
- [DeepFilterNet](https://github.com/Rikorose/DeepFilterNet) (MIT/Apache-2.0) — the noise-removal model
- [libASPL](https://github.com/gavv/libASPL) (MIT) — the Core Audio driver framework

Sotto is an independent project and is not affiliated with, or endorsed by, any
commercial noise-cancellation vendor.
