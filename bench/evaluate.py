"""Score every system in out/ against the clean references.

Metrics per file:
  - DNSMOS P.835 (SIG speech quality, BAK noise intrusiveness, OVRL overall), no reference needed
  - PESQ wideband and STOI (reference-based)
  - SI-SDR in dB (reference-based)
  - delay_ms: output delay estimated by cross-correlation (outputs are aligned before scoring)

"noisy" (unprocessed input) is always included as the reference row.
Writes results/scores.csv and prints a summary by system and by system x noise type.
"""

import csv
import sys
from collections import defaultdict
from pathlib import Path

import librosa
import numpy as np
import onnxruntime as ort
import soundfile as sf
from pesq import pesq
from pystoi import stoi
from scipy import signal

ROOT = Path(__file__).parent
CLEAN = ROOT / "data" / "clean"
NOISY = ROOT / "data" / "noisy"
OUT = ROOT / "out"
MAX_DELAY_S = 0.5

# DNSMOS P.835 (microsoft/DNS-Challenge, non-personalized model + calibration polynomials)
DNSMOS_SR = 16_000
DNSMOS_LEN = int(9.01 * DNSMOS_SR)
P_SIG = np.poly1d([-0.08397278, 1.22083953, 0.0052439])
P_BAK = np.poly1d([-0.13166888, 1.60915514, -0.39604546])
P_OVR = np.poly1d([-0.06766283, 1.11546468, 0.04602535])
_dnsmos = ort.InferenceSession(str(ROOT / "models" / "sig_bak_ovr.onnx"), providers=["CPUExecutionProvider"])


def dnsmos(audio16: np.ndarray) -> tuple[float, float, float]:
    x = audio16
    while len(x) < DNSMOS_LEN:
        x = np.concatenate([x, audio16])
    hop = DNSMOS_SR
    scores = []
    for start in range(0, max(1, len(x) - DNSMOS_LEN + 1), hop):
        seg = x[start : start + DNSMOS_LEN].astype(np.float32)[np.newaxis, :]
        sig, bak, ovr = _dnsmos.run(None, {"input_1": seg})[0][0]
        scores.append((P_SIG(sig), P_BAK(bak), P_OVR(ovr)))
    return tuple(float(v) for v in np.mean(scores, axis=0))


def estimate_delay(reference: np.ndarray, output: np.ndarray, sr: int) -> int:
    """Samples by which `output` lags `reference` (searched within +/- MAX_DELAY_S)."""
    max_lag = int(MAX_DELAY_S * sr)
    n = min(len(reference), len(output))
    corr = signal.correlate(output[:n], reference[:n], mode="full", method="fft")
    lags = signal.correlation_lags(n, n, mode="full")
    window = np.abs(lags) <= max_lag
    return int(lags[window][np.argmax(np.abs(corr[window]))])


def align(output: np.ndarray, delay: int, length: int) -> np.ndarray:
    out = output[delay:] if delay >= 0 else np.concatenate([np.zeros(-delay, output.dtype), output])
    return np.pad(out, (0, max(0, length - len(out))))[:length]


def si_sdr(ref: np.ndarray, est: np.ndarray) -> float:
    ref = ref - ref.mean()
    est = est - est.mean()
    target = np.dot(est, ref) / (np.dot(ref, ref) + 1e-12) * ref
    noise = est - target
    return float(10 * np.log10((target**2).sum() / ((noise**2).sum() + 1e-12) + 1e-12))


def score_file(system: str, path: Path) -> dict:
    clean_name, noise, snr = path.stem.split("__")
    clean, sr = sf.read(CLEAN / f"{clean_name}.wav", dtype="float32")
    output, out_sr = sf.read(path, dtype="float32")
    if output.ndim > 1:
        output = output.mean(axis=1)
    if out_sr != sr:
        output = librosa.resample(output, orig_sr=out_sr, target_sr=sr)
    delay = estimate_delay(clean, output, sr)
    output = align(output, delay, len(clean))

    clean16 = librosa.resample(clean, orig_sr=sr, target_sr=16_000)
    out16 = librosa.resample(output, orig_sr=sr, target_sr=16_000)
    try:
        pesq_wb = pesq(16_000, clean16, out16, "wb")
    except Exception:
        pesq_wb = float("nan")
    sig, bak, ovr = dnsmos(out16)
    return {
        "system": system,
        "file": path.stem,
        "noise": noise,
        "snr_db": int(snr.removesuffix("dB")),
        "delay_ms": round(delay / sr * 1000, 1),
        "pesq_wb": round(pesq_wb, 3),
        "stoi": round(float(stoi(clean, output, sr, extended=False)), 3),
        "si_sdr": round(si_sdr(clean, output), 2),
        "dnsmos_sig": round(sig, 3),
        "dnsmos_bak": round(bak, 3),
        "dnsmos_ovrl": round(ovr, 3),
    }


def main() -> None:
    systems = {"noisy": NOISY} | {d.name: d for d in sorted(OUT.iterdir()) if d.is_dir()}
    if len(sys.argv) > 1:
        systems = {k: v for k, v in systems.items() if k in sys.argv[1:] or k == "noisy"}

    rows = []
    for system, folder in systems.items():
        files = sorted(folder.glob("*.wav"))
        print(f"scoring {system}: {len(files)} files", flush=True)
        rows += [score_file(system, f) for f in files]

    (ROOT / "results").mkdir(exist_ok=True)
    with open(ROOT / "results" / "scores.csv", "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    metrics = ["pesq_wb", "stoi", "si_sdr", "dnsmos_sig", "dnsmos_bak", "dnsmos_ovrl", "delay_ms"]

    def summarize(key_fn, title):
        groups = defaultdict(list)
        for r in rows:
            groups[key_fn(r)].append(r)
        print(f"\n== {title}")
        print(f"{'group':34}" + "".join(f"{m:>12}" for m in metrics))
        for key in sorted(groups):
            vals = [np.nanmean([r[m] for r in groups[key]]) for m in metrics]
            print(f"{' / '.join(map(str, key)):34}" + "".join(f"{v:12.3f}" for v in vals))

    summarize(lambda r: (r["system"],), "by system")
    summarize(lambda r: (r["system"], r["snr_db"]), "by system x SNR")
    summarize(lambda r: (r["system"], r["noise"]), "by system x noise")


if __name__ == "__main__":
    main()
