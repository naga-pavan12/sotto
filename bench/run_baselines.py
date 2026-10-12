"""Run non-AI baseline denoisers over data/noisy -> out/<system>/."""

import time
from pathlib import Path

import noisereduce as nr
import numpy as np
import soundfile as sf

ROOT = Path(__file__).parent
NOISY = ROOT / "data" / "noisy"


def spectral_gate(audio: np.ndarray, sr: int) -> np.ndarray:
    return nr.reduce_noise(y=audio, sr=sr, stationary=False, prop_decrease=0.9)


SYSTEMS = {"spectral_gate": spectral_gate}


def main() -> None:
    files = sorted(NOISY.glob("*.wav"))
    for name, fn in SYSTEMS.items():
        out_dir = ROOT / "out" / name
        out_dir.mkdir(parents=True, exist_ok=True)
        audio_s = proc_s = 0.0
        for f in files:
            audio, sr = sf.read(f, dtype="float32")
            start = time.perf_counter()
            enhanced = fn(audio, sr)
            proc_s += time.perf_counter() - start
            audio_s += len(audio) / sr
            sf.write(out_dir / f.name, enhanced.astype(np.float32), sr, subtype="FLOAT")
        print(f"{name}: {len(files)} files, real-time factor {proc_s / audio_s:.3f}")


if __name__ == "__main__":
    main()
