# Word lists (assets/words/)

`android/assets/words/en.txt` and `de.txt` ("word weight" per line, most
frequent first) are derived from the FrequencyWords project
(https://github.com/hermitdave/FrequencyWords, content CC-BY-SA-4.0, built
from OpenSubtitles 2018). They are NOT taken from the Morserino-32 firmware
(its list is based on the Oxford 5000, whose licence is unclear).

Filters: letters a-z only (German: no umlauts / ß), no names, interjections,
subtitle artifacts, nothing about violence, crime, drugs, sex or swearing;
English is US spelling. English: 3500 words, length 2-10. German: 2500 words,
length 2-12.

Rebuild (macOS; sandbox paths are placeholders): download
`content/2018/{en,de}/{en,de}_50k.txt` into `fw/`, then
`python3 -I build_en.py 3500` / `python3 -I build_de.py`. English uses
`/usr/share/dict/web2` and `propernames` as filters; German pipes the
candidates through `spellcheck_de.swift` (compiled with `swiftc`) into
`de_spell.txt` first. The blocklists in the scripts were curated by hand.
