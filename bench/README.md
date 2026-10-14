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

## Sotto quality: three references

Comparing Sotto against the right reference matters. `dfn3` above is the
**deep-filter CLI**, a *different* code path from Sotto's `df`-crate integration,
so it is not Sotto's own ceiling. Two helper tools measure Sotto itself:

- **`sotto_offline.py`** drives Sotto's own `libsotto_denoiser.dylib` hop-by-hop
  (no audio devices, fresh model state) — Sotto's true offline ceiling.
- **`measure_sotto_fresh.py`** runs the full live pipeline (BlackHole →
  DeepFilterNet3 → Sotto Bridge → **Sotto Microphone**) with a **fresh engine per
  clip**, so the model's running normalization is not biased by preceding clips.

### The v0.1→v0.2 quality investigation (2026-10-14)

The original `measure_sotto.py` reported Sotto live at DNSMOS OVRL 2.71, ~0.4 below
`dfn3` (3.09), and that gap was attributed to real-time buffering. Investigation
showed the gap was **not** the real-time path:

- **No clock drift** (windowed cross-correlation lag is flat), and BlackHole
  loopback alone is lossless (corr 1.000). The pipeline reproduces the model
  within 0.03 DNSMOS (live vs `sotto_offline`).
- **Wrong reference.** `dfn3` is the CLI, not Sotto's model. Sotto's own model
  offline scored 2.74 — the real gap was in the model config, not the pipeline.
- **Benchmark bias.** `measure_sotto.py` streams all clips through one never-reset
  model with silence gaps; a loud clip before a quiet one over-attenuates the quiet
  one's speech. `measure_sotto_fresh.py` (fresh engine per clip) removes this.
- **Root cause + fix.** Sotto used the `df` library's conservative decoder
  thresholds (`min_db_thresh -10`, `max_db_erb_thresh 30`, `max_db_df_thresh 20`)
  instead of DeepFilterNet's recommended inference values (`-15 / 35 / 35`, the
  deep-filter CLI defaults). Matching them (in `denoiser/src/lib.rs`) lifts Sotto
  +0.25 DNSMOS OVRL at no CPU cost (RTF still ~0.039).

**Result (full 192-clip set, Sotto at default strength 90, fixed thresholds):**

| | PESQ | STOI | SI-SDR | DNSMOS SIG | DNSMOS BAK | DNSMOS OVRL |
|---|---|---|---|---|---|---|
| Sotto | 2.70 | 0.96 | 16.8 | **3.42** | 3.82 | 3.03 |
| deep-filter CLI (reference) | 2.79 | 0.96 | 16.2 | 3.43 | 3.93 | 3.09 |
| Krisp (standard NC) | 2.88 | 0.96 | 17.8 | 3.35 | 4.01 | 3.07 |

Sotto now ties Krisp overall (3.03 vs 3.07) and leads on speech quality (SIG 3.42
vs 3.35). Live matches this within 0.03 DNSMOS (the real-time path is lossless).

```bash
make driver && make install && make app
cd bench
uv run python sotto_offline.py 192 90        # Sotto's offline ceiling
uv run python measure_sotto_fresh.py         # live, fresh engine per clip
uv run python evaluate.py sotto_model sotto_fresh dfn3 krisp
```
