"""Generate a synthetic noisy-speech test set.

Clean speech comes from macOS `say`; noise is synthesized. Everything is 48 kHz mono float32.
Output: data/clean/*.wav, data/noise/*.wav, data/noisy/<clean>__<noise>__<snr>dB.wav
"""

import subprocess
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

SR = 48_000
ROOT = Path(__file__).parent / "data"
RNG = np.random.default_rng(1234)

VOICES = ["Aman", "Rishi", "Daniel", "Samantha"]
SENTENCES = [
    "The quarterly sales review is scheduled for Thursday afternoon in the main conference room.",
    "Please share the updated floor plans with the site engineer before the end of the day.",
    "Could you confirm whether the booking amount has been received from the customer?",
    "We need to finalize the vendor contracts and send the purchase orders by Monday morning.",
]
BABBLE_SENTENCES = [
    "I think the coffee machine on the third floor is broken again today.",
    "Did anyone see the cricket match yesterday evening, it was incredible.",
    "Let me check my calendar and get back to you after lunch.",
    "The traffic on the highway was terrible because of the construction work.",
]
SNRS_DB = [0, 5, 10, 20]


def tts(text: str, voice: str) -> np.ndarray:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "s.wav"
        subprocess.run(
            ["say", "-v", voice, "-o", str(out), "--file-format=WAVE", f"--data-format=LEF32@{SR}", text],
            check=True,
        )
        audio, sr = sf.read(out, dtype="float32")
    assert sr == SR
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    return audio


def colored_noise(n: int, exponent: float) -> np.ndarray:
    """1/f^exponent noise: 0 = white, 1 = pink, 2 = brown."""
    spectrum = RNG.standard_normal(n // 2 + 1) + 1j * RNG.standard_normal(n // 2 + 1)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    freqs[0] = freqs[1]
    spectrum /= freqs ** (exponent / 2)
    x = np.fft.irfft(spectrum, n)
    return x / np.max(np.abs(x))


def noise_fan(n: int) -> np.ndarray:
    t = np.arange(n) / SR
    hum = sum(np.sin(2 * np.pi * f * t) / k for k, f in enumerate([100, 200, 300], start=1))
    b, a = signal.butter(4, 3000, "low", fs=SR)
    return signal.lfilter(b, a, colored_noise(n, 1.0)) + 0.15 * hum


def noise_keyboard(n: int) -> np.ndarray:
    out = np.zeros(n)
    click_len = int(0.015 * SR)
    env = np.exp(-np.linspace(0, 8, click_len))
    b, a = signal.butter(2, [1500, 9000], "band", fs=SR)
    pos = 0
    while pos < n - click_len:
        burst = signal.lfilter(b, a, RNG.standard_normal(click_len)) * env * RNG.uniform(0.5, 1.0)
        out[pos : pos + click_len] += burst
        pos += int(RNG.exponential(0.15) * SR) + int(0.05 * SR)
    return out


def noise_traffic(n: int) -> np.ndarray:
    t = np.arange(n) / SR
    rumble = colored_noise(n, 2.0) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.2 * t))
    horn = np.zeros(n)
    for start in RNG.uniform(0, max(n / SR - 1.0, 0.1), size=3):
        s, e = int(start * SR), int((start + 0.6) * SR)
        tt = t[s:e]
        horn[s:e] += 0.3 * np.sign(np.sin(2 * np.pi * 420 * tt)) * np.hanning(e - s)
    return rumble + horn


def noise_babble(n: int) -> np.ndarray:
    voices = ["Karen", "Eddy (English (US))", "Flo (English (UK))", "Reed (English (US))"]
    out = np.zeros(n)
    for text, voice in zip(BABBLE_SENTENCES, voices):
        speech = tts(text, voice)
        speech = np.tile(speech, int(np.ceil(n / len(speech))))[:n]
        out += np.roll(speech, RNG.integers(0, n))
    b, a = signal.butter(2, 3500, "low", fs=SR)  # distant talkers sound muffled
    return signal.lfilter(b, a, out)


def noise_music(n: int) -> np.ndarray:
    t = np.arange(n) / SR
    chords = [[261.6, 329.6, 392.0], [220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [196.0, 246.9, 293.7]]
    out = np.zeros(n)
    seg = int(1.0 * SR)
    for i in range(0, n, seg):
        chord = chords[(i // seg) % len(chords)]
        tt = t[i : i + seg]
        env = np.minimum(1, np.linspace(0, 20, len(tt))) * np.exp(-np.linspace(0, 2, len(tt)))
        out[i : i + seg] = sum(np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(4 * np.pi * f * tt) for f in chord) * env
    return out


def noise_white(n: int) -> np.ndarray:
    return colored_noise(n, 0.0)


NOISES = {
    "fan": noise_fan,
    "keyboard": noise_keyboard,
    "traffic": noise_traffic,
    "babble": noise_babble,
    "music": noise_music,
    "white": noise_white,
}


def active_rms(x: np.ndarray) -> float:
    """RMS over 20 ms frames whose energy is within 40 dB of the loudest frame."""
    frame = int(0.02 * SR)
    frames = x[: len(x) // frame * frame].reshape(-1, frame)
    energy = (frames**2).mean(axis=1)
    active = energy > energy.max() * 1e-4
    return float(np.sqrt(energy[active].mean()))


def mix(clean: np.ndarray, noise: np.ndarray, snr_db: float) -> np.ndarray:
    noise_rms = np.sqrt((noise**2).mean())
    scaled = noise * (active_rms(clean) / (noise_rms * 10 ** (snr_db / 20)))
    noisy = clean + scaled
    peak = np.max(np.abs(noisy))
    return noisy / peak * 0.9 if peak > 0.9 else noisy


def main() -> None:
    for d in ("clean", "noise", "noisy"):
        (ROOT / d).mkdir(parents=True, exist_ok=True)

    lead = np.zeros(int(0.5 * SR), dtype=np.float32)  # silence on both ends for latency/NC warm-up
    cleans = {}
    for vi, voice in enumerate(VOICES):
        for si in (vi % 4, (vi + 1) % 4):
            name = f"{voice.split()[0].lower()}_s{si}"
            audio = np.concatenate([lead, tts(SENTENCES[si], voice), lead])
            audio = audio / np.max(np.abs(audio)) * 0.5
            sf.write(ROOT / "clean" / f"{name}.wav", audio, SR, subtype="FLOAT")
            cleans[name] = audio

    longest = max(len(a) for a in cleans.values())
    for noise_name, make in NOISES.items():
        noise = make(longest)
        noise = noise / np.max(np.abs(noise))
        sf.write(ROOT / "noise" / f"{noise_name}.wav", noise.astype(np.float32), SR, subtype="FLOAT")
        for clean_name, clean in cleans.items():
            for snr in SNRS_DB:
                noisy = mix(clean, noise[: len(clean)], snr).astype(np.float32)
                sf.write(ROOT / "noisy" / f"{clean_name}__{noise_name}__{snr}dB.wav", noisy, SR, subtype="FLOAT")

    print(f"{len(cleans)} clean clips, {len(NOISES)} noises, {len(SNRS_DB)} SNRs -> "
          f"{len(list((ROOT / 'noisy').glob('*.wav')))} noisy files")


if __name__ == "__main__":
    main()
