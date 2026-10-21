#!/bin/bash
# echo_auto.sh <lang 0|1> : 100% Send block (suggestion), then a block with errors
cd "$(dirname "$0")"; L=$1; N=$([ $1 = 0 ] && echo de || echo en); O=out/$N; mkdir -p $O raw

T="$(dirname "$0")/.."
S(){ ./u shot raw/tmp.png >/dev/null; python3 -I $T/crop.py raw/tmp.png $O/$1.png; }
./setm.sh 1 $L
./u tap '^(Geben|Send) \|' wait 1 tapxy 1017 226 wait 2
for i in 1 2 3; do ./u swipe 540 2000 540 700 600 wait 1; ./u dump | grep -qE "Beides|Both" && break; done
./u tap '^(Beides|Both)$'; ./u back wait 1 tap '^(Koch-Lektion|Koch lesson)' tap '^(Zufall|Random)' wait 1
./u tap '^START$' 
python3 -I $T/echo_loop.py "" "" raw/ans.png | tail -8
python3 -I $T/crop.py raw/ans.png $O/echo_answer.png
./u wait 2; S echo_result2
./u tap '^(Nächster Block|Next block)' 
python3 -I $T/echo_loop.py "2" "4" | tail -8
./u wait 2; S echo_result
