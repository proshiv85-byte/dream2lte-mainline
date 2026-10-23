#!/usr/bin/env python3
"""Generate the "dusk" wallpaper: striped sun over layered mountains.

usage: wallpaper.py WIDTH HEIGHT OUT.png
"""
import sys

import numpy as np
from PIL import Image, ImageFilter

W, H, OUT = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
rng = np.random.default_rng(8895)
portrait = H > W


def hexrgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float64)


def gradient(stops, n):
    """Interpolate color stops [(pos, '#rrggbb'), ...] over n samples."""
    pos = np.array([p for p, _ in stops])
    cols = np.array([hexrgb(c) for _, c in stops])
    t = np.linspace(0, 1, n)
    return np.stack([np.interp(t, pos, cols[:, k]) for k in range(3)], axis=1)


horizon = 0.62 if portrait else 0.66
img = np.zeros((H, W, 3))

# sky
sky = gradient([(0.0, '#0b0913'), (0.22, '#15112a'), (0.40, '#2a1d47'),
                (0.52, '#5a2f63'), (0.58, '#a24d72'), (0.62, '#e0798a'),
                (0.66, '#f4a98c'), (1.0, '#f4a98c')], H)
sky_y = np.clip(np.arange(H) / (horizon * H) * 0.66, 0, 1)
img[:] = gradient([(0.0, '#0b0913'), (0.33, '#15112a'), (0.6, '#2a1d47'),
                   (0.79, '#5a2f63'), (0.88, '#a24d72'), (0.94, '#e0798a'),
                   (1.0, '#f4a98c')], 1000)[(np.clip(np.arange(H) / (horizon * H), 0, 1) * 999).astype(int)][:, None, :]

yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)

# stars, fading out towards the horizon
nstars = int(W * H / 2500)
sx = rng.uniform(0, W, nstars)
sy = rng.uniform(0, H * horizon * 0.8, nstars) ** 1.0
sb = rng.uniform(0.15, 1.0, nstars) ** 3
star = np.zeros((H, W))
for x, y, b in zip(sx.astype(int), sy.astype(int), sb):
    fade = 1 - y / (H * horizon * 0.8)
    star[y, x] = max(star[y, x], b * fade)
glow = np.asarray(Image.fromarray((star * 255).astype(np.uint8)).filter(
    ImageFilter.GaussianBlur(W / 900)), dtype=np.float64) / 255
star = np.clip(star + glow * 2.2, 0, 1)
img += star[:, :, None] * hexrgb('#f4eefc')[None, None, :] * 0.9

# sun: soft glow, then a disc with a vertical gradient and widening gaps
cx, cy = W / 2, H * horizon - (W * 0.06 if portrait else H * 0.04)
r = (W * 0.27) if portrait else (H * 0.30)
d = np.hypot(xx - cx, yy - cy)
glow = np.exp(-((d / (r * 1.9)) ** 2))
img += glow[:, :, None] * hexrgb('#e86f86')[None, None, :] * 0.35
disc = np.clip(r - d + 1.5, 0, 1)
t = np.clip((yy - (cy - r)) / (2 * r), 0, 1)
suncol = gradient([(0.0, '#ffe2a8'), (0.45, '#f9a98a'), (1.0, '#e8607f')], 1000)
sun = suncol[(t * 999).astype(int)]
# gaps in the lower half, thicker towards the bottom
rel = (yy - cy) / r
period = r * 0.11
phase = np.mod(yy - cy, period) / period
gapw = np.clip((rel + 0.30) * 0.95, 0, 0.7)
stripes = np.where((rel > -0.30) & (phase < gapw), 0.0, 1.0)
stripes = np.asarray(Image.fromarray((stripes * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), dtype=np.float64) / 255
alpha = (disc * stripes)[:, :, None]
img = img * (1 - alpha) + sun * alpha


def ridge(n, rough, seed):
    """Midpoint displacement ridge line, n samples in [0, 1]."""
    r_ = np.random.default_rng(seed)
    size = 1
    while size < n:
        size *= 2
    h = np.zeros(size + 1)
    h[0], h[-1] = r_.uniform(-0.3, 0.3, 2)
    step, amp = size, 1.0
    while step > 1:
        half = step // 2
        for i in range(half, size, step):
            h[i] = (h[i - half] + h[i + half]) / 2 + r_.uniform(-amp, amp)
        step, amp = half, amp * rough
    xs = np.linspace(0, size, n)
    return np.interp(xs, np.arange(size + 1), h)


# mountain layers, back (hazy) to front (dark)
layers = [
    (horizon + 0.005, 0.060, '#7a3f6e', '#4b2c55', 0.62, 11),
    (horizon + 0.035, 0.075, '#4a2a52', '#2d1e3d', 0.58, 23),
    (horizon + 0.075, 0.085, '#2b1c3a', '#1a1326', 0.55, 37),
    (horizon + 0.125, 0.090, '#171120', '#0e0a15', 0.52, 51),
]
if not portrait:
    layers = [(b - 0.01, a * 1.1, c1, c2, ro, s) for b, a, c1, c2, ro, s in layers]
for base, amp, ctop, cbot, rough, seed in layers:
    line = ridge(W, rough, seed)
    line = (line - line.min()) / (np.ptp(line) + 1e-9)
    top = (base - amp * line) * H
    mask = np.clip(yy - top[None, :] + 1, 0, 1)
    depth = np.clip((yy - top[None, :]) / (H * 0.18), 0, 1)
    col = (hexrgb(ctop)[None, None, :] * (1 - depth[:, :, None]) +
           hexrgb(cbot)[None, None, :] * depth[:, :, None])
    # mist at the foot of each layer
    img = img * (1 - mask[:, :, None]) + col * mask[:, :, None]
    fog = np.exp(-(((yy - (base * H + H * 0.02)) / (H * 0.018)) ** 2)) * 0.22
    img += fog[:, :, None] * hexrgb('#c06a86')[None, None, :] * (1 - depth[:, :, None])

# reflection-free dark ground towards the bottom, for the bar and keyboard
ground = np.clip((yy - H * (horizon + 0.20)) / (H * 0.18), 0, 1)
img = img * (1 - ground[:, :, None] * 0.55) + hexrgb('#0b0913') * ground[:, :, None] * 0.55

# vignette and grain
v = np.hypot((xx - W / 2) / (W * 0.75), (yy - H * 0.45) / (H * 0.75))
img *= np.clip(1.08 - v ** 2 * 0.45, 0.55, 1)[:, :, None]
img += rng.normal(0, 3.2, img.shape)

Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(OUT, optimize=True)
print(OUT, W, H)
