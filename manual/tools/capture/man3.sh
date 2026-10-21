#!/bin/bash
# man3.sh <lang> : sheets and setup screens
cd "$(dirname "$0")"; L=$1; N=$([ $1 = 0 ] && echo de || echo en); O=out/$N; mkdir -p $O raw
S(){ ./u shot raw/tmp.png >/dev/null; python3 -I "$(dirname "$0")/../crop.py" raw/tmp.png $O/$1.png; }
./setm.sh 1 $L
./u tap '^(Hören|Listen) \|' wait 1 tapxy 1017 226 wait 2; S hear_sheet_0
for i in 1 2 3 4 5; do ./u swipe 540 2000 540 700 600 wait 1; S hear_sheet_$i; done
./u back back
./u tap '^(Geben|Send) \|' wait 1 tapxy 1017 226 wait 2; S echo_sheet_0
for i in 1 2 3; do ./u swipe 540 2000 540 700 600 wait 1; S echo_sheet_$i; done
./u back back
./u tap '^(Verstehen|Head copy) \|' wait 1; S understand
./u tap '^(Sätze|Sentences)' wait 1; S headcopy_setup; ./u back
./u tap '^(Q-Gruppen|Q-groups)' wait 1; S qgroups_setup; ./u back
./u tap '^Mini.QSO' wait 1; S miniqso_setup; ./u back back
./u tap '^(Lernressourcen|Learning resources)' tap '^(Prüfungssimulation|Exam simulation)' wait 1; S exam_setup; ./u back back
