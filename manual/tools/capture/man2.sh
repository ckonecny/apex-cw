#!/bin/bash
# man2.sh <lang> : Listen/Send start + statistics
cd "$(dirname "$0")"; L=$1; N=$([ $1 = 0 ] && echo de || echo en); O=out/$N; mkdir -p $O raw
S(){ ./u shot raw/tmp.png >/dev/null; python3 -I "$(dirname "$0")/../crop.py" raw/tmp.png $O/$1.png; }
./setm.sh 1 $L
for M in hear echo; do
  if [ $M = hear ]; then ./u tap '^(Hören|Listen) \|'; ST='^(Statistik Hören|Statistics: listening)'; else ./u tap '^(Geben|Send) \|' tap '^(Koch-Lektion|Koch lesson)'; ST='^(Statistik Geben|Statistics: sending)'; fi
  ./u wait 2 dump >/dev/null; S ${M}_start
  ./u tap "$ST" wait 2; S ${M}_stats
  ./u tap '^(Verlauf|Progress)' wait 2; S ${M}_progress
  ./u swipe 540 1900 540 600 600; S ${M}_progress_b
  ./u swipe 540 1900 540 600 600; S ${M}_progress_c
  ./u swipe 540 600 540 2000 300 swipe 540 600 540 2000 300 swipe 540 600 540 2000 300
  ./u tap '^Trends' wait 2; S ${M}_trends
  ./u tap '^(Zeichen|Characters)$' wait 2
  ./u tapxy 300 1500 wait 2; S ${M}_char_detail
  ./u back back back
done
