#!/bin/bash
# key.sh "<morse>" [gap_s]  e.g. ".-. ... / -.-."  ('.'=dit, '-'=dah, ' '=char gap, '/'=word gap)
GAP=${2:-0.12}
s=""
for ((i=0;i<${#1};i++)); do c=${1:i:1}
  case "$c" in .) s+="input keyevent 113; sleep ${DIT:-0.15}; ";; -) s+="input keyevent 114; sleep ${DAH:-0.40}; ";;
    " ") s+="sleep ${CG:-0.7}; ";; /) s+="sleep ${WG:-2}; ";; esac; done
"${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}" ${DEVICE:+-s $DEVICE} shell "$s"
