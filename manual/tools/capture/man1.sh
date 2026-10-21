#!/bin/bash
# man1.sh <lang 0|1> : static screens
cd "$(dirname "$0")"; L=$1; N=$([ $1 = 0 ] && echo de || echo en); O=out/$N; mkdir -p $O raw
S(){ ./u shot raw/$N_$1.png >/dev/null; python3 -I "$(dirname "$0")/../crop.py" raw/$N_$1.png $O/$1.png; }
./setm.sh 1 $L
./u wait 3 dump >/dev/null; S home
./u tap '^(Freie Modi|Free modes)' wait 1; S freemodes; ./u back
./u tap '^(Spiele|Games) \|' wait 1; S games; ./u back
./u tap '^(Lernressourcen|Learning resources)' wait 1; S res_hub
./u tap '^(Zeichentabelle|Character chart)' wait 1; S chart; ./u back
./u tap '^Links' wait 1; S links; ./u back back
./u tap '^[0-9]+ \|' wait 4 dump >/dev/null; S achievements; ./u tapxy 1017 226 wait 1; S achievements_settings; ./u back back
./u tapxy 1017 226 wait 1; S settings1
for i in 2 3 4 5; do ./u swipe 540 1900 540 400 500; S settings$i; done
