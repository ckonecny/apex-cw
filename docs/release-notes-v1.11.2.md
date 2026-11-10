# APEX CW v1.11.2

Exact timing of the generated Morse, and a word gap that matches what is played.

## Fixed
- **Sample-accurate keying.** Dits, dahs and all gaps of generated Morse (Listen, Send, Audio trainer, QSO Bot, chart, Morsel, own texts) are now exact over Bluetooth headsets and the speaker. Before, every tone edge snapped to an audio block, so lengths wobbled by 10–30 ms over Bluetooth (reported with measurements by OE3RLV, thank you).
- In the Listen block flow the pause between groups is counted in samples as well, instead of being about 14 ms too long.
- **Word spacing:** the firmware plays the larger of the word spacing and character spacing + 4 dits, so a setting of 6 always sounded like 7. The generator spacing controls (−/+ rows, ⚙ sliders, training goals) now start at character spacing + 4, and raising the character spacing raises the word spacing with it. eff. WPM counts the played gap, like the firmware. CW Keyer, WiFi Trx and QSO Bot keep 6–105: there the value is the decoder's pause before a space.
- Adventure: stored word spacing below the played minimum is lifted to it, like in the other screens.

## Known
- If the audio output stops delivering, playback now continues silently and too slowly instead of at the right pace (Stop still works); not seen on a phone.
- Not checked on a phone: WiFi Trx playback.

## Under the hood
- F-Droid preparation (fastlane metadata, optional Gradle properties `appId` / `appLabel`; the Play app id and label stay the defaults). No change for this app's signature, package or permissions.
- Android Gradle Plugin 9.5.1, CodeQL action update.
