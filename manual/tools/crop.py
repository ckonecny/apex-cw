#!/usr/bin/env python3
# crop.py in.png out.png [y0 y1]  -> strips status/gesture bar (or a y band), scales to 540 px wide
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
y0, y1 = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (140, im.height - 50)
im = im.crop((0, y0, im.width, y1))
w = 540
im.resize((w, round(im.height * w / im.width)), Image.LANCZOS).save(sys.argv[2], optimize=True)
