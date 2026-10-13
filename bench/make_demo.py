"""Render docs/demo.gif: noisy input vs Sotto-cleaned, with a sweeping playhead."""
import numpy as np, soundfile as sf
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
noisy, sr = sf.read("data/noisy/aman_s0__fan__10dB.wav", dtype="float32")
clean, _ = sf.read("out/sotto/aman_s0__fan__10dB.wav", dtype="float32")

W, H = 760, 380
cols = 360
pad = 40
panelH = 120
teal = (18, 160, 133)
gray = (150, 150, 150)
dark = (40, 40, 42)

def envelope(x, n):
    x = x[: len(x)//n*n].reshape(n, -1)
    e = np.sqrt((x**2).mean(axis=1))
    return e / (e.max() + 1e-9)

en = envelope(noisy, cols)
ec = envelope(clean, cols)

def draw_panel(d, top, env, color, label):
    mid = top + panelH//2
    bw = (W - 2*pad) / cols
    for i, v in enumerate(env):
        x = pad + i*bw
        h = v * (panelH//2 - 6)
        d.rectangle([x, mid-h, x+bw*0.7, mid+h], fill=color)
    d.text((pad, top-20), label, fill=dark, font=FONT)

try:
    FONT = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 15)
    FBIG = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 22)
except Exception:
    FONT = ImageFont.load_default(); FBIG = FONT

frames = []
N = 48
for f in range(N):
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)
    d.text((pad, 14), "Sotto", fill=teal, font=FBIG)
    d.text((pad+78, 20), "noise cancellation, on-device", fill=gray, font=FONT)
    draw_panel(d, 110, en, gray, "Input  ·  mic with background noise")
    draw_panel(d, 270, ec, teal, "Output  ·  Sotto Microphone")
    px = pad + (W - 2*pad) * (f / (N - 1))
    d.line([px, 92, px, 400], fill=(0, 0, 0), width=1)
    frames.append(img)

out = ROOT / "docs"; out.mkdir(exist_ok=True)
frames += frames[::-1]
frames[0].save(out/"demo.gif", save_all=True, append_images=frames[1:], duration=70, loop=0, optimize=True)
print("wrote", out/"demo.gif")
