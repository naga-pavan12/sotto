"""Run the noisy test set through Krisp's live noise cancellation.

Setup (once):
  1. Install a loopback device:  brew install blackhole-2ch
  2. In Krisp, set Microphone to "BlackHole 2ch" and turn noise cancellation on.

This script plays each noisy file into BlackHole (Krisp's input) while recording from
"krisp microphone" (Krisp's output) in one continuous session, so Krisp sees a single
call. Each file's recording window is saved to out/krisp/ with a margin; evaluate.py
aligns it by cross-correlation and reports the measured delay.
"""

import sys
import threading
import time
from pathlib import Path

import numpy as np
import sounddevice as sd
import soundfile as sf

ROOT = Path(__file__).parent
NOISY = ROOT / "data" / "noisy"
OUT = ROOT / "out" / "krisp"
SR = 48_000
PLAY_DEVICE = "BlackHole 2ch"
REC_DEVICE = "krisp microphone"
WARMUP_S = 5.0  # let Krisp detect the "call" and settle before the first clip
GAP_S = 0.8  # silence between clips; also the tail margin kept after each clip


def find_device(name: str, kind: str) -> int:
    for i, dev in enumerate(sd.query_devices()):
        if name.lower() in dev["name"].lower() and dev[f"max_{kind}_channels"] > 0:
            return i
    sys.exit(f"Device '{name}' with {kind} channels not found. See setup steps in this file.")


def main() -> None:
    play_dev, rec_dev = find_device(PLAY_DEVICE, "output"), find_device(REC_DEVICE, "input")
    files = sorted(NOISY.glob("*.wav"))
    if len(sys.argv) > 1:
        files = files[: int(sys.argv[1])]
    OUT.mkdir(parents=True, exist_ok=True)

    chunks: list[np.ndarray] = []
    lock = threading.Lock()

    def on_input(indata, frames, time_info, status):
        with lock:
            chunks.append(indata[:, 0].copy())

    def recorded_frames() -> int:
        with lock:
            return sum(len(c) for c in chunks)

    windows = []
    with sd.InputStream(device=rec_dev, samplerate=SR, channels=1, dtype="float32", callback=on_input):
        sd.play(np.zeros(int(WARMUP_S * SR), dtype=np.float32), SR, device=play_dev, blocking=True)
        for i, f in enumerate(files, 1):
            audio, sr = sf.read(f, dtype="float32")
            assert sr == SR, f"{f.name}: expected {SR} Hz"
            start = recorded_frames()
            sd.play(np.concatenate([audio, np.zeros(int(GAP_S * SR), np.float32)]), SR,
                    device=play_dev, blocking=True)
            windows.append((f.name, start, len(audio) + int(GAP_S * SR)))
            print(f"\r{i}/{len(files)} {f.name}", end="", flush=True)
        time.sleep(GAP_S)

    with lock:
        recording = np.concatenate(chunks)
    for name, start, length in windows:
        sf.write(OUT / name, recording[start : start + length], SR, subtype="FLOAT")
    print(f"\nsaved {len(windows)} clips to {OUT} ({len(recording) / SR:.0f} s recorded)")


if __name__ == "__main__":
    main()
