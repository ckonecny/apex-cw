#!/usr/bin/env python3
"""ui.py dump | tap <regex> [n] | tapxy x y | shot <path> | back | swipe x1 y1 x2 y2 ms | text <s> | wait s"""
import re, subprocess, sys, time
import os
ADB = [os.path.expanduser(os.environ.get('ADB', '~/Library/Android/sdk/platform-tools/adb'))] + (['-s', os.environ['DEVICE']] if os.environ.get('DEVICE') else [])
def sh(*a, **k): return subprocess.run(ADB + list(a), capture_output=True, **k)
def nodes():
    sh('shell', 'uiautomator', 'dump', '/sdcard/ui.xml')
    x = sh('shell', 'cat', '/sdcard/ui.xml').stdout.decode()
    out = []
    for m in re.finditer(r'<node [^>]*>', x):
        n = m.group(0)
        d = (re.search(r'content-desc="([^"]*)"', n) or re.search('()', '')).group(1)
        t = (re.search(r' text="([^"]*)"', n) or re.search('()', '')).group(1)
        bm = re.search(r'bounds="([^"]*)"', n)
        if not bm: continue
        b = list(map(int, re.findall(r'\d+', bm.group(1))))
        lab = (d or t).replace('&#10;', ' | ')
        if lab: out.append((lab, b))
    return out
args = sys.argv[1:]
while args:
    c = args.pop(0)
    if c == 'dump':
        for l, b in nodes(): print(f'{b}  {l[:90]}')
    elif c == 'tap':
        rx = args.pop(0); idx = int(args.pop(0)) if args and args[0].isdigit() else 0
        m = [(l, b) for l, b in nodes() if re.search(rx, l)]
        if len(m) <= idx: print('NOT FOUND', rx); sys.exit(1)
        l, b = m[idx]; sh('shell', 'input', 'tap', str((b[0]+b[2])//2), str((b[1]+b[3])//2)); print('tap', l[:40]); time.sleep(1.0)
    elif c == 'tapxy':
        x, y = args.pop(0), args.pop(0); sh('shell', 'input', 'tap', x, y); time.sleep(1.0)
    elif c == 'swipe':
        a = [args.pop(0) for _ in range(5)]; sh('shell', 'input', 'swipe', *a); time.sleep(0.8)
    elif c == 'back':
        sh('shell', 'input', 'keyevent', '4'); time.sleep(1.0)
    elif c == 'text':
        sh('shell', 'input', 'text', args.pop(0).replace(' ', '%s'))
    elif c == 'wait':
        time.sleep(float(args.pop(0)))
    elif c == 'shot':
        p = args.pop(0); open(p, 'wb').write(sh('exec-out', 'screencap', '-p').stdout); print('shot', p)
