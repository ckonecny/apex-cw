#!/bin/bash
# bot.sh <theme> <lang> <out>
cd "$(dirname "$0")"; O=raw/$3
./setp.sh $1 $2
./u tap '^(Freie Modi|Free modes)' tap '^QSO Bot' tap '^Start$'
for i in $(seq 1 12); do
  ./u dump > bot.txt
  CALL=$(grep -oE "cq cq de [a-z0-9/]+ [a-z0-9/]+ k" bot.txt | head -1 | awk "{print \$4}")
  [ -n "$CALL" ] && break
done
echo call=$CALL
./u tapxy 400 2010 text "$CALL de oe1cko oe1cko k" tapxy 975 1136 back wait 45 shot $O/qso.png dump | grep -E "RX|TX"
