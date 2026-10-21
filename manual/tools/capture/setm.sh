#!/bin/bash
# setm.sh <theme> <lang>: seeded prefs, light theme etc., restart app
cd "$(dirname "$0")"
A=~/Library/Android/sdk/platform-tools/adb; D=$DEVICE; P=at.oe1cko.nextcwtrainer
$A -s $D shell am force-stop $P
python3 -I - "$1" "$2" <<PY
import re,sys
s=open('prefs.seed.xml').read()
def setv(s,k,v):
    pat=r'<long name="flutter\.%s" value="\d+" />'%k
    new='<long name="flutter.%s" value="%s" />'%(k,v)
    return re.sub(pat,new,s) if re.search(pat,s) else s.replace('<map>','<map>\n    '+new,1)
s=setv(s,'themeMode',sys.argv[1]); s=setv(s,'uiLang',sys.argv[2])
for k in ('hc.lang','qg.lang','mq.lang'): s=setv(s,k,sys.argv[2])
for k in('blueLightOn','hideStatusBar','compactTop'):
    s=re.sub(r'<boolean name="flutter\.%s" value="\w+" />'%k,'<boolean name="flutter.%s" value="false" />'%k,s)

s=s.replace('"2026-10-21":{"s":5,','"2026-10-21":{"s":840,',1)
s=s.replace('name="flutter.practice.sessions">[','name="flutter.practice.sessions">[{"t":1792562400000,"d":420,"m":"hear","e":1792562820000},{"t":1792564200000,"d":420,"m":"hear","e":1792564620000},',1)
open('prefs.cur.xml','w').write(s)
PY
$A -s $D shell "run-as $P sh -c 'cat > shared_prefs/FlutterSharedPreferences.xml'" < prefs.cur.xml
$A -s $D shell am start -n $P/.MainActivity >/dev/null; sleep 4
