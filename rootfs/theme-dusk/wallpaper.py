#!/usr/bin/env python3
"""Minimal "dusk" wallpaper: one muted sun behind one ridge, dark background.

usage: wallpaper-min.py WIDTH HEIGHT OUT.png
"""
import sys

import numpy as np
from PIL import Image

W, H, OUT = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
rng = np.random.default_rng(8895)
portrait = H > W


def hexrgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float64)


yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)

# background: very slight vertical gradient
t = (yy / H)[:, :, None]
img = hexrgb('#17151b') * (1 - t) + hexrgb('#0f0e11') * t

# sun
horizon = 0.56 if portrait else 0.62
cx = W / 2
r = (W * 0.17) if portrait else (H * 0.20)
cy = H * horizon - r * 0.35
d = np.hypot(xx - cx, yy - cy)
disc = np.clip(r - d + 1.0, 0, 1)[:, :, None]
img = img * (1 - disc) + hexrgb('#d9a48f') * disc

# one smooth ridge in front of it
x = np.linspace(0, 1, W)
ridge = (0.030 * np.sin(x * 5.3 + 0.7) + 0.018 * np.sin(x * 11.9 + 2.1) +
         0.008 * np.sin(x * 23.0 + 0.3))
top = (horizon + ridge * (1 if portrait else 0.8)) * H
mask = np.clip(yy - top[None, :] + 1.0, 0, 1)[:, :, None]
img = img * (1 - mask) + hexrgb('#0c0b0e') * mask

# fine grain
img += rng.normal(0, 1.6, img.shape)
Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(OUT, optimize=True)
print(OUT, W, H)
