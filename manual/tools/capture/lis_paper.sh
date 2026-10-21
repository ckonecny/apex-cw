#!/bin/bash
# lis_paper.sh <lang>: Listen paper block screens (random guesses for marks)
cd "$(dirname "$0")"; ; L=$1; N=$([ $1 = 0 ] && echo de || echo en); O=out/$N; mkdir -p $O raw
T="$(dirname "$0")/.."
S(){ ./u shot raw/tmp.png >/dev/null; python3 -I $T/crop.py raw/tmp.png $O/$1.png; }
./setm.sh 1 $L
./u tap '^(Hören|Listen) \|' wait 1 tap '^(PAPIER|PAPER)' wait 2
for i in $(seq 1 30); do d=$(./u dump); echo "$d" | grep -qE "(Gruppe|Group) (5 von|5 of) 5|5 of 5|5 von 5" && break; sleep 2; done
S hear_sending
for i in $(seq 1 30); do d=$(./u dump); echo "$d" | grep -qE "(Fertig|Done|Finish) ·" && break; sleep 2; done
./u tapxy 317 1100 wait 1 tapxy 540 1323 wait 1; S hear_mark; ./u tap '^(Zurück|Back)$' wait 1
./u tapxy 317 1323 wait 1 tapxy 713 1323 wait 1 tap '^(Zurück|Back)$' wait 1
S hear_revealed
./u tap '^(Fertig|Done|Finish)' wait 3; S hear_result_tmp
./u tapxy 271 1504 wait 1; S hear_weak
