# Claude Code TTS — Changelog

Lightweight public summary. Full detail lives in `TTS_Changelog_Claude_Code.docx` in the source folder.

---

## Shared server v2.5

**Improved speech**

- **Speed survives a restart too.** The chosen speed is saved to `speed.txt` beside the
  server (mirroring voice memory in `voice.txt`) and reloaded on start, so it no longer
  resets to the default after a reboot.
- **Abbreviations are finally spoken.** `e.g.`, `i.e.`, `vs.`, `etc.`, `approx.` were never
  expanded — their patterns ended in a word boundary that cannot match before a space, so the
  rules existed but never fired. They now read "for example", "that is", "versus",
  "etcetera", "approximately".
- **Money reads naturally in more shapes.** `$3.5` reads "3 dollars and 50 cents" (the
  ".5" used to be left dangling after "3 dollars"), `$0.99` reads "99 cents", `$1.5 million`
  and `$1.5M` read "1 point 5 million dollars" (scale words thousand/million/billion/trillion
  plus attached suffixes k/M/B), and odd precision like `$12.345` falls back to
  "12 point 345 dollars". `$3.50` and `$1,234.56` read exactly as before.
- **More emoji and symbols stripped.** The star/symbol and arrow blocks (U+2B00-2BFF,
  U+2190-21FF — e.g. star and left-right-arrow glyphs) no longer reach the voice.

**Cleanup**

- **Dead fallback removed.** The Claude Code and Cowork installers wrote `tts_speak.py` and
  set an unused `$ttsScript`/`TTS_SCRIPT` variable pointing at it; nothing ever invoked
  either. Both are gone. The persistent server remains the only audio path, unchanged.
  Existing installs keep an inert `tts_speak.py` on disk; it is harmless.

All six embedded servers and the three `src/` copies remain byte-identical (v2.5).

---

## Shared server v2.4

**Fixed**

- **Mid-reply silence.** Long sentences became single oversized chunks (200+ chars); when
  one followed a short chunk, playback caught up with synthesis and speech stalled for a
  couple of seconds. Sentences now split at clause breaks (commas, semicolons) into chunks
  of at most ~120 characters, and fragments under ~40 merge with a neighbour. Synthesis on
  CPU runs about 4x realtime, so with uniform chunks the synthesizer always finishes the
  next chunk before the current one ends. Measured on a real reply: zero gaps.
- **Speech starts sooner.** A short opening sentence is no longer glued onto a following
  long one, so the first chunk stays small. Measured time-to-first-audio on a typical
  reply: 1.5s, down from 3.6s.

Chunking only: the control protocol, stop/replay hotkeys, queue, and audio path are
untouched. All six embedded servers and the three `src/` copies remain byte-identical
(v2.4).

---

## Shared server v2.3

**New**

- **Your voice now survives a restart.** The chosen voice is saved to `voice.txt` next to the
  server and reloaded on start, so it no longer resets to the default after a reboot or a
  server restart.
- **Version numbers and bare domains are read properly.** `3.11` is spoken "3 point 11",
  `2.3.1` as "2 point 3 point 1", and `claude.ai` as "claude dot ai" (known TLDs only).
  Money is unaffected — `$3.50` still reads "3 dollars and 50 cents". The pronunciation rule
  is deliberately ordered **after** the money rule: a ` point ` substitution applied first
  eats the decimal and produces "3 dollars point 50". That ordering is load-bearing and is
  pinned by a comment in `clean_text()`; do not move it above the money rule.

**Fixed / consolidated**

- **All installers now ship one identical Kokoro server.** Every installer writes the *same*
  file (`~/.claude/kokoro/tts_server.py`, port 59001), but the six embedded copies had drifted
  (six copies ranging from 170 to 192 lines), so **install order silently decided which server
  you ended up with** — installing a second product could silently replace a newer server with
  an older, smaller one (the Codex Mac copy, for example, lacked emoji stripping). All six are now
  byte-identical to a single canonical **v2.3**, so any install order gives the same result.
- **Version header corrected.** The embedded servers advertised `v2.0` / `v2.1` in their
  docstring while actually shipping replay, output-device follow and the money/decimal fixes.
  The header now matches the code and is stamped v2.3.
- **`src/` resynced (was stale).** The published `src/tts_server.py`, `src/tts_hotkey.py` and
  `src/tts_hotkey_mac.py` still held older code: no `__REPLAY__`, a stop-only `Ctrl+Alt+X`
  hotkey daemon, and the previous `pynput` Mac hotkey. The installers shipped the replay
  hotkey while the published source folder did not contain it. `src/` now matches byte-for-byte
  what the installers write.
- **Claude Code Mac reached parity.** Its embedded server was missing voice memory (so the
  chosen voice was lost on restart) and the version/domain pronunciation block. Both added.
