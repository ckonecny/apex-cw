#!/bin/bash
# lis_type.sh <lang>: Listen typing screens
cd "$(dirname "$0")"; ; L=$1; N=$([ $1 = 0 ] && echo de || echo en); O=out/$N; mkdir -p $O raw
T="$(dirname "$0")/.."
S(){ ./u shot raw/tmp.png >/dev/null; python3 -I $T/crop.py raw/tmp.png $O/$1.png; }
W(){ for i in $(seq 1 25); do d=$(./u dump); echo "$d" | grep -qE "$1" && ! echo "$d" | grep -qE "$2" && return; sleep 2; done; }
./setm.sh 1 $L
# retry mode: Repeat, 2 attempts
./u tap '^(Hören|Listen) \|' wait 1 tapxy 1017 226 wait 2
for i in 1 2 3 4; do ./u swipe 540 2000 540 700 600 wait 1; ./u dump | grep -qE "Versuche pro Wort|Attempts per word|per word" && break; done
./u tap '^(Wiederholen|Repeat)$' wait 1 tap '^2$' wait 1 back wait 1
./u tap '^(TIPPEN|TYPE)' wait 4
./u tap '^e$' tap '^s$' tap '^(⏎ Prüfen|⏎ Check)'; ./u wait 2; S hear_type_retry
W "(Versuch|Attempt) 2" "zzzz"
./u tap '^e$' tap '^s$'; ./u tap '^(⏎ Prüfen|⏎ Check)'
W "(Gruppe|Group) 2 (von|of) 5" "spielt|playing|Hör, wie|Listen to how|(Versuch|Attempt)"
./u tap '^t$' tap '^o$'; S hear_type
./u tap '^(⏎ Prüfen|⏎ Check)'
for i in $(seq 1 30); do d=$(./u dump); echo "$d" | grep -qE "(Fertig|Done|Finish) ·|Next block|Nächster" && break; if echo "$d" | grep -qE "(Prüfen|Check)" && echo "$d" | grep -qE "(Gruppe|Group) [0-9] (von|of) 5" && ! echo "$d" | grep -qE "spielt|playing"; then ./u tap '^e$' tap '^s$' tap '^(⏎ Prüfen|⏎ Check)' >/dev/null; fi; sleep 3; done
S hear_type_sent
