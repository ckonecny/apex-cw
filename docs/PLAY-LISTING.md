# Google Play listing — texts and console answers

Source for what goes into the Play Console. Keep in sync with the app and
the manual (facts from the code, like everything else). Limits: title 30,
short description 80, full description 4000 characters.

## App details

- **App name:** Next CW Trainer
- **Default language:** Deutsch (de-DE); translation: English (en-US)
- **App or game:** App · **Category:** Education · **Free**
- **Contact e-mail:** oe1ckoapps@gmail.com
- **Website:** https://github.com/ckonecny/next_cw_trainer
- **Privacy policy URL:**
  https://github.com/ckonecny/next_cw_trainer/blob/main/PRIVACY.md

## Short description

- **DE:** Morsen lernen: Koch-Methode, Hör- und Gebetraining, Keyer, Decoder, Spiele
- **EN:** Learn Morse code: Koch method, copy & send training, keyer, decoder, games

## Full description — DE

```
Next CW Trainer bringt die Trainingsmodi des Morserino-32 aufs Android-Handy: Morsen (CW) hören, geben und üben – unterwegs, ohne zusätzliche Hardware.

HÖREN
• Zufallszeichen, Gruppen, häufige Wörter, Abkürzungen, Rufzeichen, gemischte Inhalte
• Koch-Methode mit den Reihenfolgen M32, LCWO, CW Academy, LICW oder einer eigenen
• Blockweise mitschreiben, Fehler markieren, Auswertung mit Trend und schwachen Zeichen
• Adaptive Vorschläge: nächstes Koch-Zeichen, Farnsworth-Abstände, Tempo – du entscheidest

GEBEN
• Echo-Trainer wie am Morserino: Wort hören, zurückgeben, sofortige Bewertung
• Eigenes Profil fürs Geben, Verwechslungspaare, Gebe-Tempo

FREI MORSEN
• CW-Keyer: Iambic A/B, Ultimatic, Non-Squeeze, Handtaste, mit Live-Dekodierung
• CW-Decoder über das Mikrofon
• WiFi Trx: CW übers Internet mit dem Morserino-Protokoll (z. B. cq.morserino.info)
• QSO-Bot: simulierter Funkpartner für SOTA/POTA-, Standard- und Contest-QSOs

SPIELE
• Morse Invaders, Morsel (Wörter raten), Memory Chain
• Die Textadventures Zork I–III, komplett in CW gespielt

AUSSERDEM
• Touch-Paddles am Bildschirm oder echte Taste/Paddle über einen Adapter
• Latenzarmer Mithörton, Ausgabe über Lautsprecher, Kopfhörer oder Bluetooth
• Deutsch und Englisch, Statistik pro Zeichen, ausführliches Handbuch

Keine Werbung, keine Konten, keine Datensammlung. Freie Software (GPL-3.0), Quellcode auf GitHub.

Die Trainingslogik stammt aus der Firmware des Morserino-32 von Willi Kraml, OE1WKL. Dies ist ein unabhängiges Projekt und nicht mit dem Morserino-32-Team verbunden. Zork ist eine Marke ihrer Inhaber; die App steht mit ihnen in keiner Verbindung.
```

## Full description — EN

```
Next CW Trainer brings the training modes of the Morserino-32 to your Android phone: copy, send and practise Morse code (CW) on the go, with no extra hardware.

LISTEN
• Random characters, groups, common words, abbreviations, call signs, mixed content
• Koch method with M32, LCWO, CW Academy, LICW or your own sequence
• Copy in blocks, mark your misses, results with trend and weak characters
• Adaptive suggestions: next Koch character, Farnsworth spacing, speed – you decide

SEND
• Echo Trainer like on the Morserino: hear a word, key it back, instant grading
• Separate sending profile, confusion pairs, answer speed cap

FREE KEYING
• CW keyer: Iambic A/B, Ultimatic, Non-Squeeze, straight key, with live decoding
• CW decoder using the microphone
• WiFi Trx: CW over the internet with the Morserino protocol (e.g. cq.morserino.info)
• QSO Bot: a simulated partner for SOTA/POTA, standard and contest QSOs

GAMES
• Morse Invaders, Morsel (word guessing), Memory Chain
• The text adventures Zork I–III, played entirely in CW

ALSO
• On-screen touch paddles, or a real key/paddle via an adapter
• Low-latency sidetone through speaker, headphones or Bluetooth
• German and English, per-character statistics, detailed manual

No ads, no accounts, no data collection. Free software (GPL-3.0), source code on GitHub.

The training logic comes from the Morserino-32 firmware by Willi Kraml, OE1WKL. This is an independent project, not affiliated with the Morserino-32 team. Zork is a trademark of its owners; this app is not affiliated with them.
```

## Graphics

- App icon 512×512 PNG (from `android/tool/icon/`)
- Feature graphic 1024×500 PNG/JPG
- Phone screenshots: 2–8 per language, from `manual/img/{de,en}/`

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
**Content rating (IARC):** Reference/education utility; no violence, sex,
language, drugs, gambling; users can interact online: **Yes** (WiFi Trx
exchanges Morse text with other users on public servers); no sharing of
location; no purchases. (Zork contains mild fantasy combat in text.)
**Target audience:** 18+ (not designed for children).
**News app:** No. **Government app:** No. **Financial features:** None.
**Health:** No.
