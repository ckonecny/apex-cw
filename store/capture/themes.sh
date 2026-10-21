#!/bin/bash
# themes.sh <lang> : home screen in themes 1..7 (needs a while for the goal ring to settle)
cd "$(dirname "$0")"; L=$1; O=raw/themes_$L; mkdir -p $O
for T in 1 2 3 4 5 6 7; do
  ./setp.sh $T $L
  ./u wait 3 dump >/dev/null; ./u shot $O/t$T.png
done
