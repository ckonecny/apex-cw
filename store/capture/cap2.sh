#!/bin/bash
# cap2.sh <theme> <lang> <out> : qso bot + mini-qso question
cd "$(dirname "$0")"; O=raw/$3
A=~/Library/Android/sdk/platform-tools/adb; D=${DEVICE:?set DEVICE to the adb serial}
./setp.sh $1 $2
./u tap '^(Verstehen|Head copy) \|' tap '^Mini.QSO' wait 1 dump | grep -iE "start|runde|round" 
./u tap '^(Runde starten|Start round|Start)' wait 40 dump | grep -iE "Frage|question|fragen|questions"
./u tap '^(Zu den Fragen|To the questions|Go to)' wait 3 dump >/dev/null
./u shot $O/miniqso.png back back back
./u tap '^(Freie Modi|Free modes)' tap '^QSO Bot' tap '^Start$' wait 12 dump > bot.txt
CALL=$(grep -oE "de [a-z0-9]+ " bot.txt | head -1 | cut -d' ' -f2)
echo call=$CALL
./u tapxy 400 2010 text "$CALL de oe1cko oe1cko k"
./u tapxy 975 1136 back wait 50 shot $O/qso.png dump | grep -E "RX|TX"
