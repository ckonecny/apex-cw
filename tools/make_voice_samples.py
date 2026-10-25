#!/usr/bin/env python3
"""Generates the spelling-alphabet voice samples for the audio trainer (#139).

The samples are synthesised once, offline, with Piper and the voice
"en_US-ljspeech-high". That voice was trained from scratch on the LJ Speech
dataset, which is in the public domain (Piper MODEL_CARD: "License: public
domain"), so the generated audio is unencumbered and falls under the app's
licence, GPL-3.0-or-later (CLAUDE.md rule 11). Piper itself is only a build
tool and is not shipped. Other Piper voices were rejected: ryan and hfc_* are
CC BY-NC-SA, and joe/amy/libritts_r are fine-tuned from the lessac voice,
whose licence is not clear.

    python3 -m venv venv && venv/bin/pip install piper-tts
    venv/bin/python tools/make_voice_samples.py MODEL.onnx OUT_DIR [symbols|prosigns]

MODEL.onnx is en_US-kristin-medium.onnx or en_US-bryce-medium.onnx (the
.onnx.json must sit beside it); the voice name is taken from the file name.
With "symbols" only the punctuation words, with "prosigns" only the
prosign clips are written.
Writes one mono Ogg/Opus file per character to OUT_DIR, named
voice_<voice>_<char>.ogg, e.g. voice_kristin_a.ogg (a..z: ICAO words; 0..9:
digits), trimmed of silence and
loudness-normalised to the same level (-14 LUFS, true peak -1.5 dB; the app
plays them at 10-100 %, default 70 %). Needs ffmpeg.
"""
import os
import subprocess
import sys
import tempfile
import wave

from piper import PiperVoice, SynthesisConfig

# What is spoken for each character. Piper reads the text, so a few words are
# respelled where the plain ICAO spelling would be read wrongly (Oscar came out
# as "ossar", Papa as "pahpuh", Whiskey as "whisk"). Romeo and Sierra came out
# garbled ("robedo", "siderah") with the model's default randomness, so they
# use a lower noise setting (CALM); the wording that works differs per voice
# (VOICE_TEXT below).
WORDS = {
    "a": "Alfa", "b": "Bravo", "c": "Charlie", "d": "Delta", "e": "Echo",
    "f": "Foxtrot", "g": "Golf", "h": "Hotel", "i": "India", "j": "Juliett",
    "k": "Kilo", "l": "Lima", "m": "Mike", "n": "November", "o": "Oss-kah",
    "p": "Pa-pa", "q": "Quebec", "r": "Romeo", "s": "Sierra", "t": "Tango",
    "u": "Uniform", "v": "Victor", "w": "Wiss-key", "x": "X-ray",
    "y": "Yankee", "z": "Zulu",
    "0": "Zero", "1": "One", "2": "Two", "3": "Three", "4": "Four",
    "5": "Five", "6": "Six", "7": "Seven", "8": "Eight", "9": "Nine",
}


# Punctuation and operator characters of the Morse set, spoken as words. The
# file name carries the key, because a character cannot be part of an Android
# resource name: voice_<voice>_<key>.ogg.
SYMBOLS = {
    "period": ("Period", "."), "comma": ("Kom-uh", ","),
    "colon": ("Colon", ":"), "dash": ("Dash", "-"),
    "slash": ("Slash", "/"), "equals": ("Equals", "="),
    "question": ("Question mark", "?"), "at": ("At sign", "@"),
    "plus": ("Plus", "+"),
}


# Prosigns: the meaning, and the word "Pro sign" as a separate clip, so the app
# can play the word, a tone or nothing before the meaning (the user's choice).
# Keys are prosign_<mnemonic>, matching the app's two-letter prosign keys.
PROSIGNS = {
    "prosign_word": "Pro sign.",
    "prosign_as": "Stand by.",
    "prosign_ka": "Start of message.",
    "prosign_kn": "Go ahead, named station only.",
    "prosign_sk": "End of contact.",
    "prosign_ve": "Understood.",
    "prosign_bk": "Break.",
    # Added with the Prosign set (#156).
    "prosign_ar": "End of message.",
    "prosign_bt": "New paragraph.",
    "prosign_hh": "Error.",
    "prosign_sos": "Distress call.",
}


# Words that need less randomness in the model (noise_scale, noise_w_scale).
CALM = {"r", "s"}

# Per-voice text for the characters where the default wording sounded wrong
# with that voice. Spoken exactly as written (no full stop appended).
# Chosen by ear.
VOICE_TEXT = {
    "kristin": {"r": "Roh, mee, oh."},
    "bryce": {"r": "Roh-mee-oh", "s": "Si-erra"},
}


def encode(wav_path, out_path):
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
         "-af",
         # trim leading/trailing silence, then even out the loudness
         "silenceremove=start_periods=1:start_threshold=-45dB,"
         "areverse,silenceremove=start_periods=1:"
         "start_threshold=-45dB,areverse,"
         "loudnorm=I=-14:TP=-1.5:LRA=7",
         "-ac", "1", "-ar", "24000", "-c:a", "libopus", "-b:a", "24k",
         out_path],
        check=True)


def main():
    model, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    name = os.path.basename(model).split("-")[1]
    mode = sys.argv[3] if len(sys.argv) > 3 else "all"
    only_symbols = mode in ("symbols", "prosigns")
    texts = dict(WORDS)
    texts.update(VOICE_TEXT.get(name, {}))
    voice = PiperVoice.load(model)
    cfg = SynthesisConfig(length_scale=1.05)
    calm = SynthesisConfig(length_scale=1.05, noise_scale=0.3,
                           noise_w_scale=0.3)
    with tempfile.TemporaryDirectory() as tmp:
        for key, text in PROSIGNS.items() if mode in ("all", "prosigns") else []:
            wav_path = os.path.join(tmp, key + ".wav")
            with wave.open(wav_path, "wb") as w:
                voice.synthesize_wav(text, w, syn_config=cfg)
            encode(wav_path, os.path.join(out, "voice_%s_%s.ogg" % (name, key)))
        for key, (word, _) in (SYMBOLS.items() if mode != "prosigns" else []):
            wav_path = os.path.join(tmp, key + ".wav")
            with wave.open(wav_path, "wb") as w:
                voice.synthesize_wav(word + ".", w, syn_config=cfg)
            encode(wav_path, os.path.join(out, "voice_%s_%s.ogg" % (name, key)))
        for ch in ([] if only_symbols else WORDS):
            text = texts[ch] if ch in VOICE_TEXT.get(name, {}) \
                else WORDS[ch] + "."
            wav_path = os.path.join(tmp, ch + ".wav")
            with wave.open(wav_path, "wb") as w:
                voice.synthesize_wav(
                    text, w, syn_config=calm if ch in CALM else cfg)
            encode(wav_path, os.path.join(out, "voice_%s_%s.ogg" % (name, ch)))
    print("wrote to %s" % out)


if __name__ == "__main__":
    main()
