# Google Play listing — texts and console answers

Source for what goes into the Play Console. Positioning (user decision
2026-09-28): a CW trainer in its own right, not "the Morserino-32 on your
phone" — the Morserino-32 is credited in the text, not used as the pitch. Keep in sync with the app and
the manual (facts from the code, like everything else). Limits: title 30,
short description 80, full description 4000 characters.

## App details

- **App name:** APEX CW
- **Package name:** at.oe1cko.nextcwtrainer (permanent)
- **Default language:** English (en-US) — the fallback for every device
  language without a translation; translation: Deutsch (de-DE)
- **App or game:** App · **Category:** Education · **Free**
- **Contact e-mail:** oe1ckoapps@gmail.com
- **Website:** https://ckonecny.github.io/apex-cw/ (landing page,
  `site/`; source code stays at https://github.com/ckonecny/apex-cw)
- **Privacy policy URL:**
  https://github.com/ckonecny/apex-cw/blob/main/PRIVACY.md

## Short description

- **DE:** Morsen lernen: Koch-Methode, Hören, Geben, Prüfungssimulation, Keyer, Spiele
- **EN:** Learn Morse code: Koch method, copy, send, exam simulation, keyer, games

## Full description — DE

```
APEX CW ist ein umfassender Morse-Trainer (CW) fürs Android-Handy: hören, geben und üben – unterwegs, ohne zusätzliche Hardware.

HÖREN
• Zufallszeichen, Gruppen, häufige Wörter, Abkürzungen, Rufzeichen, gemischte Inhalte
• Koch-Methode mit den Reihenfolgen M32, LCWO, CW Academy, LICW oder einer eigenen
• Blockweise mitschreiben, Fehler markieren, Auswertung mit Trend und schwachen Zeichen
• Adaptive Vorschläge: nächstes Koch-Zeichen, Farnsworth-Abstände, Tempo, Pausenhinweis – du entscheidest

GEBEN
• Echo-Trainer: Wort hören, zurückgeben, sofortige Bewertung
• Eigenes Profil fürs Geben, Verwechslungspaare, Gebe-Tempo

PRÜFUNGSSIMULATION
• Die freiwillige Morseprüfung üben: Österreich, Deutschland, UK, Neuseeland, Indien, USA oder ein eigenes Profil
• Aufnehmen und Geben wie in der Prüfung: festes Tempo, Zeitlimit, Fehlergrenze, bestanden oder nicht
• Verlauf deiner Versuche – die Werte stammen aus öffentlichen Quellen und ersetzen nicht die offizielle Prüfung

VERSTEHEN OHNE MITSCHREIBEN
• Sätze, Q-Gruppen und Mini-QSOs hören und Fragen dazu beantworten
• Zwei Stationen mit zwei Tonhöhen, wie auf dem Band

FREI MORSEN
• CW-Keyer: Iambic A/B, Ultimatic, Non-Squeeze, Handtaste, mit Live-Dekodierung
• CW-Decoder über das Mikrofon
• WiFi Trx: CW übers Internet mit anderen Funkamateuren (MOPP-Server)
• QSO-Bot: simulierter Funkpartner für SOTA/POTA-, Standard- und Contest-QSOs

SPIELE
• Morse Invaders, Morsel, Memory Chain, Trailblazer, Fox Hunt, Fight the Pileup, Radio Cave
• Die Textadventures Zork I–III, komplett in CW gespielt

DRAN BLEIBEN
• Tagesziel und Serie, Statistik pro Zeichen, Verlaufskurven für Trefferquote, Tempo und Übungszeit

AUSSERDEM
• Touch-Keyer am Bildschirm oder echte Morsetaste über einen Adapter
• Latenzarmer Mithörton, Ausgabe über Lautsprecher, Kopfhörer oder Bluetooth
• Deutsch und Englisch, ausführliches Handbuch

Keine Werbung, keine Konten, keine Datensammlung. Freie Software (GPL-3.0), Quellcode auf GitHub.

Viele Ideen und ein Großteil der Trainingslogik stammen aus der Open-Source-Firmware des Morserino-32 von Willi Kraml, OE1WKL – herzlichen Dank dafür. APEX CW ist ein unabhängiges Projekt und steht in keiner Verbindung zum Morserino-32-Team. Zork ist eine Marke ihrer Inhaber; die App steht mit ihnen in keiner Verbindung.
```

