"""Measure this harness's own playback->record delay without Krisp in the path.

Plays clips into "BlackHole 2ch" and records "BlackHole 2ch" input directly, using the
same streaming code path as capture_krisp.py. Subtract the result from Krisp's measured
delay to estimate Krisp's own latency (driver hop + processing + model lookahead).
"""

from pathlib import Path

import numpy as np
import sounddevice as sd
import soundfile as sf

from capture_krisp import GAP_S, NOISY, PLAY_DEVICE, SR, find_device
from evaluate import estimate_delay

N_CLIPS = 8


def main() -> None:
    dev = find_device(PLAY_DEVICE, "output")
    sd.playrec(np.zeros(SR, np.float32), SR, channels=1, device=(dev, dev), blocking=True)  # warm-up
    delays = []
    for f in sorted(NOISY.glob("*.wav"))[:N_CLIPS]:
        audio, _ = sf.read(f, dtype="float32")
        padded = np.concatenate([audio, np.zeros(int(GAP_S * SR), np.float32)])
        recording = sd.playrec(padded, SR, channels=1, device=(dev, dev), blocking=True)[:, 0]
        delays.append(estimate_delay(audio, recording, SR))

    ms = np.array(delays) / SR * 1000
    print(f"harness loopback delay: median {np.median(ms):.1f} ms (min {ms.min():.1f}, max {ms.max():.1f})")


if __name__ == "__main__":
    main()
