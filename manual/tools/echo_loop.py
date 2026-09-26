#!/usr/bin/env python3
# Answers Echo Trainer words: word numbers in WRONG1 are keyed wrong on the first try,
# in WRONGALL always wrong. Stops at the result page. usage: echo_loop.py "2" "4" [shotprefix]
import re, subprocess, sys, time
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
D = sys.path[0]
M = {'e':'.','s':'...','t':'-','m':'--','a':'.-','n':'-.','i':'..','o':'---','k':'-.-','r':'.-.','u':'..-'}
wrong1 = {int(x) for x in sys.argv[1].split(',') if x}; wrongall = {int(x) for x in sys.argv[2].split(',') if x}
prefix = sys.argv[3] if len(sys.argv) > 3 else ''
exec(open(D + '/ui.py').read().split('args = sys.argv')[0])   # reuse nodes()
done = set(); shot_taken = False
t_end = time.time() + 300
while time.time() < t_end:
    n = nodes(); labs = [l for l, b in n]
    if any(re.search('Nächster Block|Next block', l) for l in labs): print('result'); break
    word = next((int(m.group(1)) for l in labs for m in [re.search(r'(?:Wort|Word) (\d+) /', l)] if m), 0)
    att = next((int(m.group(1)) for l in labs for m in [re.search(r'(?:Versuch|Attempt) (\d+)', l)] if m), 1)
    sending = any(re.search('Senden|Sending', l) for l in labs)
    tgt = next((l.strip() for l, b in n if 950 < b[1] < 1150 and re.fullmatch(r'\s*[a-z0-9]+\s*', l)), None)
    if sending and tgt and (word, att) not in done:
        done.add((word, att))
        ans = tgt
        if word in wrongall or (word in wrong1 and att == 1):
            ans = ''.join('s' if c == 'e' else 'e' for c in tgt)
        code = ' '.join(M[c] for c in ans) + ' /'
        print(word, att, tgt, '->', ans)
        subprocess.run([D + '/key.sh', code])
        if prefix and not shot_taken:
            time.sleep(0.2)
            open(prefix, 'wb').write(subprocess.run(ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)
            shot_taken = True
    time.sleep(0.3)
