<p align="center">
  <img src="assets/banner.png" alt="Omnicapable Voice for Claude Code, local offline text-to-speech" width="880"><br>
  <img src="assets/waveform.gif" alt="Voice waveform" width="480">
</p>

<div align="center">

# Omnicapable Voice for Claude Code

![Cost Free](https://img.shields.io/badge/Cost-Free-green) ![Runs 100% Offline](https://img.shields.io/badge/Runs-100%25%20Offline-green) ![Platform Windows macOS](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS-green) ![License MIT](https://img.shields.io/badge/License-MIT-green)

[Install](#install) · [How it works](#how-it-works) · [Controls](#controls) · [Troubleshooting](#troubleshooting)

</div>

Every time Claude Code finishes a response, it is spoken aloud automatically through a Stop hook. No API keys, no cloud, and nothing leaves your machine.

> **Part of Omnicapable:** Omnicapable bridges AI activity and human agency, making machine behavior easier to see, hear, follow, and steer. See also: [Claude Cowork](https://github.com/Omnicapable/claude-cowork-tts) · [Codex](https://github.com/Omnicapable/codex-tts).
>
> **Not affiliated.** An independent, open-source Omnicapable project, not affiliated with or endorsed by Anthropic. The Claude and Claude Code names are used only to indicate compatibility.

---

## What makes this different

This is not a generic text-to-speech add-on. It is built for coding agents:

- **Built into the agent, not bolted on.** It hooks directly into Claude through a Stop hook, so every reply is spoken automatically. No copy-paste, no reading your screen.

- **Tuned for agent output.** It reads the explanation unchanged and skips what doesn't belong in speech, like code blocks, tables, URLs, and emoji. You hear the point, not the syntax.

- **Local, private, and free.** Everything runs offline with the open Kokoro model. No API keys, no accounts, no cloud, no cost.

- **Shared engine across your agents.** Claude Code, Claude Cowork, and Codex install separately but share one local voice engine and controls, so each new one reuses what's already there and behaves the same.

- **Keeps you in the loop.** Hear what your agent is doing and guide it while your eyes are elsewhere. It runs in the background, so it never slows your agent down.

- **Yours to tune.** 27 voices and adjustable speed, with a per-tool voice so parallel agents sound distinct.

- **Smooth, natural delivery.** Speech starts in about a second and streams without mid-reply gaps, and money, percentages, versions, domains, and abbreviations are read the way a person would say them.

- **More accessible.** A comfortable way to work with AI for people with dyslexia, low vision, or screen fatigue.

---

## Install

Setup takes just a few clicks and configures everything for you automatically.

**➡️ Let your AI do it.**

Just paste this into Claude Code:

```
Clone https://github.com/Omnicapable/claude-code-tts and run the installer for my OS.
Run it to completion and show me the final summary. Tell me first if git or Python 3.9+ is missing.
```

It clones and installs everything for you.

---

**Prefer to do it yourself?**

**1. Get the files.** Open **Terminal** (macOS) or **PowerShell** (Windows) and run:
```
git clone https://github.com/Omnicapable/claude-code-tts
cd claude-code-tts
```
No `git`? On macOS, the first `git` command offers to install Apple's Command Line Tools; accept it. On Windows, install [Git for Windows](https://git-scm.com/download/win), or download the ZIP (green **Code** button → **Download ZIP**), unzip, and `cd` in.

**2. Run the installer for your OS** (from inside that folder):

**macOS:** in Terminal:
```
chmod +x Mac/install_claude_tts_Mac_v3.0.sh && ./Mac/install_claude_tts_Mac_v3.0.sh
```

**Windows:** in the `Windows` folder, right-click `install_claude_tts_Windows_v3.0.ps1` and choose *Run with PowerShell*.

The installer sets up everything for you automatically (one time, downloads ~336 MB of model files):
1. Installs Python packages (`kokoro-onnx`, `sounddevice`, `numpy`)
2. Downloads the Kokoro ONNX model and voices
3. Writes the TTS server and helper scripts to `%USERPROFILE%\.claude\kokoro\`
4. Adds a Stop hook to Claude Code's `settings.json`
5. Adds the TTS server to auto-start at login
6. Launches the server immediately

After install, every Claude Code response is spoken automatically.

<details>
<summary><b>Requirements</b></summary>

- Windows 10/11 or macOS 12+
- Python 3.9+
- Claude Code installed (`npm install -g @anthropic-ai/claude-code`)

</details>

---

## How it works

Both Claude setups feed the same local Voice Engine (Kokoro), differing only in how they capture a finished reply.

<p align="center">
  <img src="assets/how-it-works.png" alt="How Omnicapable Voice for Claude works" width="820">
</p>

### How they differ

| Feature | Claude Code | Claude Cowork |
| --- | --- | --- |
| How it detects a new reply | A listener fires the moment Claude finishes writing (Stop hook, every response). | A background watcher checks the transcript file every 0.1s (`tts_watcher.py`). |
| Where it reads the reply | Directly from Claude, passed in as the reply ends (`last_assistant_message` from hook stdin). | From the conversation file saved on disk (lines with `stop_reason=end_turn`). |
| If the Voice Engine is down | Retries with a 2s timeout, then skips that reply silently. Run `restart_tts.ps1` to recover. | Skips for 15s, then retries automatically (`KOKORO_RETRY_SECONDS = 15`). |
| Starts at login | Voice engine starts automatically. | Watcher and auto-restarter both start automatically. |
| Does Claude do anything | No, fully automatic. | No, fully automatic. |

<br>

Both share the same controls: 27 voices, adjustable speed (default 1.2x), voice previews, stop speech with Ctrl+Alt+X (Windows) / Ctrl+Option+X (macOS), and replay the last answer with Ctrl+Alt+R / Ctrl+Option+R.

---

## Controls

Ask Claude directly (*"turn voice off"*, *"speak faster"*, *"switch to voice sky"*), or run the scripts yourself.

| Action | Command |
| --- | --- |
| Change voice | `set_voice.py <voice>` |
| Change speed (0.5 to 2.5) | `set_speed.py --up` / `--down` / `1.5` |
| Turn on or off | `toggle_tts.ps1` |
| Stop, status, restart | `stop_tts.ps1` · `status_tts.ps1` · `restart_tts.ps1` |
| Stop current speech | `Ctrl+Alt+X` (Windows) / `Ctrl+Option+X` (macOS) |
| Replay last answer | `Ctrl+Alt+R` (Windows) / `Ctrl+Option+R` (macOS) |
| Preview voices | say *"quick preview voices"* or *"preview all voices"* |
| Uninstall | `uninstall_tts.ps1` |

Voice and speed scripts live in `%USERPROFILE%\.claude\kokoro\`; the toggle, stop, status, restart, and uninstall scripts live in `%USERPROFILE%\.claude\`.

<p align="center">
  <img src="assets/voices.png" alt="The 27 available voices, by accent and gender" width="820">
</p>

<details>
<summary><b>All 27 voices and previews</b></summary>

- American male: `am_onyx` (default), `am_adam`, `am_echo`, `am_eric`, `am_fenrir`, `am_liam`, `am_michael`, `am_santa`
- American female: `af_alloy`, `af_aoede`, `af_bella`, `af_heart`, `af_jessica`, `af_kore`, `af_nicole`, `af_nova`, `af_river`, `af_sarah`, `af_sky`
- British female: `bf_alice`, `bf_emma`, `bf_isabella`, `bf_lily`
- British male: `bm_daniel`, `bm_fable`, `bm_george`, `bm_lewis`

Short aliases such as `onyx`, `sky`, and `daniel` resolve to full Kokoro IDs.

The easiest way to hear samples is to just ask Claude in the chat, for example:

```
give me a quick voice preview
```
```
play all the voices
```
```
preview the onyx voice
```

Or run the helper yourself in a terminal (PowerShell):

```
py -3 %USERPROFILE%\.claude\kokoro\tts_preview.py "quick preview voices"
```
```
py -3 %USERPROFILE%\.claude\kokoro\tts_preview.py "preview all voices"
```
```
py -3 %USERPROFILE%\.claude\kokoro\tts_preview.py "preview voice onyx"
```

</details>

<details>
<summary><b>What gets spoken (text cleaning rules)</b></summary>

The server cleans the text before synthesising. These are silently skipped or replaced:

- **Code blocks** are removed entirely; only the surrounding explanation is read.
- **Markdown tables** are replaced with "attached table".
- **URLs** are replaced with "link".
- **Emoji** are stripped.
- **Abbreviations** are expanded - `e.g.` becomes "for example", `vs.` becomes "versus", and `$50` becomes "50 dollars".

</details>

---

## Troubleshooting

**Nothing is spoken.** Run `status_tts.ps1`. If the server is not running, run `restart_tts.ps1`.

**Hook not firing.** Check that `%USERPROFILE%\.claude\settings.json` has a Stop hook entry pointing to `tts_hook.ps1`. Re-run the installer if it is missing.

**"pythonw" errors.** The hook must use `powershell.exe`, not `pythonw`, because Python is not on Claude Code's PATH. The installer sets this correctly; if you edited the hook manually, revert to the PowerShell version.

**Claude Code briefly froze after a response (Windows).** The hook uses a 2-second connect timeout, so if Kokoro was in a bad state it recovers within 2 seconds and Claude Code returns control. Run `restart_tts.ps1` if speech stopped.

---

## Uninstall

One command cleanly removes everything it installed:
```
powershell -File %USERPROFILE%\.claude\uninstall_tts.ps1
```

---

## Credits

Built on the open [Kokoro ONNX](https://github.com/thewh1teagle/kokoro-onnx) text-to-speech model, which runs fully offline on CPU.

Created by [Gordon Berger](https://github.com/GordonBerger), part of [Omnicapable](https://github.com/Omnicapable).

---

## License

MIT License. See [LICENSE](LICENSE) for details.
