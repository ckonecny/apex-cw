#!/bin/bash
# bot2.sh <lang> : QSO bot exchange via text field, then the settings sheet
cd "$(dirname "$0")"; L=$1; N=$([ $1 = 0 ] && echo de || echo en); O=out/$N
T="$(dirname "$0")/.."
S(){ ./u shot raw/tmp.png >/dev/null; python3 -I $T/crop.py raw/tmp.png $O/$1.png; }
./setm.sh 1 $L
./u tap '^(Freie Modi|Free modes)' tap '^QSO Bot' tap '^Start$'
for i in $(seq 1 15); do ./u dump > bot.txt; CALL=$(grep -oE "cq cq de [a-z0-9/]+ [a-z0-9/]+ k" bot.txt | head -1 | awk '{print $4}'); [ -n "$CALL" ] && break; done
echo call=$CALL
./u tapxy 400 2010 text "$CALL de oe1cko oe1cko k" tapxy 975 1136 back wait 45
S qso
./u tap '^(Stopp|Stop)$' wait 1 tap '^(Einstellungen|Settings)$' wait 2; S qso_sheet
