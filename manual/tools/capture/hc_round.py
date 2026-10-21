import subprocess,re,sys,time,os
# hc_round.py <lang> <mode regex> <prefix>
lang,mode,prefix=sys.argv[1:4]
N='de' if lang=='0' else 'en'
env=dict(os.environ)  # DEVICE must be set
T=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..')
def u(*a):
    return subprocess.run(['./u',*a],capture_output=True,text=True,env=env).stdout
def nodes():
    out=[]
    for l in u('dump').splitlines():
        m=re.match(r'\[(\d+), (\d+), (\d+), (\d+)\]  (.*)',l)
        if m: out.append((list(map(int,m.groups()[:4])),m.group(5)))
    return out
def shot(name):
    u('shot','raw/tmp.png'); subprocess.run(['python3','-I',T+'/crop.py','raw/tmp.png',f'out/{N}/{name}.png'])
subprocess.run(['./setm.sh','1',lang],env=env)
u('tap','^(Verstehen|Head copy) \\|','wait','1','tap',mode,'wait','1')
u('tap','^(Runde starten|Start round)','wait','4')
shot(prefix+'_listen')
for i in range(40):
    if any(re.search('Zu den Fragen|To the questions',l) for b,l in nodes()): break
    time.sleep(3)
u('tap','^(Zu den Fragen|To the questions)','wait','2')
first=True
for i in range(20):
    n=nodes(); labs=[l for b,l in n]
    nxt=[b for b,l in n if re.fullmatch(r'(Weiter|Next|Continue|Ergebnis|Result|See result|Zur Auswertung|Auswertung|Results?|Evaluation|Score|Finish|Done)',l.strip())]
    if nxt:
        b=nxt[0]; u('tapxy',str((b[0]+b[2])//2),str((b[1]+b[3])//2),'wait','2'); continue
    if any(re.search(r'(Frage|Question) \d+ (von|of)',l) for l in labs):
        if first: shot(prefix+'_question'); first=False
        opts=[b for b,l in n if b[0]==42 and 130<b[3]-b[1]<165 and b[1]>560]
        if not opts: break
        b=opts[0]; u('tapxy',str((b[0]+b[2])//2),str((b[1]+b[3])//2),'wait','2')
    else:
        break
time.sleep(2); shot(prefix+'_result')
print('done',prefix)
