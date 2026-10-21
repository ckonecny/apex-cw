#!/bin/bash
# cap.sh <theme> <lang 0|1> <outdir> : home, hear, stats, qrm, streak, exam, examcustom, send, games, zork, verstehen
cd "$(dirname "$0")"; T=$1; L=$2; O=raw/$3; mkdir -p $O
A=~/Library/Android/sdk/platform-tools/adb; D=${DEVICE:?set DEVICE to the adb serial}
./setp.sh $T $L
./u shot $O/home.png
./u tap '^(Hören|Listen) \|' shot $O/hear.png
./u tap '^(Statistik Hören|Statistics: listening)' wait 1 shot $O/hear_stats.png back
$A -s $D shell input swipe 765 226 765 226 900; sleep 1.5; ./u tapxy 903 426 wait 1 shot $O/qrm.png back back
./u tap '^(Verstehen|Head copy) \|' shot $O/verstehen.png back
./u tap '^(Geben|Send) \|' tap '^(Koch-Lektion|Koch lesson)' shot $O/send.png back
./u tap '^(Spiele|Games) \|' shot $O/games.png tap '^(Text-Adventure|Text adventure)' shot $O/zork.png back back
./u tap '^(Lernressourcen|Learning resources)' tap '^(Prüfungssimulation|Exam simulation)' wait 1 shot $O/exam.png tap '^(Eigenes Profil|Custom)' wait 1 shot $O/examcustom.png back back
./u tap '^[0-9]+ \|' wait 3 shot $O/streak.png back
