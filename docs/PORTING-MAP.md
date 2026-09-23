# Porting Map

Original = `reference/Software/src/Version 6 and newer/` (submodule, tag
`V9.0`). Android Kotlin/C++ files are bare names below, relative to
`android/android/app/src/main/{kotlin/at/oe1cko/nextcwtrainer,cpp}/`;
Dart files are given relative to `android/` (e.g. `lib/...`).

| Original module | Android module | Status |
|---|---|---|
| `m32_v6.ino` generateCW()/fetchNewWord() | `CwGenerator.kt` | Done |
| `m32_v6.ino` doPaddleIambic() (keyer state machine, CurtisB, ACS) | `CwKeyer.kt` | Done |
| `m32_v6.ino` echoTrainerEval() | `lib/ui/echo_trainer_screen.dart` | Done |
| `MorseDecoder.cpp` (CWtree decode) | `lib/keyer/morse_decoder.dart` | Done (pattern-table lookup, not the literal tree) |
| `MorsePreferences.cpp` Koch class / prefs | `lib/content/cw_content.dart`, `lib/ui/settings_screen.dart` | Done, except Koch prosign-tail extension |
| `callsign_prefixes.h` / getRandomCall() | `CallsignData.kt` | Done |
| `english_words.h`, `abbrev.h` | `CwGenerator.kt` (word/abbrev lists) | Done |
| `MorseOutput.cpp` sidetone + envelope | `cw_tone_jni.cpp` (AAudio) | Done (pitch, softness, shift) |
| `cleanUpProSigns()`/`encodeProSigns()` | inline in generator/echo screens + `morseTable` | Done (display only, two-char mnemonic convention, see DECISIONS.md) |
| `MorsePreferences.cpp` NVS persistence | `SharedPreferences` | Done (equivalent, different storage) |
| `MorseTextEntry.cpp` (on-device char picker) | Flutter native text fields | N/A — superseded by touch keyboard |
| Display layer (`DisplayWrapper`, `M32OledLGFX`) | Flutter widgets | N/A — superseded |
| `MorseWiFi.cpp` / cwForTx() (WiFi Trx UDP protocol) | `lib/net/mopp.dart`, `lib/net/mopp_client.dart`, `lib/ui/wifi_trx_screen.dart` | First version: single server/peer, send + receive, in foreground only. Not yet tested against a real server. ESP-NOW/LoRa: N/A |
| `MorseQsoBot.cpp`, `MorseQsoBotMatch.h`, `qso_content.h` | — | Not started |
| `goertzel.cpp` (mic CW decode) | — | Not started |
| File Player / multi-part file builder | — | Not started |
| CW Memories (config tool) | — | Not started |
| Snapshots (doWriteSnapshot/doReadSnapshot) | — | Not started |
| Practice Stats (`CONFIG_PRACTICE_STATS`) | — | Not started (no tracking layer exists yet) |
| Games (`MorseGame`, `MorsePileup`, `MorseRadioCave`, `MorseMorsel`) | — | N/A — out of scope |
| Grid games (`MorseGridScore`, Trailblazer/Fox Hunt) | — | N/A — out of scope |
| LoRa (RadioLib) | — | N/A — no hardware |
| Bluetooth (`MorseBluetooth.cpp`) | — | N/A — Android handles BT/HID natively |
| Accessibility voice clips (`CONFIG_AUDIO_A11Y`) | — | N/A — not evaluated |
| — (no firmware equivalent) | `lib/l10n/strings.dart` | Done — app-only DE/EN switch |
| — (no firmware equivalent) | `lib/theme/*`, `lib/ui/widgets/pinch_zoom_text.dart` | Done — app-only theme/text-size |

## Dead code (not wired up, safe to delete)
`android/lib/audio/tone_synth.dart`, `android/lib/input/paddle_input.dart`,
`android/lib/keyer/iambic_keyer.dart` — early pure-Dart prototype, superseded
by the native Kotlin/C++ engine, unimported.
