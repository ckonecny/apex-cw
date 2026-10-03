# Porting Map

Original = `reference/Software/src/Version 6 and newer/` (submodule, tag
`V9.0`). Android Kotlin/C++ files are bare names below, relative to
`android/android/app/src/main/{kotlin/at/oe1cko/nextcwtrainer,cpp}/`;
Dart files are given relative to `android/` (e.g. `lib/...`).

| Original module | Android module | Status |
|---|---|---|
| `m32_v6.ino` generateCW()/fetchNewWord() | `CwGenerator.kt` | Done |
| `m32_v6.ino` doPaddleIambic() (keyer state machine, CurtisB, ACS) | `CwKeyer.kt` | Done |
| `m32_v6.ino` echoTrainerEval() | `lib/ui/echo_trainer_screen.dart` | Done (Echo Speed Max as "Gebe-Tempo"; Adaptive Speed differs, see DECISIONS) |
| `MorseDecoder.cpp` (CWtree decode) | `lib/keyer/morse_decoder.dart` | Done (pattern-table lookup, not the literal tree) |
| `MorsePreferences.cpp` Koch class / prefs | `lib/content/cw_content.dart`, `lib/ui/settings_screen.dart` | Done, except Koch prosign-tail extension |
| `callsign_prefixes.h` / getRandomCall() | `CallsignData.kt` | Done |
| `english_words.h`, `abbrev.h` | `CwGenerator.kt` (word/abbrev lists) | Done |
| `MorseOutput.cpp` sidetone + envelope | `cw_tone_jni.cpp` (AAudio) | Done (pitch, softness, shift) |
| `cleanUpProSigns()`/`encodeProSigns()` | inline in generator/echo screens + `morseTable` | Done (display only, two-char mnemonic convention, see DECISIONS.md) |
| `MorsePreferences.cpp` NVS persistence | `SharedPreferences` | Done (equivalent, different storage) |
| `MorseTextEntry.cpp` (on-device char picker) | Flutter native text fields | N/A — superseded by touch keyboard |
| Display layer (`DisplayWrapper`, `M32OledLGFX`) | Flutter widgets | N/A — superseded |
| `MorseWiFi.cpp` / cwForTx() (WiFi Trx UDP protocol) | `lib/net/mopp.dart`, `lib/net/mopp_client.dart`, `lib/ui/wifi_trx_screen.dart` | Single server/peer, send + receive, in foreground only (2026-09-25), user-tested OK. ESP-NOW/LoRa: N/A |
| `MorseMorsel.cpp` (Morsel, word guessing) | `lib/ui/morsel_screen.dart` (via `games_screen.dart`) | Ported, single player (2026-09-25), user-tested OK |
| `MorseMemoryChain.cpp` (Memory Chain) | `lib/ui/memory_chain_screen.dart` (via `games_screen.dart`) | Ported (2026-09-25), user-tested OK |
| `MorseGridEngine.cpp`, `MorseGridScore.cpp`, `MorseTrailblazer.cpp`, `MorseFoxHunt.cpp` (grid games) | `lib/content/grid_engine.dart`, `lib/content/grid_score.dart`, `lib/ui/maze_game_screen.dart` (via `games_screen.dart`) | Ported (2026-10-03, issue #13), single player; see DECISIONS.md |
| `MorseGame.cpp`, `MorseGameMode.cpp`, `GameSprite.cpp` (Morse Invaders) | `lib/ui/invaders_screen.dart` (via `games_screen.dart`), effects in `CwTonePlugin.kt` | Ported (2026-09-25), user-tested OK |
| `MorseRadioCave.cpp` (Radio Cave, text adventure) | `lib/content/radio_cave_engine.dart`, `lib/ui/radio_cave_screen.dart` (via `games_screen.dart`) | Ported, single player (2026-10-03) |
| `MorsePileup.cpp` (Fight the Pileup) | `lib/content/pileup_engine.dart`, `lib/ui/pileup_screen.dart` (via `games_screen.dart`) | Ported, single player (2026-10-03, issue #15), see DECISIONS.md |
| Multiplayer of all games (`MorseGridNet.cpp`, ESP-NOW parts of Morsel/Pileup) | — | N/A: ESP-NOW does not exist on a phone |
| `MorseQsoBot.cpp`, `MorseQsoBotMatch.h`, `qso_content.h` | `lib/content/qso_bot.dart`, `lib/ui/qso_bot_screen.dart`, call zones in `CallsignData.kt` | Ported (2026-09-25), user-tested OK |
| `goertzel.cpp` (mic CW decode) | `lib/keyer/cw_audio_decoder.dart`, `MicInput.kt`, `lib/ui/decoder_screen.dart` | Ported (2026-09-25), user-tested OK |
| File Player / multi-part file builder | `lib/owntexts/`, `lib/ui/own_texts_screen.dart`, `lib/ui/own_text_player_screen.dart` | Implemented (2026-10-01, issue #8), clipboard instead of file, see DECISIONS.md |
| Snapshots (doWriteSnapshot/doReadSnapshot) | — | Dropped (user decision 2026-10-01) |
| CW Memories (config tool) | — | Dropped (user decision 2026-10-01) |
| Practice Stats (`MorsePracticeStats.cpp`) | — | Will not be ported: the app has its own statistics (see DECISIONS.md) |
| LoRa (RadioLib) | — | N/A — no hardware |
| Bluetooth (`MorseBluetooth.cpp`) | — | N/A — Android handles BT/HID natively |
| Accessibility voice clips (`CONFIG_AUDIO_A11Y`) | — | N/A — not evaluated |

Open rows are tracked as GitHub issues (CLAUDE.md rule 12).

## Dead code
None known. The Dart prototype files (commit 85cfd8f) and unused handlers,
strings and prefs (2026-09-25) have been removed.
