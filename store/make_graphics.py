#!/usr/bin/env python3
"""Builds the Google Play graphics from the app icon and the app's fonts.

  python3 store/make_graphics.py          (from the repo root; needs Pillow)

Writes store/out/: icon_512.png (Play draws its own rounded mask, so the
full-bleed icon is used), feature_{de,en}.png (1024x500 feature graphic) and
shot_{de,en}_N_<name>.png: phone screenshots from store/raw/<lang>/ (taken
with manual/tools/ui.py, dark theme, 1080x2424 with the status and
gesture bars cut off: rows 140..2374) framed at 1080x1920 (9:16;
Play allows at most 2:1) with a caption. Texts per language are in FEATURE
and SHOTS below.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
ICON = os.path.join(ROOT, 'android', 'tool', 'icon', 'icon_fullbleed.png')
FONT = os.path.join(ROOT, 'android', 'assets', 'fonts', 'DMSans.ttf')
OUT = os.path.join(ROOT, 'store', 'out')

FEATURE = {
    'de': ('Morsen lernen, überall', 'Hören · Geben · Keyer · Decoder · Spiele'),
    'en': ('Learn Morse code anywhere', 'Copy · Send · Keyer · Decoder · Games'),
}
SHOTS = [  # (raw file, DE caption, EN caption), in store order
    ('home', 'Alles fürs CW-Training', 'Everything for CW practice'),
    ('hear', 'Hören mit der Koch-Methode', 'Copy with the Koch method'),
    ('hear_stats', 'Statistik für jedes Zeichen', 'Statistics for every character'),
    ('echo_stats', 'Geben üben: was du verwechselst', 'Sending: see what you mix up'),
    ('qso', 'QSO-Bot als Übungspartner', 'QSO Bot as a practice partner'),
    ('games', 'Spielend morsen lernen', 'Learn Morse through games'),
    ('adventure', 'Klassische Text-Adventures in CW', 'Classic text adventures in CW'),
]
RAW = os.path.join(ROOT, 'store', 'raw')
TOP, BOTTOM = (116, 153, 212), (45, 70, 125)      # the icon's panel gradient
DOT, DASH = 18, 54                                  # "CW" in Morse as a motif


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def gradient(w, h):
    im = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return im


def rounded(im, radius):
    mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius, fill=255)
    out = im.convert('RGBA')
    out.putalpha(mask)
    return out


def morse(d, x, y, code, colour):
    for sym in code:
        if sym == ' ':
            x += DOT * 2
            continue
        w = DOT if sym == '.' else DASH
        d.rounded_rectangle([x, y, x + w, y + DOT], DOT // 2, fill=colour)
        x += w + DOT


def feature(lang):
    title_sub, line = FEATURE[lang]
    im = gradient(1024, 500)
    icon = Image.open(ICON).convert('RGB')
    m = icon.width * 12 // 100                      # trim the adaptive-icon margin
    icon = rounded(icon.crop((m, m, icon.width - m, icon.height - m)).resize((300, 300), Image.LANCZOS), 66)
    shadow = Image.new('RGBA', (1024, 500), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([72, 112, 372, 412], 66, fill=(10, 20, 50, 110))
    im.paste(shadow.filter(ImageFilter.GaussianBlur(14)), (0, 0), shadow.filter(ImageFilter.GaussianBlur(14)))
    im.paste(icon, (64, 100), icon)
    d = ImageDraw.Draw(im)
    x = 420
    d.text((x, 118), 'Next CW Trainer', font=font(64, 'Bold'), fill='white')
    d.text((x, 204), title_sub, font=font(36, 'Medium'), fill=(255, 214, 102))
    d.text((x, 256), line, font=font(24, 'Regular'), fill=(225, 234, 250))
    morse(d, x, 330, '-.-. .--', (94, 214, 214))
    return im


def shot(lang, name, caption):
    im = gradient(1080, 1920)
    d = ImageDraw.Draw(im)
    size = 64
    while d.textlength(caption, font=font(size, 'Bold')) > 960:   # 60 px margin
        size -= 2
    f = font(size, 'Bold')
    d.text((540, 150), caption, font=f, fill='white', anchor='mm')
    morse(d, 540 - 157, 225, '-.-. .--', (94, 214, 214))
    raw = Image.open(os.path.join(RAW, lang, name + '.png')).convert('RGB')
    h = 1920 - 300 - 40
    w = round(raw.width * h / raw.height)
    x, y = (1080 - w) // 2, 300
    shadow = Image.new('RGBA', im.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x + 6, y + 14, x + w + 6, y + h + 14], 40, fill=(5, 10, 30, 140))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    im.paste(shadow, (0, 0), shadow)
    phone = rounded(raw.resize((w, h), Image.LANCZOS), 40)
    im.paste(phone, (x, y), phone)
    return im


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    Image.open(ICON).convert('RGB').resize((512, 512), Image.LANCZOS).save(
        os.path.join(OUT, 'icon_512.png'), optimize=True)
    for lang in FEATURE:
        feature(lang).save(os.path.join(OUT, f'feature_{lang}.png'), optimize=True)
    for i, (name, de, en) in enumerate(SHOTS, 1):
        for lang, cap in (('de', de), ('en', en)):
            shot(lang, name, cap).save(os.path.join(OUT, f'shot_{lang}_{i}_{name}.png'), optimize=True)
    print('written to', os.path.relpath(OUT))
