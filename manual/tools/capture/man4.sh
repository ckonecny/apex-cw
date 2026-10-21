#!/bin/bash
# man4.sh <lang> : free modes, own texts, game lobbies
cd "$(dirname "$0")"; L=$1; N=$([ $1 = 0 ] && echo de || echo en); O=out/$N; mkdir -p $O raw
S(){ ./u shot raw/tmp.png >/dev/null; python3 -I "$(dirname "$0")/../crop.py" raw/tmp.png $O/$1.png; }
./setm.sh 1 $L
./u tap '^(Freie Modi|Free modes)' wait 1
./u tap '^CW Keyer' wait 2; S keyer; ./u tap '^(Einstellungen|Settings)$' wait 2; S keyer_sheet; ./u back back
./u tap '^(CW-Decoder|CW Decoder)' wait 2; S decoder; ./u tapxy 1017 226 wait 2; S decoder_sheet; ./u back back
./u tap '^WiFi Trx' wait 2; S wifi; ./u back
./u tap '^(Eigene Texte|Own texts)' wait 2; S own_library; ./u back back
./u tap '^(Spiele|Games) \|' wait 1
./u tap "^(Text-Adventure|Text adventure)" wait 2; S adv_select; ./u back
for G in "Morse Invaders:inv_lobby" "Morsel:morsel_lobby" "Memory Chain:mc_lobby" "Trailblazer:tb_lobby"; do ./u tap "^${G%%:*}" wait 2; S ${G##*:}; ./u back; done
./u swipe 540 1900 540 600 500 wait 1
for G in "Fight the Pileup:pu_lobby" "Radio Cave:rc_lobby"; do ./u tap "^${G%%:*}" wait 2; S ${G##*:}; ./u back; done
./u back back
