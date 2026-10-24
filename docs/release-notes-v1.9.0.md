# APEX CW v1.9.0

A new way to practise without looking at the screen: the Audio trainer. Plus a
choice of confirmation sounds and a clearer heat map.

## New
- **Audio trainer (Free modes):** you hear a group of characters in Morse, think
  the characters, then hear them spelled out as words (Alfa, Bravo, ...). Eyes
  closed, no input. Own Koch level and character set (seeded once from Listen),
  word/abbreviation length, interference button, two voices, voice volume.
  Currently letters and digits only: punctuation and special characters are
  skipped, so groups can be shorter.
- **Audio trainer in the background:** keeps going with the screen off or in
  another app, with notification, lock-screen and headset/Bluetooth controls
  (play/pause, next = skip group, previous = repeat group).
- **Confirmation tone:** choose Classic, Marimba, Gentle or none in
  Settings > General; right and wrong now sound clearly different from the
  Morse tone (#136).
- **Heat map:** explains what a column is and is titled "Practised characters".

## Fixed
- **Crash on Stop in the background:** pausing on the lock screen, unlocking and
  tapping Stop could crash the app (Audio trainer and Own texts share the
  playback service). The service is now stopped in a way Android accepts.
- **Audio trainer view:** while it runs, the setup area is hidden and the
  running view looks like Listen; the solution no longer makes the tempo box jump.
