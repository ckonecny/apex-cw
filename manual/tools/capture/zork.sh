#!/bin/bash
# zork.sh <lang>
cd "$(dirname "$0")"; L=$1; N=$([ $1 = 0 ] && echo de || echo en); O=out/$N; mkdir -p $O
T="$(dirname "$0")/.."
S(){ ./u shot raw/tmp.png >/dev/null; python3 -I $T/crop.py raw/tmp.png $O/$1.png; }
./setm.sh 1 $L
./u tap '^(Spiele|Games) \|' tap '^(Text-Adventure|Text adventure)' wait 1
./u tap '^(Weiter|Continue)' wait 10; S adv_game
./u tap '^(Befehle|Commands)' wait 2
for i in 1 2 3 4 5; do ./u swipe 540 2100 540 600 500; done; ./u wait 1; S adv_help; ./u back wait 1
./u tap '^(Karte|Map)' wait 2; S adv_map
./u tap '^(Ganze Karte|Whole map)' wait 2; S adv_map_warn
./u tap '^(Trotzdem zeigen|Show anyway|Show it anyway|Show regardless)' wait 3; S adv_map_whole; ./u back wait 1
./u tapxy 1017 226 wait 1 tapxy 838 257 wait 2
./u tapxy 1017 226 wait 1 tapxy 838 383 wait 2; S adv_saves
A=~/Library/Android/sdk/platform-tools/adb; $A -s $DEVICE shell input swipe 540 690 540 690 900; sleep 2; ./u tapxy 800 1285 wait 1; ./u tapxy 740 1314 wait 1; ./u back wait 1
./u tapxy 1017 226 wait 1 tapxy 838 677 wait 2; S adv_settings
./u swipe 540 1900 540 600 600 wait 1; S adv_settings2
