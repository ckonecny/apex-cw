# Inserts screenshot blocks after anchor paragraphs. Each entry: (de_anchor, en_anchor, [(img, de_caption, en_caption)])
P = [
("stellst du dagegen direkt in diesem Training ein.", "is set up\ndirectly inside that training.",
 [("home", "Die Startseite", "The home screen")]),
("Lektionen gibt es deshalb nur sehr wenige davon.", "very few of them.",
 [("hear_start", "Startansicht von Hören: Zeichenvorrat, Inhalt, Koch-Lektion, schwache Zeichen, Abstand und Tempo", "Listen start view: character set, content, Koch lesson, weak characters, spacing and speed")]),
("[Einzelzeichen üben](#einzelzeichen-üben)).", "[Practising a single character](#practising-a-single-character)).",
 [("char_sheet", "Ein Koch-Zeichen antippen", "Tapping a Koch character")]),
("Ergebnisse gespeichert und die Ergebnisseite erscheint.", "and the result page appears.",
 [("hear_sending", "Während des Blocks: nur Fortschritt, kein Text", "During the block: progress only, no text"),
  ("hear_revealed", "Aufgedeckt: Gruppen mit Fehlern sind rot", "Revealed: groups with errors are red"),
  ("hear_mark", "Eine Gruppe geöffnet: falsche Zeichen antippen", "One group opened: tap the wrong characters")]),
("keinen neuen Block.", "block.\n\nHow the app",
 [("hear_result", "Ergebnisseite mit Trefferquote, Abstand, schwachen Zeichen und Fortschrittsanzeige", "Result page with accuracy, spacing, weak characters and progress card"),
  ("hear_weak", "Ein schwaches Zeichen ausgenommen (durchgestrichen)", "A weak character excluded (struck through)")]),
("Werte in **fett** sind\ndie Voreinstellungen.", "Values in **bold** are\nthe defaults.",
 [("hear_sheet1", "⚙-Blatt: Koch Sequence und Practice Set", "⚙ sheet: Koch Sequence and Practice Set"),
  ("hear_sheet2", "⚙-Blatt: Abstände, Wortauswahl, Ablauf", "⚙ sheet: Spacing, Word selection, Flow")]),
("[Einstellungen des adaptiven Modus](#einstellungen-des-adaptiven-modus)\nbeschrieben.", "[Adaptive mode settings](#adaptive-mode-settings).",
 [("hear_sheet4", "⚙-Blatt: Adaptiver Modus", "⚙ sheet: Adaptive Mode")]),
("Unten liegen die Paddles bzw. die Taste und **Start**.", "At the bottom are the paddles or the key, and **Start**.",
 [("echo_start", "Startansicht von Geben", "Send start view"),
  ("echo_answer", "Während der Antwort: Vorgabe (Echo Prompt = Beides), Versuch und Tempo", "While answering: prompt (Echo Prompt = Both), attempt and speed")]),
("übernimmt die angehakten Vorschläge ohne Verstärkung und kehrt zur\nStartansicht zurück.", "suggestions without a boost and returns to the start view.",
 [("echo_result", "Ergebnisseite: Aufteilung, Verwechslungen, schwache Zeichen, erste Versuche", "Result page: breakdown, mix-ups, weak characters, first attempts"),
  ("echo_result2", "Ein Vorschlag (hier: Gebe-Tempo erhöhen), angehakt", "A suggestion (here: raise the answer speed), ticked")]),
("Geben zu kommen, etwa zum Einschleifen neuer Zeichen.", "for example to drill new characters.",
 [("echo_sheet", "⚙-Blatt von Geben: Abschnitt Echo Trainer", "Send ⚙ sheet: the Echo Trainer section")]),
("Das lässt\nsich nicht rückgängig machen.", "This cannot be undone.",
 [("hear_stats", "Statistik Hören: Versuche, Trefferquote, bereit", "Listen statistics: attempts, accuracy, ready"),
  ("echo_stats", "Statistik Geben mit häufigen Verwechslungen", "Send statistics with common mix-ups")]),
("tastest: CW Keyer, Geben, WiFi Trx, QSO Bot und Spiele.", "Send, WiFi Trx, QSO Bot and the games.",
 [("keyer", "CW Keyer mit dekodiertem Text", "CW Keyer with decoded text")]),
("aktuelle Dit- und Dah-Länge.", "dah length as it goes.",
 [("decoder", "CW-Decoder beim Zuhören, mit Pegelanzeige", "CW Decoder listening, with level meter"),
  ("decoder_sheet", "Einstellungen des Decoders", "Decoder settings")]),
("WiFi Trx funktioniert nur, solange die App im Vordergrund ist.", "WiFi Trx only works while the app is in the foreground.",
 [("wifi", "WiFi Trx mit Dienst, Log und Eingabefeld", "WiFi Trx with service, log and text field")]),
("Jede Verbindung läuft mit einem neuen, realistischen Rufzeichen des Bots.", "Each contact uses a new, realistic call sign for the bot.",
 [("qso", "Ein QSO mit dem Bot, Antwort per Texteingabe", "A QSO with the bot, answered with the text field")]),
("**Lange auf das Log drücken** leert\nes nach einer Rückfrage.", "**Long-press the log** to clear it after a\nconfirmation.",
 [("qso_sheet", "Einstellungen des QSO Bots", "QSO Bot settings")]),
("eine kurze Spielanleitung.", "short rules before you start.",
 [("games", "Die Spiele", "The games")]),
("sagt dir die App, welche Lektion nötig ist.", "app tells you which lesson you need.",
 [("morsel_lobby", "Morsel vor dem Start", "Morsel before the start")]),
("Highscores werden gespeichert.", "High scores are saved.",
 [("inv_lobby", "Morse Invaders vor dem Start", "Morse Invaders before the start"),
  ("inv_game", "Morse Invaders im Spiel", "Morse Invaders in play")]),
("Highscores werden je Modus gespeichert.", "High scores are saved per mode.",
 [("mc_lobby", "Memory Chain vor dem Start", "Memory Chain before the start")]),
("steht im ⚙-Blatt des jeweiligen Trainings.", "that training's ⚙ sheet.",
 [("settings1", "Einstellungen: Darstellung, Allgemein, Keyer", "Settings: Appearance, General, Keyer"),
  ("settings2", "Audioausgabe und Call Signs", "Audio output and Call Signs"),
  ("settings3", "vband Paddle, Key-Events, Info", "vband Paddle, key events, Info")]),
]
import re, os
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
for lang, ai in (('de', 0), ('en', 1)):
    f = f'manual_{lang}.md'; s = open(f).read()
    s = re.sub(r'\n\n::: \{\.shots[^}]*\}\n.*?\n:::', '', s, flags=re.S)   # idempotent
    for entry in P:
        anchor, imgs = entry[ai], entry[2]
        i = s.find(anchor); assert i >= 0, (lang, anchor)
        j = s.find('\n\n', i + len(anchor) - 1)
        if j < 0: j = len(s)
        cls = {1: 'shots one', 3: 'shots three'}.get(len(imgs), 'shots')
        block = f'\n\n::: {{.{cls.replace(" ", " .")}}}\n' + '\n\n'.join(
            f'![{c[1 + ai]}](img/{lang}/{c[0]}.png)' for c in imgs) + '\n:::'
        s = s[:j] + block + s[j:]
    open(f, 'w').write(s)
print('ok')
