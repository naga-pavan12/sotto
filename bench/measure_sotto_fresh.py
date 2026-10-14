"""Measure Sotto live with FRESH model state per clip.

The original measure_sotto.py streams every clip through ONE never-reset engine
with silence gaps between clips, so the model's running normalization carries
bias from preceding clips into later ones (diagnosed: a loud clip before a quiet
one over-attenuates the quiet one's speech). That is an artifact of concatenating
unrelated test clips; it does not represent a single real conversation.

This harness launches a fresh SottoCLI engine per clip (fresh DeepFilterNet
state), warms the Core Audio devices with a short silence lead-in, then plays and
records just that clip. Each clip is therefore measured from clean model state,
the same condition as sotto_offline.py (Sotto's own model, offline).

Usage: uv run python measure_sotto_fresh.py [clip_glob]
  clip_glob: optional substring filter, e.g. "keyboard" or "20dB" (default: all 24
             for speaker aman_s0). Pass "ALL" for every clip.
"""

import subprocess
import sys
import threading
import time
from pathlib import Path

import numpy as np
import sounddevice as sd
import soundfile as sf

ROOT = Path(__file__).parent
NOISY = ROOT / "data" / "noisy"
OUT = ROOT / "out" / "sotto_fresh"
SR = 48_000
PLAY_DEVICE = "BlackHole 2ch"
REC_DEVICE = "Sotto Microphone"
CLI_APP = "/tmp/SottoCLI.app/Contents/MacOS/SottoCLI"
DEVICE_WARMUP_S = 1.5   # let the fresh engine's Core Audio IO procs settle
TAIL_S = 0.5            # record a little past the clip for model latency


def find_device(name: str, kind: str) -> int:
    for i, dev in enumerate(sd.query_devices()):
        if name.lower() in dev["name"].lower() and dev[f"max_{kind}_channels"] > 0:
            return i
    sys.exit(f"device '{name}' ({kind}) not found")


def measure_clip(path: Path, play_dev: int, rec_dev: int) -> np.ndarray:
    audio, sr = sf.read(path, dtype="float32")
    assert sr == SR, f"{path} is {sr} Hz"
    clip_s = len(audio) / SR
    run_s = DEVICE_WARMUP_S + clip_s + TAIL_S + 1.0
    engine = subprocess.Popen(
        [CLI_APP, "BlackHole2ch_UID", str(int(run_s) + 1)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(DEVICE_WARMUP_S)
        chunks: list[np.ndarray] = []
        lock = threading.Lock()

        def on_input(indata, frames, t, status):
            with lock:
                chunks.append(indata[:, 0].copy())

        with sd.InputStream(device=rec_dev, samplerate=SR, channels=1,
                            dtype="float32", callback=on_input):
            # brief silence so the input stream + device are streaming before the clip
            sd.play(np.zeros(int(0.3 * SR), np.float32), SR, device=play_dev, blocking=True)
            with lock:
                start = sum(len(c) for c in chunks)
            tail = np.zeros(int(TAIL_S * SR), np.float32)
            sd.play(np.concatenate([audio, tail]), SR, device=play_dev, blocking=True)
            time.sleep(0.1)
        with lock:
            rec = np.concatenate(chunks) if chunks else np.zeros(0, np.float32)
    finally:
        engine.terminate()
        engine.wait(timeout=5)
    length = len(audio) + len(tail)
    return rec[start:start + length]


def main() -> None:
    filt = sys.argv[1] if len(sys.argv) > 1 else ""
    files = sorted(NOISY.glob("*.wav"))
    if filt and filt != "ALL":
        files = [f for f in files if filt.lower() in f.name.lower()]
    elif not filt:
        files = [f for f in files if f.name.startswith("aman_s0__")]
    if not files:
        sys.exit(f"no clips match '{filt}'")
    OUT.mkdir(parents=True, exist_ok=True)
    play_dev, rec_dev = find_device(PLAY_DEVICE, "output"), find_device(REC_DEVICE, "input")
    for i, f in enumerate(files, 1):
        rec = measure_clip(f, play_dev, rec_dev)
        sf.write(OUT / f.name, rec, SR, subtype="FLOAT")
        rms = float(np.sqrt(np.mean(rec**2))) if len(rec) else 0.0
        print(f"{i}/{len(files)} {f.name}  ({len(rec)/SR:.1f}s, RMS {rms:.4f})")
    print(f"\nwrote {len(files)} clips to {OUT} (fresh engine per clip)")


if __name__ == "__main__":
    main()
