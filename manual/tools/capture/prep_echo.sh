#!/bin/bash
# prep_echo.sh <lang>: Send start view, Koch 2, prompt Both
cd "$(dirname "$0")"; 
./setm.sh 1 $1
./u tap '^(Geben|Send) \|' wait 1 tapxy 1017 226 wait 2
for i in 1 2 3; do ./u swipe 540 2000 540 700 600 wait 1; ./u dump | grep -qE "Beides|Both" && break; done
./u tap '^(Beides|Both)$'; ./u back wait 1 tap '^(Koch-Lektion|Koch lesson)' tap '^(Zufall|Random)' wait 1