## Full description — EN

```
APEX CW is a comprehensive Morse code (CW) trainer for your Android phone: copy, send and practise on the go, with no extra hardware.

LISTEN
• Random characters, groups, common words, abbreviations, call signs, mixed content
• Koch method with M32, LCWO, CW Academy, LICW or your own sequence
• Copy in blocks, mark your misses, results with trend and weak characters
• Adaptive suggestions: next Koch character, Farnsworth spacing, speed, break hint – you decide

SEND
• Echo Trainer: hear a word, key it back, instant grading
• Separate sending profile, confusion pairs, answer speed cap

EXAM SIMULATION
• Rehearse the voluntary Morse exam: Austria, Germany, UK, New Zealand, India, USA or your own profile
• Receive and send as in the exam: fixed speed, time limit, error limit, pass or fail
• History of your runs – values come from public sources and do not replace the official exam

HEAD COPY, NO WRITING
• Hear sentences, Q-groups and mini QSOs and answer questions about them
• Two stations at two pitches, like on the band

FREE KEYING
• CW keyer: Iambic A/B, Ultimatic, Non-Squeeze, straight key, with live decoding
• CW decoder using the microphone
• WiFi Trx: CW over the internet with other hams (MOPP servers)
• QSO Bot: a simulated partner for SOTA/POTA, standard and contest QSOs

GAMES
• Morse Invaders, Morsel, Memory Chain, Trailblazer, Fox Hunt, Fight the Pileup, Radio Cave
• The text adventures Zork I–III, played entirely in CW

STAY ON TRACK
• Daily goal and streak, per-character statistics, progress charts for hit rate, speed and practice time

ALSO
• On-screen touch keyer, or a real Morse key via an adapter
• Low-latency sidetone through speaker, headphones or Bluetooth
• German and English, detailed manual

No ads, no accounts, no data collection. Free software (GPL-3.0), source code on GitHub.

Many ideas and much of the training logic come from the open-source Morserino-32 firmware by Willi Kraml, OE1WKL – many thanks for that. APEX CW is an independent project, not affiliated with the Morserino-32 team. Zork is a trademark of its owners; this app is not affiliated with them.
```

## Graphics

All built by `python3 store/make_graphics.py` into `store/out/`:
- `icon_512.png` — app icon 512×512 (full-bleed; Play masks it)
- `feature_{de,en}.png` — feature graphic 1024×500
- `shot_{de,en}_N_<name>.png` — 8 phone screenshots per language, 1080×1920,
  captioned, upload in order N (home, listen, statistics, head copy, exam
  simulation, send, QSO Bot, games). Raw shots in `store/raw/{de,en}/` (dark
  theme, test phone, 2026-10-08, beta 1.6.1); retake when those screens change.

## Console answers

**Data safety**
- Collects or shares user data: **No** (nothing leaves the device to the
  developer or third parties; audio is processed on-device only; WiFi Trx
  sends user-typed Morse to a server the user chose — user-initiated
  transfer to a service of the user's choice, not developer collection).
- Data encrypted in transit: not applicable (no collection).
- Deletion request: not applicable (no account, no collected data).

**App access:** all functions available without login.
**Ads:** No.
**Content rating (IARC):** questionnaire category "All other app types"
(not Game, not Social/communication); no violence, sex,
language, drugs, gambling; users can interact online: **Yes** (WiFi Trx
exchanges Morse text with other users on public servers); no sharing of
location; no purchases. (Zork contains mild fantasy combat in text.)
**Target audience:** 18+ (not designed for children).
**News app:** No. **Government app:** No. **Financial features:** None.
**Health:** No.
