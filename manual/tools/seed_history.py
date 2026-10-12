#!/usr/bin/env python3
"""seed_history.py <prefs.xml>: pads the statistics in a copy of the phone's
FlutterSharedPreferences.xml with ~10 earlier weeks (copies of the existing
days shifted back by 7*k days, scaled and with slightly higher error rates),
so progress, heatmap and detail screenshots show 12 weeks. Only for
screenshots: push the result with run-as on a debug build, restore the
original afterwards (see README, "Keep the user's data clean")."""
import re, html, json, random, datetime, sys
random.seed(7)
path = sys.argv[1]
x = open(path).read()
def getj(k):
    m=re.search(r'(name="flutter\.%s"[^>]*>)(.*?)(</string>)'%re.escape(k),x,re.S)
    return m, json.loads(html.unescape(m.group(2)))
def put(k,obj):
    global x
    m,_=getj(k)
    x=x[:m.start(2)]+html.escape(json.dumps(obj,separators=(',',':')),quote=False)+x[m.end(2):]
D=datetime.date.fromisoformat
def shift(d,k): return (D(d)-datetime.timedelta(days=7*k)).isoformat()
for key in ['charStats.hear.days','charStats.echo.days']:
    try: m,days=getj(key)
    except Exception: continue
    new=dict(days)
    for d,v in days.items():
        for k in range(1,11):
            nd=shift(d,k)
            if nd in new or random.random()<0.45: continue
            f=random.uniform(0.4,0.9); w=1+0.25*k/10
            nv={kk:vv for kk,vv in v.items() if kk!='c'}
            for a in ('a','e','ws'):
                if a in nv: nv[a]=max(1,round(nv[a]*f)) if a!='e' else max(1,round(nv[a]*f*w))
            nv['c']={}
            for ch,(a,e) in v.get('c',{}).items():
                a2=max(1,round(a*f)); e2=min(a2,round(e*w+random.random()*a2*0.06*k/10))
                nv['c'][ch]=[a2,e2]
            new[nd]=nv
    put(key,new)
m,pd=getj('practice.days'); new=dict(pd)
for d,v in pd.items():
    for k in range(1,11):
        nd=shift(d,k)
        if nd in new or random.random()<0.4: continue
        f=random.uniform(0.4,1.0); nv=dict(v)
        for a in ('s','n'): nv[a]=max(1,round(nv[a]*f))
        new[nd]=nv
put('practice.days',new)
open(path, 'w').write(x)
print('seeded')
