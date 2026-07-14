# Claude Code TTS — Changelog

Lightweight public summary. Full detail lives in `TTS_Changelog_Claude_Code.docx` in the source folder.

---

## Session 16 — July 14, 2026

- **Mac stop hotkey needs no permission now.** The macOS stop hotkey (Ctrl+Option+X) was rewritten from `pynput` to Carbon `RegisterEventHotKey`, which is not gated by Accessibility / Input Monitoring, so there is no first-use permission prompt. The leftover Automator "Stop TTS" service was removed and `pynput` dropped from the Mac dependencies.
- **Fixed the Mac hotkey failing to start.** On macOS 11+, `ctypes.util.find_library("Carbon")` returns `None` (system frameworks live in the dyld shared cache), so the daemon crashed before registering. It now loads Carbon by absolute path and logs any startup error to `~/.claude/tts_hotkey.log`.
- **Replay the last answer.** New global hotkey — Ctrl+Alt+R (Windows) / Ctrl+Option+R (macOS) — re-speaks the last reply. The server stores the last text and handles a new `__REPLAY__` command.
- **Audio follows your output device.** The server refreshes the audio device before each utterance, so switching output (e.g. connecting AirPods or headphones) is picked up without restarting the server.
- **Clearer install docs.** The README manual-install steps now include the full `git clone` + `cd` sequence (with a ZIP fallback), and the Controls list documents stop, replay, speed, voice change, and voice previews.
- **Mac installer BOM removed.** The macOS installer no longer begins with a UTF-8 byte-order mark, which had broken `./install_claude_tts_Mac_v3.0.sh` (the BOM hid the `#!/bin/bash` shebang). It now runs directly as documented.

---

## Session 15 — June 30, 2026

- **Friendly voice preview helper.** Installers now write bundled `tts_preview.py` beside the Kokoro server. Claude Code instructions route explicit requests such as `quick preview voices`, `preview all voices`, and `preview voice onyx` through the helper. It supports short voice aliases, strict command matching, and `--dry-run` tests; ordinary explanatory text does not trigger previews.
- **Ctrl+Alt+X stop hotkey now installed (was advertised but disabled).** The Windows installer
  installs a standalone `tts_hotkey.py` daemon (`RegisterHotKey`, no low-level keyboard hook) and
  the Mac installer a `pynput` launchd agent (Ctrl+Option+X) — both auto-start at login and are
  single-instance, sending `__STOP__` to the shared Kokoro server. macOS needs Accessibility
  permission (the installer prints how); `pynput` added to the Mac dependency install. Uninstaller
  removes the hotkey daemon and its startup entry.

---

## Session 14 — June 29, 2026

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

## Session 13 — June 29, 2026

- **Robust Python launcher (Windows)** — the installer now launches Python through the Windows `py -3` launcher instead of bare `python` for the package install, the Kokoro server start, the auto-start VBS, and the generated helper-command docs. `py -3` is PATH-order independent and version-aware, so on machines with more than one Python install the server always starts under Python 3.x. Process detection (`Get-Process python`) is unchanged. **Mac is unaffected** — its installer already resolves `python3` once and reuses it.

---

## Session 12 — June 2026

- **Default speed 1.1 → 1.2** — all installers now ship with `SPEED = 1.2`; existing installs unaffected (change live with `set_speed.py`)

---

## Session 11 — June 2026

- **`tts_hook.ps1` connect timeout (Windows)** — replaced blocking `TcpClient.Connect()` with `BeginConnect` + 2-second `AsyncWaitHandle.WaitOne` timeout. If Kokoro enters a zombie state (port open but unresponsive), the old call could freeze Claude Code for up to 120 seconds; the fix bounds the worst case to 2 seconds. Mac hook unaffected — already uses `s.settimeout(2)`.

---

## Session 1–10 — April 2026 (v3.0)

- **Double-speaking fix** — Claude no longer writes regular responses to `tts_queue.txt`; queue is now reserved for special commands only (`__PREVIEW_*`)
- **CLAUDE.md simplified** — cut from 43 to 20 lines; removed duplicate voice list, consolidated controls into a single block; added "never change voice" rule
- Installers renamed to `v3.0`; Mac installer gains hook note that was missing in v2.0

---

## v2.0 — April 2026

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

## v1.0 — April 2026

- **Kokoro ONNX** installed locally — fully offline, no API keys
- **Persistent TCP server** (`tts_server.py`) on port 59001 — loads model once, listens continuously
- **Claude Code Stop hook** — fires after every reply, sends text to server
- **Toggle on/off** — `tts_enabled.txt`; tell Claude "turn voice on/off"
- **Auto-start at login** — Windows Startup VBS; macOS launchd plist
- One-shot installers for Windows and Mac


