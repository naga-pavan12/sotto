"""Offline reference using Sotto's OWN denoiser crate (not the deep-filter CLI).

Drives libsotto_denoiser.dylib hop-by-hop at 48 kHz mono, exactly as the live
app does (same strength->atten_lim mapping), but with no audio devices, no rings,
no resampler, and fresh model state. This isolates the model from the real-time
pipeline so out/sotto (live) can be compared against the same model offline.

Usage: uv run python sotto_offline.py [n_clips] [strength]
"""

import ctypes
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).parent
DYLIB = ROOT.parent / "denoiser" / "target" / "release" / "libsotto_denoiser.dylib"
NOISY = ROOT / "data" / "noisy"
OUT = ROOT / "out" / "sotto_offline"
SR = 48_000


def load_lib() -> ctypes.CDLL:
    lib = ctypes.CDLL(str(DYLIB))
    lib.sotto_denoiser_new.restype = ctypes.c_void_p
    lib.sotto_denoiser_hop_size.restype = ctypes.c_uint32
    lib.sotto_denoiser_hop_size.argtypes = [ctypes.c_void_p]
    lib.sotto_denoiser_set_atten_lim_db.argtypes = [ctypes.c_void_p, ctypes.c_float]
    lib.sotto_denoiser_process.restype = ctypes.c_int32
    lib.sotto_denoiser_process.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_float),
        ctypes.POINTER(ctypes.c_float),
    ]
    lib.sotto_denoiser_free.argtypes = [ctypes.c_void_p]
    return lib


def atten_db(strength: int) -> float:
    return 100.0 if strength >= 100 else strength * 0.4


def process(lib, audio: np.ndarray, strength: int) -> np.ndarray:
    d = lib.sotto_denoiser_new()
    if not d:
        sys.exit("sotto_denoiser_new failed")
    lib.sotto_denoiser_set_atten_lim_db(d, atten_db(strength))
    hop = lib.sotto_denoiser_hop_size(d)
    n = len(audio) // hop
    out = np.zeros(n * hop, np.float32)
    inbuf = (ctypes.c_float * hop)()
    outbuf = (ctypes.c_float * hop)()
    for i in range(n):
        chunk = audio[i * hop : (i + 1) * hop]
        inbuf[:] = chunk
        rc = lib.sotto_denoiser_process(d, inbuf, outbuf)
        out[i * hop : (i + 1) * hop] = chunk if rc != 0 else np.frombuffer(outbuf, np.float32)
    lib.sotto_denoiser_free(d)
    return out


def main() -> None:
    n_clips = int(sys.argv[1]) if len(sys.argv) > 1 else 24
    strength = int(sys.argv[2]) if len(sys.argv) > 2 else 80
    lib = load_lib()
    OUT.mkdir(parents=True, exist_ok=True)
    files = sorted(NOISY.glob("*.wav"))[:n_clips]
    for i, f in enumerate(files, 1):
        audio, sr = sf.read(f, dtype="float32")
        assert sr == SR, f"{f} is {sr} Hz"
        if audio.ndim > 1:
            audio = audio.mean(1)
        out = process(lib, audio.astype(np.float32), strength)
        sf.write(OUT / f.name, out, SR, subtype="FLOAT")
        print(f"\r{i}/{len(files)} {f.name}", end="", flush=True)
    print(f"\nwrote {len(files)} clips to {OUT} (strength {strength}, atten {atten_db(strength)} dB)")


if __name__ == "__main__":
    main()
