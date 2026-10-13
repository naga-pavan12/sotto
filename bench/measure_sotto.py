"""Measure Sotto end-to-end, live, through the real driver + engine.

Signal path:
  this script plays noisy clips -> BlackHole 2ch (output)
  BlackHole loopback -> BlackHole input
  SottoCLI engine captures BlackHole -> DeepFilterNet3 -> Sotto Bridge -> Sotto Microphone
  this script records Sotto Microphone

The SottoCLI.app engine must be running and capturing BlackHole2ch_UID. This script
launches it. Recordings are scored by evaluate.py (system name "sotto").

Usage: uv run python measure_sotto.py [n_clips]
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
OUT = ROOT / "out" / "sotto"
SR = 48_000
PLAY_DEVICE = "BlackHole 2ch"
REC_DEVICE = "Sotto Microphone"
CLI_APP = "/tmp/SottoCLI.app/Contents/MacOS/SottoCLI"
GAP_S = 0.8
WARMUP_S = 3.0


def find_device(name: str, kind: str) -> int:
    for i, dev in enumerate(sd.query_devices()):
        if name.lower() in dev["name"].lower() and dev[f"max_{kind}_channels"] > 0:
            return i
    sys.exit(f"device '{name}' ({kind}) not found")


def main() -> None:
    files = sorted(NOISY.glob("*.wav"))
    if len(sys.argv) > 1:
        files = files[: int(sys.argv[1])]
    OUT.mkdir(parents=True, exist_ok=True)
    play_dev, rec_dev = find_device(PLAY_DEVICE, "output"), find_device(REC_DEVICE, "input")

    total_s = WARMUP_S + sum(sf.info(f).duration + GAP_S for f in files) + 2
    engine = subprocess.Popen([CLI_APP, "BlackHole2ch_UID", str(int(total_s) + 2)])
    time.sleep(WARMUP_S)

    chunks: list[np.ndarray] = []
    lock = threading.Lock()

    def on_input(indata, frames, t, status):
        with lock:
            chunks.append(indata[:, 0].copy())

    def recorded() -> int:
        with lock:
            return sum(len(c) for c in chunks)

    windows = []
    with sd.InputStream(device=rec_dev, samplerate=SR, channels=1, dtype="float32", callback=on_input):
        sd.play(np.zeros(int(0.5 * SR), np.float32), SR, device=play_dev, blocking=True)
        for i, f in enumerate(files, 1):
            audio, sr = sf.read(f, dtype="float32")
            assert sr == SR
            start = recorded()
            sd.play(np.concatenate([audio, np.zeros(int(GAP_S * SR), np.float32)]), SR,
                    device=play_dev, blocking=True)
            windows.append((f.name, start, len(audio) + int(GAP_S * SR)))
            print(f"\r{i}/{len(files)} {f.name}", end="", flush=True)
        time.sleep(GAP_S)

    with lock:
        rec = np.concatenate(chunks) if chunks else np.zeros(0, np.float32)
    engine.terminate()
    for name, start, length in windows:
        sf.write(OUT / name, rec[start:start + length], SR, subtype="FLOAT")
    overall_rms = float(np.sqrt(np.mean(rec**2))) if len(rec) else 0.0
    print(f"\nsaved {len(windows)} clips to {OUT}; recorded {len(rec)/SR:.0f}s, overall RMS {overall_rms:.4f}")


if __name__ == "__main__":
    main()
