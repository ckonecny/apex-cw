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
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
ICON = os.path.join(ROOT, 'android', 'tool', 'icon', 'icon_fullbleed.png')
FONT = os.path.join(ROOT, 'android', 'assets', 'fonts', 'DMSans.ttf')
OUT = os.path.join(ROOT, 'store', 'out')

FEATURE = {
    'de': ('Morsen lernen, überall', 'Hören · Geben · Prüfung · Keyer · Spiele'),
    'en': ('Learn Morse code anywhere', 'Copy · Send · Exam · Keyer · Games'),
}
SHOTS = [  # (raw file, DE caption, EN caption), in store order
    ('home', 'Alles fürs CW-Training', 'Everything for CW practice'),
    ('hear', 'Hören mit der Koch-Methode', 'Copy with the Koch method'),
    ('hear_stats', 'Statistik für jedes Zeichen', 'Statistics for every character'),
    ('verstehen', 'Verstehen ohne Mitschreiben', 'Head copy without writing'),
    ('exam', 'Prüfungssimulation', 'Exam simulation'),
    ('qso', 'QSO-Bot als Übungspartner', 'QSO Bot as a practice partner'),
    ('themes', 'Sieben Farbschemata', 'Seven colour themes'),
    ('games', 'Spielend morsen lernen', 'Learn Morse through games'),
]
RAW = os.path.join(ROOT, 'store', 'raw')
SITE = os.path.join(ROOT, 'site', 'img')
# Fan of the seven colour themes: raw/<lang>/theme_N.png, left to right (the
# middle one is on top). N = the app's theme index (1 Light, 2 Dark, 3 Amber,
# 4 Red, 5 Green, 6 Warm grey, 7 Navy & orange).
THEME_ORDER = (1, 3, 4, 7, 5, 6, 2)

TOP, BOTTOM = (30, 52, 96), (18, 33, 64)           # the new icon's navy (#122140)
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
    d.text((x, 118), 'APEX CW', font=font(64, 'Bold'), fill='white')
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
    if name == 'games':   # scrollbar was captured at the right edge: paint over
        ImageDraw.Draw(raw).rectangle([raw.width - 14, 0, raw.width, raw.height], fill=raw.getpixel((raw.width - 30, 600)))
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


def fan(lang, size, card_w, crop_h, radius, step, pivot_y, bg=None):
    """Seven theme shots as a fan: each shows only the top `crop_h` rows of
    the raw shot; the middle card is drawn last (fully visible)."""
    W, H = size
    im = bg.copy().convert('RGBA') if bg else Image.new('RGBA', size, (0, 0, 0, 0))
    n = len(THEME_ORDER)
    order = sorted(range(n), key=lambda i: -abs(i - n // 2))     # outer cards first
    card_h = round(card_w * crop_h / 1080)
    for i in order:
        angle = (i - n // 2) * step
        raw = Image.open(os.path.join(RAW, lang, f'theme_{THEME_ORDER[i]}.png')).convert('RGB')
        card = rounded(raw.crop((0, 0, 1080, crop_h)).resize((card_w, card_h), Image.LANCZOS), card_w // 14)
        edge = Image.new('RGBA', card.size, (0, 0, 0, 0))                # thin light rim
        ImageDraw.Draw(edge).rounded_rectangle([0, 0, card_w - 1, card_h - 1], card_w // 14,
                                               outline=(255, 255, 255, 60), width=3)
        card = Image.alpha_composite(card, edge)
        pad = 60                                                         # room for the shadow
        sheet = Image.new('RGBA', (card_w + 2 * pad, card_h + 2 * pad), (0, 0, 0, 0))
        shadow = Image.new('RGBA', sheet.size, (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle([pad - 4, pad + 10, pad + card_w + 4, pad + card_h + 10],
                                                 card_w // 14, fill=(0, 0, 0, 150))
        sheet = Image.alpha_composite(sheet, shadow.filter(ImageFilter.GaussianBlur(16)))
        sheet.alpha_composite(card, (pad, pad))
        rot = sheet.rotate(-angle, resample=Image.BICUBIC, expand=True)
        a = math.radians(angle)
        # the card's bottom-centre sits on the arc around the pivot
        cx = W / 2 + radius * math.sin(a)
        cy = pivot_y - radius * math.cos(a) - card_h / 2 + card_h / 2
        im.alpha_composite(rot, (round(cx - rot.width / 2), round(cy - rot.height / 2)))
    return im


def themes_shot(lang):
    im = gradient(1080, 1920).convert('RGBA')
    d = ImageDraw.Draw(im)
    caption = next(de if lang == 'de' else en for n, de, en in SHOTS if n == 'themes')
    d.text((540, 150), caption, font=font(64, 'Bold'), fill='white', anchor='mm')
    morse(d, 540 - 157, 225, '-.-. .--', (94, 214, 214))
    return fan(lang, (1080, 1920), 640, 1900, 760, 8, 1700, bg=im).convert('RGB')


def themes_site(lang):
    out = fan(lang, (1500, 640), 420, 1900, 520, 8, 915)
    out.save(os.path.join(SITE, f'{lang}_themes.webp'), quality=84, method=6)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    Image.open(ICON).convert('RGB').resize((512, 512), Image.LANCZOS).save(
        os.path.join(OUT, 'icon_512.png'), optimize=True)
    for lang in FEATURE:
        feature(lang).save(os.path.join(OUT, f'feature_{lang}.png'), optimize=True)
    for i, (name, de, en) in enumerate(SHOTS, 1):
        for lang, cap in (('de', de), ('en', en)):
            (themes_shot(lang) if name == 'themes' else shot(lang, name, cap)).save(os.path.join(OUT, f'shot_{lang}_{i}_{name}.png'), optimize=True)
    for lang in FEATURE:
        themes_site(lang)
    print('written to', os.path.relpath(OUT))
