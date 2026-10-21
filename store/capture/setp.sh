#!/bin/bash
# setp.sh <theme 0-7> <lang 0|1>  : edit prefs, restart app
A=~/Library/Android/sdk/platform-tools/adb; D=${DEVICE:?set DEVICE to the adb serial}; P=at.oe1cko.nextcwtrainer
B=${BACKUP:?set BACKUP to a folder holding prefs.orig.xml}
$A -s $D shell am force-stop $P
python3 -I - "$1" "$2" <<PY
import re,sys
s=open('$B/prefs.orig.xml').read()
def setv(s,k,v):
    pat=r'<long name="flutter\.%s" value="\d+" />'%k
    new='<long name="flutter.%s" value="%s" />'%(k,v)
    return re.sub(pat,new,s) if re.search(pat,s) else s.replace('<map>','<map>\n    '+new,1)
s=setv(s,'themeMode',sys.argv[1]); s=setv(s,'uiLang',sys.argv[2])

def setb(s,k,v):
    return re.sub(r'<boolean name="flutter\.%s" value="\w+" />'%k,'<boolean name="flutter.%s" value="%s" />'%(k,v),s)
for k in('blueLightOn','hideStatusBar','compactTop'): s=setb(s,k,'false')
if '2026-10-21' not in s:
    s=s.replace('{&quot;2026-10-03&quot;','{&quot;2026-10-21&quot;:{&quot;s&quot;:840,&quot;n&quot;:9,&quot;l&quot;:3},&quot;2026-10-03&quot;',1)

if '1792562400000' not in s:
    s=s.replace('name="flutter.practice.sessions">[','name="flutter.practice.sessions">[{&quot;t&quot;:1792562400000,&quot;d&quot;:420,&quot;m&quot;:&quot;hear&quot;,&quot;e&quot;:1792562820000},{&quot;t&quot;:1792564200000,&quot;d&quot;:420,&quot;m&quot;:&quot;hear&quot;,&quot;e&quot;:1792564620000},',1)
open('$B/prefs.cur.xml','w').write(s)
PY
$A -s $D shell "run-as $P sh -c 'cat > shared_prefs/FlutterSharedPreferences.xml'" < $B/prefs.cur.xml
$A -s $D shell am start -n $P/.MainActivity >/dev/null; sleep 4
