#!/usr/bin/env python3
"""Builds the Android launcher icons from icon_source.jpg (design by Sia).

The source is a finished rounded-square icon: a logo on a blue panel.
Android masks launcher icons itself, so the panel is rebuilt full bleed:
a plane fitted to the panel's colour (outside the logo) gives the
background, and the logo (with its shadow) is lifted off by its difference
from that plane and pasted back on top.

  python3 tool/icon/make_icon.py      (from android/, needs Pillow + numpy)
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, '..', '..', 'android', 'app', 'src', 'main', 'res')
src = np.asarray(Image.open(os.path.join(HERE, 'icon_source.jpg')).convert('RGB')).astype(float)
H, W, _ = src.shape
IN = (150, 1130)                   # inside the panel's edge, both axes

# 1. Fit colour = a + b*x + c*y per channel on panel pixels (logo excluded).
ys, xs = np.mgrid[0:H, 0:W]
rr = Image.new('L', (W, H), 0)     # inner area with the panel's round corners
ImageDraw.Draw(rr).rounded_rectangle([IN[0], IN[0], IN[1], IN[1]], radius=260, fill=1)
inner = np.asarray(rr).astype(bool)
rough = np.abs(src - np.median(src[inner], axis=0)).sum(axis=2) < 90
A = np.stack([np.ones(H * W), xs.ravel(), ys.ravel()], 1)
sel = (inner & rough).ravel()
for _ in range(3):                 # refit, dropping pixels far from the plane
    coef, *_ = np.linalg.lstsq(A[sel], src.reshape(-1, 3)[sel], rcond=None)
    plane = (A @ coef).reshape(H, W, 3)
    diff = np.linalg.norm(src - plane, axis=2)
    sel = (inner & (diff < 20)).ravel()

# 2. Logo alpha: soft ramp on the difference, only inside the panel.
# The panel darkens slightly towards its bevel; fade the lift out near the
# edge of the inner area so that shading doesn't come along as a frame.
edge = np.minimum(np.minimum(xs - IN[0], IN[1] - xs), np.minimum(ys - IN[0], IN[1] - ys))
alpha = np.clip((diff - 18) / 24, 0, 1) * np.clip(edge / 14, 0, 1) * inner
a_img = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
a = np.asarray(a_img).astype(float) / 255
yy, xx = np.where(a > 0.5)
cx, cy = (xx.min() + xx.max()) / 2, (yy.min() + yy.max()) / 2
span = max(xx.max() - xx.min(), yy.max() - yy.min())
# un-premultiply against the plane so edges carry the logo colour only
logo = np.where(a[..., None] > 0.01,
                (src - plane * (1 - a[..., None])) / np.maximum(a[..., None], 0.01), 0)
logo_rgba = Image.fromarray(np.dstack([np.clip(logo, 0, 255), a * 255]).astype(np.uint8), 'RGBA')

def master(size, logo_frac):
    """Full-bleed square; the logo's larger side takes logo_frac*size."""
    s = logo_frac * size / span
    oy, ox = np.mgrid[0:size, 0:size].astype(float)
    sx, sy = cx + (ox - size / 2) / s, cy + (oy - size / 2) / s
    bg = coef[0] + coef[1] * sx[..., None] + coef[2] * sy[..., None]
    img = Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')
    lg = logo_rgba.resize((round(W * s), round(H * s)), Image.LANCZOS)
    img.alpha_composite(lg, (round(size / 2 - cx * s), round(size / 2 - cy * s)))
    return img

DENS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

# Adaptive icon (API 26+): 108 dp layer; launchers show the inner 72 dp,
# the safe zone is a 66 dp circle.
fg = master(1024, 0.56).convert('RGB')
for d, k in DENS.items():
    fg.resize((round(108 * k),) * 2, Image.LANCZOS).save(
        os.path.join(RES, f'mipmap-{d}', 'ic_launcher_foreground.png'), optimize=True)

# Legacy icon (below API 26): 48 dp rounded square.
leg = master(1024, 0.70)
m = Image.new('L', (4096, 4096), 0)
ImageDraw.Draw(m).rounded_rectangle([64, 64, 4031, 4031], radius=900, fill=255)
leg.putalpha(m.resize((1024, 1024), Image.LANCZOS))
for d, k in DENS.items():
    leg.resize((round(48 * k),) * 2, Image.LANCZOS).save(
        os.path.join(RES, f'mipmap-{d}', 'ic_launcher.png'), optimize=True)

fg.save(os.path.join(HERE, 'icon_fullbleed.png'))
leg.save(os.path.join(HERE, 'icon_rounded.png'))
print('plane', np.round(coef, 3).tolist(), 'logo centre', cx, cy, 'span', span)