- **Cowork gained emoji stripping.** Its server lacked the emoji strip the other products had,
  so emoji could be read aloud. Added to the Windows and Mac servers.
- **Note — `tts_speak.py` is vestigial.** The installers still write it and still set
  `$ttsScript` / `TTS_SCRIPT` to it, but nothing invokes it: the variable is assigned once and
  never used. The "exactly one audio path" guarantee holds. The dead file and variable are
  safe to remove in a later pass.

**Known issue (not fixed here)**

- **Occasional silence mid-reply.** Synthesis and playback already overlap (a producer thread
  synthesizes ahead of the playback loop), so this is *not* a serialization problem. Two real
  causes remain: playback calls `sd.play()`/`sd.wait()` per chunk, which opens and closes an
  output stream for every chunk; and there is no buffer-ahead, so playback starts the instant
  chunk 1 is ready and any slower chunk becomes an audible gap. The synthesis queue is also
  unbounded. Being addressed separately — it touches stop-hotkey semantics and interacts with
  `_refresh_audio_device()`, so it is deliberately not bundled with this release.

---

## v3.6

- **Mac stop hotkey needs no permission now.** The macOS stop hotkey (Ctrl+Option+X) was rewritten from `pynput` to Carbon `RegisterEventHotKey`, which is not gated by Accessibility / Input Monitoring, so there is no first-use permission prompt. The leftover Automator "Stop TTS" service was removed and `pynput` dropped from the Mac dependencies.
- **Fixed the Mac hotkey failing to start.** On macOS 11+, `ctypes.util.find_library("Carbon")` returns `None` (system frameworks live in the dyld shared cache), so the daemon crashed before registering. It now loads Carbon by absolute path and logs any startup error to `~/.claude/tts_hotkey.log`.
- **Replay the last answer.** New global hotkey — Ctrl+Alt+R (Windows) / Ctrl+Option+R (macOS) — re-speaks the last reply. The server stores the last text and handles a new `__REPLAY__` command.
- **Audio follows your output device.** The server refreshes the audio device before each utterance, so switching output (e.g. connecting AirPods or headphones) is picked up without restarting the server.
- **Clearer install docs.** The README manual-install steps now include the full `git clone` + `cd` sequence (with a ZIP fallback), and the Controls list documents stop, replay, speed, voice change, and voice previews.
- **Mac installer BOM removed.** The macOS installer no longer begins with a UTF-8 byte-order mark, which had broken `./install_claude_tts_Mac_v3.0.sh` (the BOM hid the `#!/bin/bash` shebang). It now runs directly as documented.
- **Overlapping / looping speech eliminated structurally (reported from a Mac session).** Root cause: two things could produce audio — the persistent server (which serialises requests and honours stop) and a one-off fallback that did neither — so when the Stop hook misjudged a busy server as dead, it started a second, independent, **unstoppable** voice. The hook now has **exactly one audio path**: it sends to the single server and, if the server is busy or still booting (~10s), **waits and retries for up to ~60s** rather than ever synthesising directly. Worst case is a short delay; overlapping or uncancellable audio is now structurally impossible.
- **Audio-device follow made non-fragile.** The output-device refresh no longer tears down and re-initialises PortAudio before every utterance (which caused macOS `PaMacCore -50` errors); it only re-scans after an idle gap, so it still follows AirPods/headphone switches without thrashing the audio backend mid-burst.
- **Voice preview: fixed samples playing in the wrong voice.** The preview announced each voice by mutating a shared global (`__VOICE:name__`) and sent the sample as a separate message — but synthesis runs on a background thread, so a fast preview could synthesise a sample *after* the next voice-switch had overwritten the global, playing it in the wrong voice (mismatched label/gender). Each sample now carries its own voice atomically via the per-request `VOICE=name|text` prefix, correct regardless of timing.
- **Install no longer blocked by Homebrew Python (PEP 668).** On macOS with Homebrew's Python, a global `pip install` is refused (externally-managed environment), which aborted setup at the package step. The installer now retries with `--break-system-packages` when it hits this, so it completes.
- **Money and large numbers now read correctly.** The `$` cleaner only handled a single digit and the thousands-comma strip only removed one comma per number, so `$50` was spoken "5 dollars zero" and `1,000,000` became "one thousand, zero zero zero". Both now parse the whole value: `$50` → "50 dollars", `$3.50` → "3 dollars and 50 cents", `1,000,000` → "1000000", `$1,234.56` → "1234 dollars and 56 cents". Plain decimals (`3.14`) and percentages were already correct and are unaffected.

---

## v3.5

