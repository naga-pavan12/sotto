# Noise-suppression benchmark

This benchmark compares DeepFilterNet3, a classical spectral-gating baseline, unprocessed audio, and Krisp's live noise cancellation, all on the same synthetic noisy-speech set.

> **Internal use only.** Check Krisp's terms of service before publishing any Krisp numbers.

## Test set (`gen_dataset.py`)
- **Speech:** 8 clean sentences spoken by macOS voices (Aman, Rishi, Daniel and Samantha), at 48 kHz mono.
- **Noise:** 6 synthesized types: fan, keyboard, traffic (rumble plus horns), babble (4 other voices), music and white noise.
- **Levels:** each noise is mixed in at SNR 0, 5, 10 and 20 dB, giving **192 clips (about 20 minutes)**.
- **Excluded voice:** we dropped the robotic "Albert" voice because DeepFilterNet treats it as noise.

## Systems
| System | How it was run |
|---|---|
| `dfn3` | `tools/deep-filter -D` (DeepFilterNet3 v0.5.6, Rust/tract, CPU), offline, with model delay compensated |
| `spectral_gate` | `noisereduce`, non-stationary, prop_decrease 0.9 |
| `krisp` | Krisp 3.17.9 live: clips are played into BlackHole 2ch (set as Krisp's mic) and recorded from "krisp microphone" (`capture_krisp.py`). Settings: noise removal Auto, voice isolation unavailable for this device |
| `noisy` | Unprocessed input |

## Results (`evaluate.py`, 2026-10-12)
| | PESQ-WB | STOI | SI-SDR (dB) | DNSMOS SIG | DNSMOS BAK | DNSMOS OVRL |
|---|---|---|---|---|---|---|
| noisy | 1.61 | 0.916 | 8.0 | 3.29 | 2.67 | 2.44 |
| spectral_gate | 1.58 | 0.885 | 3.4 | 3.22 | 3.33 | 2.64 |
| **dfn3** | 2.79 | 0.963 | 16.2 | **3.43** | 3.93 | **3.09** |
| **krisp** | **2.88** | **0.965** | **17.8** | 3.35 | **4.01** | 3.07 |

Head to head on each clip, DeepFilterNet3 beats Krisp on:
- DNSMOS OVRL: 114/192 clips
- PESQ: 103/192
- STOI: 88/192
- SI-SDR: 73/192

### By noise type (DNSMOS OVRL / SI-SDR)
| Noise | dfn3 | krisp |
|---|---|---|
| babble | 2.69 / 9.3 | 2.68 / 11.3 |
| fan | **3.23** / 16.5 | 3.13 / 16.1 |
| keyboard | 2.97 / 21.6 | **3.17 / 24.2** |
| music | **3.22** / 13.3 | 3.09 / 14.6 |
| traffic | 3.25 / 17.2 | 3.27 / 21.9 |
| white | **3.17** / 18.9 | 3.10 / 18.8 |

### Compute
DeepFilterNet3 used a real-time factor of 0.043 on one core of an M-series MacBook Air, which is about 4% of a core, with 64 MB RSS.

## Caveats
- **Synthetic data.** Real recordings would add room reverb, mic coloration and real-world noise.
- **Different conditions.** Krisp ran live (driver hop, resampling, real-time scheduling) while DeepFilterNet3 ran offline. That slightly favours DeepFilterNet3.
- **Latency is not comparable yet.**
  - Krisp's 135 ms (median) includes this harness's playback and record buffering.
  - `calibrate_latency.py` uses a different stream path (256 ms), so it can't be subtracted.
  - Measure latency properly once our own live prototype exists, using the same harness for both.
- **Krisp has more models than were tested.** Its background-voice (BVC) model only switches on for allow-listed headsets, so it wasn't tested here.

## Re-run
```bash
uv run python gen_dataset.py
tools/deep-filter -D -o out/dfn3 data/noisy/*.wav
uv run python run_baselines.py
uv run python capture_krisp.py        # needs BlackHole + Krisp mic set to BlackHole 2ch
uv run python evaluate.py
```

## Sotto live measurement (Task 15)

`measure_sotto.py` runs the full shipped pipeline: it plays each noisy clip into
BlackHole 2ch, the running `Sotto.app`/`SottoCLI` engine captures BlackHole →
DeepFilterNet3 → Sotto Bridge → **Sotto Microphone**, and the script records
Sotto Microphone and scores it.

**Live result (24-clip sample, one speaker across all 6 noise types × 4 SNRs, 2026-10-13):**

| | PESQ | STOI | SI-SDR | DNSMOS SIG | DNSMOS BAK | DNSMOS OVRL |
|---|---|---|---|---|---|---|
| Sotto (live) | 2.12 | 0.86 | 6.2 | 3.16 | 3.58 | 2.71 |
| DeepFilterNet3 (offline ceiling) | 2.79 | 0.96 | 16.2 | 3.43 | 3.93 | 3.09 |
| Krisp (standard NC) | 2.88 | 0.97 | 17.8 | 3.35 | 4.01 | 3.07 |

Sotto removes noise well (BAK 3.58) and works end-to-end, but the live path sits
~0.4 DNSMOS below the model's offline ceiling. The gap is real-time path overhead:
the capture ↔ bridge ↔ mic hops run on independent device clocks, and the test
feeds audio through a BlackHole loopback, adding resampling/buffer jitter. Closing
it (tighter clock sync, drift-corrected buffering) is the main v0.1→v0.2 quality item.

```bash
make driver && make install && make app
open app/build/Sotto.app        # or run SottoCLI directly for headless tests
cd bench && uv run python measure_sotto.py 24 && uv run python evaluate.py sotto
```