- **Friendly voice preview helper.** Installers now write bundled `tts_preview.py` beside the Kokoro server. Claude Code instructions route explicit requests such as `quick preview voices`, `preview all voices`, and `preview voice onyx` through the helper. It supports short voice aliases, strict command matching, and `--dry-run` tests; ordinary explanatory text does not trigger previews.
- **Ctrl+Alt+X stop hotkey now installed (was advertised but disabled).** The Windows installer
  installs a standalone `tts_hotkey.py` daemon (`RegisterHotKey`, no low-level keyboard hook) and
  the Mac installer a `pynput` launchd agent (Ctrl+Option+X) — both auto-start at login and are
  single-instance, sending `__STOP__` to the shared Kokoro server. macOS needs Accessibility
  permission (the installer prints how); `pynput` added to the Mac dependency install. Uninstaller
  removes the hotkey daemon and its startup entry.

---

## v3.4

- **Replay-bug audit (no code change).** A field-name bug was found and fixed in the Claude Cowork
  TTS watcher (its 3-minute age filter read a non-existent `ts` field instead of the ISO-8601
  `timestamp` field, so it never ran and old replies could be replayed). Claude Code TTS was checked
  for the same class of problem and is **not susceptible**: it has no file-tailing watcher. The Stop
  hook (`tts_hook.ps1`) receives `last_assistant_message` directly from the Claude Code Stop event and
  speaks it once, so there is no transcript to re-read and nothing to replay. No age filter is needed
  and no change was made.
- **Shared Kokoro server → v2.1.** The single local server (`tts_server.py` on port 59001) that the
  Stop hook speaks through was bumped v2.0 → v2.1 to support an optional per-request `VOICE=name|text`
  prefix (used by Cowork's `WATCHER_VOICE`). This is additive and backward-compatible: the Stop hook
  sends plain text with no prefix, so Claude Code TTS playback is unchanged.

---

## v3.3

- **Robust Python launcher (Windows)** — the installer now launches Python through the Windows `py -3` launcher instead of bare `python` for the package install, the Kokoro server start, the auto-start VBS, and the generated helper-command docs. `py -3` is PATH-order independent and version-aware, so on machines with more than one Python install the server always starts under Python 3.x. Process detection (`Get-Process python`) is unchanged. **Mac is unaffected** — its installer already resolves `python3` once and reuses it.

---

## v3.2

- **Default speed 1.1 → 1.2** — all installers now ship with `SPEED = 1.2`; existing installs unaffected (change live with `set_speed.py`)

---

## v3.1

- **`tts_hook.ps1` connect timeout (Windows)** — replaced blocking `TcpClient.Connect()` with `BeginConnect` + 2-second `AsyncWaitHandle.WaitOne` timeout. If Kokoro enters a zombie state (port open but unresponsive), the old call could freeze Claude Code for up to 120 seconds; the fix bounds the worst case to 2 seconds. Mac hook unaffected — already uses `s.settimeout(2)`.

---

## v3.0

- **Double-speaking fix** — Claude no longer writes regular responses to `tts_queue.txt`; queue is now reserved for special commands only (`__PREVIEW_*`)
- **CLAUDE.md simplified** — cut from 43 to 20 lines; removed duplicate voice list, consolidated controls into a single block; added "never change voice" rule
- Installers renamed to `v3.0`; Mac installer gains hook note that was missing in v2.0

---

## v2.0

- **Pipelined synthesis** — sentence-by-sentence: first word heard within ~0.5 s of reply finishing
- **`sounddevice` replaces PowerShell audio** — plays from memory in Python; no subprocess, no disk I/O, ~300 ms overhead eliminated per sentence
- **Speed control** — `set_speed.py --up / --down` steps by 0.2x; tell Claude "speak faster/slower"
- **Table and code-block skipping** — markdown tables replaced with "attached table"; fenced code blocks silently removed
- **Text cleaning** — arrows removed, dashes → comma, URLs → "link", abbreviations expanded, emoji stripped, `$` / `%` / `x` suffix expanded
- **Voice switching on the fly** — `__VOICE:name__` TCP command; `set_voice.py` helper; 27 voices
- **Voice preview system** — `preview_voices.py`; say "preview voices" for quick (~30 s) or full (~3 min) preview
- **Watchdog** — auto-restarts server within 3 s of a crash
- **Status and uninstall scripts** — `status_tts.ps1/.sh`, `uninstall_tts.ps1/.sh`
- **Ctrl+Alt+X instant stop** — Windows: in-process `WH_KEYBOARD_LL` hook inside server (~50 ms); Mac: Automator service
- **Audio device pre-warm** — silent sample at startup eliminates first-sentence latency spike
- UTF-8 encoding fix for Windows hook (em dash and Unicode now pass correctly)

---

## v1.0

- **Kokoro ONNX** installed locally — fully offline, no API keys
- **Persistent TCP server** (`tts_server.py`) on port 59001 — loads model once, listens continuously
- **Claude Code Stop hook** — fires after every reply, sends text to server
- **Toggle on/off** — `tts_enabled.txt`; tell Claude "turn voice on/off"
- **Auto-start at login** — Windows Startup VBS; macOS launchd plist
- One-shot installers for Windows and Mac


