#!/bin/bash
# =============================================================================
# install_claude_tts_Mac_v3.0.sh  v3.0
# One-shot installer for Claude Code local TTS using Kokoro ONNX — macOS
# Fully offline after install. No API keys. No data sent to third parties.
#
# Requirements: macOS 12+, Python 3.9+, Claude Code installed
# Usage: chmod +x install_claude_tts_Mac_v3.0.sh && ./install_claude_tts_Mac_v3.0.sh
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

CLAUDE_DIR="$HOME/.claude"
KOKORO_DIR="$CLAUDE_DIR/kokoro"
PORT=59001
PLIST_LABEL="com.user.kokoro-tts-server"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
VERSION="3.0"

echo ""
echo "============================================"
echo " Claude Code TTS Installer (Kokoro) v$VERSION — Mac"
echo "============================================"
echo ""

# --- 1. Check Python ---------------------------------------------------------
echo "[1/9] Checking Python..."
if ! command -v python3 &>/dev/null; then
  echo -e "${RED}ERROR: python3 not found.${NC}"
  echo "Install Python 3.9+ from https://python.org or via Homebrew: brew install python"
  exit 1
fi
PYTHON=$(command -v python3)
echo "      Found: $($PYTHON --version) at $PYTHON"

# --- 2. Install Python packages ----------------------------------------------
echo "[2/9] Installing Python packages..."
$PYTHON -m pip install kokoro-onnx sounddevice numpy pynput --quiet
echo "      Done."

# --- 3. Create folders -------------------------------------------------------
echo "[3/9] Creating folders..."
mkdir -p "$KOKORO_DIR"
echo "      Done."

# --- 4. Download model files -------------------------------------------------
echo "[4/9] Downloading Kokoro model files (~336 MB total)..."
BASE_URL="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
for FILE in "kokoro-v1.0.onnx" "voices-v1.0.bin"; do
  DEST="$KOKORO_DIR/$FILE"
  if [ -f "$DEST" ]; then
    echo "      Already exists: $FILE"
  else
    echo "      Downloading $FILE..."
    curl -L --progress-bar "$BASE_URL/$FILE" -o "$DEST"
    echo "      Done: $FILE"
  fi
done

# --- 5. Write Python scripts -------------------------------------------------
echo "[5/9] Writing Python scripts..."

cat > "$KOKORO_DIR/tts_server.py" << 'PYEOF'
# -*- coding: utf-8 -*-
"""
tts_server.py v2.0 - Persistent Kokoro TTS server.
Loads the model once, listens on localhost:59001 for text to speak.
Pipelined: synthesizes sentence-by-sentence so first sentence plays immediately.
Supports: stop, speed change, voice change, auto-restart watchdog.
"""
import socket, threading, queue, os, re, time
import numpy as np
import sounddevice as sd

HOST, PORT = "127.0.0.1", 59001
VOICE, SPEED, LANG, MAX_CHARS = "am_onyx", 1.2, "en-us", 5000

base = os.path.dirname(os.path.abspath(__file__))
from kokoro_onnx import Kokoro
kokoro = Kokoro(os.path.join(base, "kokoro-v1.0.onnx"), os.path.join(base, "voices-v1.0.bin"))

# Pre-warm audio device so first sentence has no driver init delay
sd.play(np.zeros(1, dtype=np.float32), samplerate=24000)
sd.wait()

_speak_lock = threading.Semaphore(1)
_stop_event  = threading.Event()

def clean_text(text):
    # --- Tables --- replace markdown tables with a brief label
    text = re.sub(r'(?m)(\|[^\n]+\|\n?)+', ' attached table. ', text)
    # --- Markdown removal ---
    text = re.sub(r'```[\s\S]*?```', '', text)
    text = re.sub(r'`[^`]+`', '', text)
    text = re.sub(r'(?m)^#{1,6}\s+', '', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'\1', text)
    text = re.sub(r'__([^_]+)__', r'\1', text)
    text = re.sub(r'\*([^*]+)\*', r'\1', text)
    text = re.sub(r'_([^_]+)_', r'\1', text)
    text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', text)
    text = re.sub(r'(?m)^\s*[-*+]\s+', '', text)
    text = re.sub(r'(?m)^\s*\d+\.\s+', '', text)
    text = re.sub(r'(?m)^\s*>\s+', '', text)
    text = re.sub(r'\n{2,}', '. ', text)
    text = re.sub(r'\n', ' ', text)
    # --- Symbols ---
    text = re.sub(r'[→←↑↓⇒⇐]', '', text)
    text = text.replace('\u2012', ',').replace('\u2013', ',').replace('\u2014', ',').replace('\u2015', ',').replace('\u2212', ',')
    text = re.sub(r'[|\\]', '', text)
    text = re.sub(r'[•·●◦]', '', text)
    # --- Emojis ---
    text = re.sub(r'[\U0001F000-\U0001FFFF\U00002600-\U000027BF\U0000FE00-\U0000FE0F]+', '', text)
    # --- URLs ---
    text = re.sub(r'https?://\S+', 'link', text)
    # --- Abbreviations ---
    text = re.sub(r'\be\.g\.\b', 'for example', text)
    text = re.sub(r'\bi\.e\.\b', 'that is', text)
    text = re.sub(r'\bvs\.\b', 'versus', text)
    text = re.sub(r'\betc\.\b', 'etcetera', text)
    text = re.sub(r'\bapprox\.\b', 'approximately', text)
    # --- Numbers ---
    text = re.sub(r'(\d),(\d{3})', r'\1\2', text)
    text = re.sub(r'\$(\d)', r'\1 dollars', text)
    text = re.sub(r'(\d)%', r'\1 percent', text)
    text = re.sub(r'(\d+)x\b', r'\1 times', text)
    # --- Whitespace cleanup ---
    text = re.sub(r'\s{2,}', ' ', text)
    return text.strip()

def split_sentences(text):
    parts = re.split(r'(?<=[.!?])\s+', text)
    result = []
    for s in parts:
        s = s.strip()
        if not s: continue
        if result and len(result[-1]) < 40:
            result[-1] += ' ' + s
        else:
            result.append(s)
    return result if result else [text]

def synthesize(sentence, voice_override=None):
    v = voice_override if voice_override else VOICE
    samples, rate = kokoro.create(sentence, voice=v, speed=SPEED, lang=LANG)
    return np.array(samples, dtype=np.float32), rate

def speak(text, voice_override=None):
    text = clean_text(text)
    if not text: return
    if len(text) > MAX_CHARS: text = text[:MAX_CHARS] + " ... response truncated."
    sentences = split_sentences(text)
    _stop_event.clear()
    wav_queue = queue.Queue()

    def producer():
        for sentence in sentences:
            if _stop_event.is_set(): break
            try: wav_queue.put(synthesize(sentence, voice_override=voice_override))
            except Exception: pass
        wav_queue.put(None)

    threading.Thread(target=producer, daemon=True).start()

    while True:
        item = wav_queue.get()
        if item is None or _stop_event.is_set():
            while True:
                try: wav_queue.get_nowait()
                except queue.Empty: break
            break
        samples, rate = item
        sd.play(samples, samplerate=rate)
        sd.wait()
        if _stop_event.is_set():
            sd.stop()
            break

def handle_client(conn):
    with conn:
        data = b""
        while True:
            chunk = conn.recv(4096)
            if not chunk: break
            data += chunk
        text = data.decode("utf-8", errors="ignore").strip()

        if text == "__STOP__":
            _stop_event.set(); sd.stop(); return

        if text.startswith("__SPEED:") and text.endswith("__"):
            global SPEED
            try: SPEED = float(text[8:-2].strip())
            except ValueError: pass
            return

        if text == "__GETSPEED__":
            try: conn.sendall(str(SPEED).encode("utf-8")); conn.shutdown(socket.SHUT_WR)
            except Exception: pass
            return

        if text.startswith("__VOICE:") and text.endswith("__"):
            global VOICE
            VOICE = text[8:-2].strip(); return

        if text == "__GETVOICE__":
            try: conn.sendall(VOICE.encode("utf-8")); conn.shutdown(socket.SHUT_WR)
            except Exception: pass
            return

        if text:
            # Per-request voice prefix: "VOICE=af_sky|actual text"
            req_voice = None
            if text.startswith("VOICE=") and "|" in text:
                prefix, text = text.split("|", 1)
                req_voice = prefix[6:].strip()
            if text:
                with _speak_lock: speak(text, voice_override=req_voice)

def run_server():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((HOST, PORT)); srv.listen()
        while True:
            conn, _ = srv.accept()
            threading.Thread(target=handle_client, args=(conn,), daemon=True).start()

# Auto-restart watchdog
while True:
    try: run_server()
    except Exception: time.sleep(3)
PYEOF

cat > "$KOKORO_DIR/tts_speak.py" << 'PYEOF'
# -*- coding: utf-8 -*-
"""Direct synthesis fallback — used when server is not yet running."""
import sys, os, re
import numpy as np
import sounddevice as sd

VOICE, SPEED, LANG, MAX_CHARS = "am_onyx", 1.2, "en-us", 5000
base = os.path.dirname(os.path.abspath(__file__))

def clean_text(text):
    # --- Tables ---
    text = re.sub(r'(?m)(\|[^\n]+\|\n?)+', ' attached table. ', text)
    # --- Markdown removal ---
    text = re.sub(r'```[\s\S]*?```', '', text)
    text = re.sub(r'`[^`]+`', '', text)
    text = re.sub(r'(?m)^#{1,6}\s+', '', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'\1', text)
    text = re.sub(r'__([^_]+)__', r'\1', text)
    text = re.sub(r'\*([^*]+)\*', r'\1', text)
    text = re.sub(r'_([^_]+)_', r'\1', text)
    text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', text)
    text = re.sub(r'(?m)^\s*[-*+]\s+', '', text)
    text = re.sub(r'(?m)^\s*\d+\.\s+', '', text)
    text = re.sub(r'(?m)^\s*>\s+', '', text)
    text = re.sub(r'\n{2,}', '. ', text)
    text = re.sub(r'\n', ' ', text)
    # --- Symbols ---
    text = re.sub(r'[→←↑↓⇒⇐]', '', text)
    text = text.replace('\u2012', ',').replace('\u2013', ',').replace('\u2014', ',').replace('\u2015', ',').replace('\u2212', ',')
    text = re.sub(r'[|\\]', '', text)
    text = re.sub(r'[•·●◦]', '', text)
    # --- Emojis ---
    text = re.sub(r'[\U0001F000-\U0001FFFF\U00002600-\U000027BF\U0000FE00-\U0000FE0F]+', '', text)
    # --- URLs ---
    text = re.sub(r'https?://\S+', 'link', text)
    # --- Abbreviations ---
    text = re.sub(r'\be\.g\.\b', 'for example', text)
    text = re.sub(r'\bi\.e\.\b', 'that is', text)
    text = re.sub(r'\bvs\.\b', 'versus', text)
    text = re.sub(r'\betc\.\b', 'etcetera', text)
    text = re.sub(r'\bapprox\.\b', 'approximately', text)
    # --- Numbers ---
    text = re.sub(r'(\d),(\d{3})', r'\1\2', text)
    text = re.sub(r'\$(\d)', r'\1 dollars', text)
    text = re.sub(r'(\d)%', r'\1 percent', text)
    text = re.sub(r'(\d+)x\b', r'\1 times', text)
    # --- Whitespace ---
    text = re.sub(r'\s{2,}', ' ', text)
    return text.strip()

text = sys.stdin.read().strip()
if not text: sys.exit(0)
text = clean_text(text)
if len(text) > MAX_CHARS: text = text[:MAX_CHARS] + " ... response truncated."

from kokoro_onnx import Kokoro
kokoro = Kokoro(os.path.join(base,"kokoro-v1.0.onnx"), os.path.join(base,"voices-v1.0.bin"))
samples, rate = kokoro.create(text, voice=VOICE, speed=SPEED, lang=LANG)
sd.play(np.array(samples, dtype=np.float32), samplerate=rate)
sd.wait()
PYEOF

cat > "$KOKORO_DIR/set_voice.py" << 'PYEOF'
"""
set_voice.py - Change the TTS voice on the fly without restarting the server.
Usage: python3 set_voice.py VOICENAME
       python3 set_voice.py --current
"""
import sys, socket

PORT = 59001
VOICES = [
    "am_onyx","am_adam","am_echo","am_eric","am_fenrir","am_liam","am_michael","am_santa",
    "af_alloy","af_aoede","af_bella","af_heart","af_jessica","af_kore","af_nicole","af_nova","af_river","af_sarah","af_sky",
    "bf_alice","bf_emma","bf_isabella","bf_lily",
    "bm_daniel","bm_fable","bm_george","bm_lewis",
]

def send(msg, expect_reply=False):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(("127.0.0.1", PORT))
    s.sendall(msg.encode("utf-8"))
    s.shutdown(socket.SHUT_WR)
    if expect_reply:
        data = b""
        try:
            while True:
                chunk = s.recv(1024)
                if not chunk: break
                data += chunk
        except Exception: pass
        s.close()
        return data.decode("utf-8").strip()
    s.close()
    return None

if len(sys.argv) < 2:
    print("Available voices:")
    for v in VOICES: print(f"  {v}")
    sys.exit(0)

if sys.argv[1] == "--current":
    print(f"Current voice: {send('__GETVOICE__', expect_reply=True)}")
    sys.exit(0)

voice = sys.argv[1].strip()
if voice not in VOICES:
    print(f"Unknown voice: {voice}")
    print("Run without arguments to see available voices.")
    sys.exit(1)

send(f"__VOICE:{voice}__")
print(f"Voice changed to: {voice}")
PYEOF

cat > "$KOKORO_DIR/set_speed.py" << 'PYEOF'
# -*- coding: utf-8 -*-
"""
set_speed.py - Change the TTS speed on the fly without restarting the server.
Usage: python3 set_speed.py 1.3
       python3 set_speed.py --up       (increase by 0.2)
       python3 set_speed.py --down     (decrease by 0.2)
       python3 set_speed.py --current
"""
import sys, socket

PORT = 59001
STEP = 0.2

def send(msg, expect_reply=False):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(("127.0.0.1", PORT))
    s.sendall(msg.encode("utf-8"))
    s.shutdown(socket.SHUT_WR)
    if expect_reply:
        data = b""
        try:
            while True:
                chunk = s.recv(1024)
                if not chunk: break
                data += chunk
        except Exception: pass
        s.close()
        return data.decode("utf-8").strip()
    s.close()
    return None

if len(sys.argv) < 2:
    print("Usage: python3 set_speed.py SPEED  (e.g. 1.3)")
    print("       python3 set_speed.py --up")
    print("       python3 set_speed.py --down")
    print("       python3 set_speed.py --current")
    sys.exit(0)

if sys.argv[1] == "--current":
    print(f"Current speed: {send('__GETSPEED__', expect_reply=True)}")
    sys.exit(0)

if sys.argv[1] in ("--up", "--down"):
    current = send("__GETSPEED__", expect_reply=True)
    try:
        current = float(current)
    except:
        print("Could not read current speed from server.")
        sys.exit(1)
    speed = round(current + (STEP if sys.argv[1] == "--up" else -STEP), 2)
    speed = max(0.5, min(2.5, speed))
    send(f"__SPEED:{speed}__")
    print(f"Speed changed to: {speed}x")
    sys.exit(0)

try:
    speed = float(sys.argv[1])
    assert 0.5 <= speed <= 2.5
except:
    print("Speed must be a number between 0.5 and 2.5")
    sys.exit(1)

send(f"__SPEED:{speed}__")
print(f"Speed changed to: {speed}x")
PYEOF

# preview_voices.py
cat > "$KOKORO_DIR/preview_voices.py" << 'PYEOF'
# -*- coding: utf-8 -*-
# preview_voices.py - Cycle through Kokoro voices so you can hear them before choosing.
# Usage: python3 preview_voices.py              (all voices, ~3 min)
#        python3 preview_voices.py --category   (one per group, ~30 sec)
#        python3 preview_voices.py am_onyx      (single voice test)

import socket, time, sys

HOST, PORT = "127.0.0.1", 59001

VOICES = {
    "American male":   ["am_onyx","am_adam","am_echo","am_eric","am_fenrir","am_liam","am_michael","am_santa"],
    "American female": ["af_alloy","af_aoede","af_bella","af_heart","af_jessica","af_kore","af_nicole","af_nova","af_river","af_sarah","af_sky"],
    "British female":  ["bf_alice","bf_emma","bf_isabella","bf_lily"],
    "British male":    ["bm_daniel","bm_fable","bm_george","bm_lewis"],
}

CATEGORY_REPS = {
    "American male":   ["am_onyx","am_echo"],
    "British female":  ["bf_emma"],
    "British male":    ["bm_daniel"],
    "American female": ["af_alloy","af_heart","af_nicole"],
}

SAMPLE = "Hello! This is how I sound. You can ask Claude to switch to this voice anytime."

def send(text):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5); s.connect((HOST, PORT)); s.sendall(text.encode("utf-8"))
        return True
    except Exception as e:
        print(f"  [error] {e}"); return False

def send_recv(text):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5); s.connect((HOST, PORT)); s.sendall(text.encode("utf-8"))
            s.shutdown(socket.SHUT_WR)
            data = b""
            while True:
                chunk = s.recv(1024)
                if not chunk: break
                data += chunk
        return data.decode("utf-8").strip()
    except Exception: return None

def get_current_voice():
    v = send_recv("__GETVOICE__"); return v if v else "am_onyx"

def preview_voice(category, name, delay=5):
    label = f"{category} -- {name.split('_',1)[1]}"
    print(f"  {label}")
    send(f"__VOICE:{name}__"); time.sleep(0.2)
    send(f"{label}. {SAMPLE}"); time.sleep(delay)

def main():
    args = sys.argv[1:]
    if args and not args[0].startswith("--"):
        name = args[0]
        cat = next((c for c, vs in VOICES.items() if name in vs), "Unknown")
        original = get_current_voice()
        print(f"Testing voice: {name}")
        preview_voice(cat, name, delay=6)
        send(f"__VOICE:{original}__")
        print("Done."); return
    original = get_current_voice()
    reps = "--category" in args
    pool = CATEGORY_REPS if reps else VOICES
    label = "selected voices" if reps else "all voices"
    print(f"Playing {label}. Will restore '{original}' when done. Ctrl+C to stop.\n")
    try:
        for cat, names in pool.items():
            print(f"[{cat}]")
            for name in names:
                preview_voice(cat, name, delay=8 if reps else 5)
            if not reps: print()
    except KeyboardInterrupt:
        send("__STOP__"); send(f"__VOICE:{original}__"); print("\nStopped."); return
    send(f"__VOICE:{original}__"); time.sleep(0.2)
    if reps:
        send("That was a quick selection. There are over 20 other voices available. Just ask me to preview all voices, or say switch to any voice name you heard.")
    print("\nDone. Ask Claude to switch to any voice you liked.")

if __name__ == "__main__":
    main()
PYEOF
chmod +x "$KOKORO_DIR/preview_voices.py"

echo "      Done."

# --- 6. Write shell scripts --------------------------------------------------
# tts_preview.py - friendly preview phrase router
cat > "$KOKORO_DIR/tts_preview.py" << 'PYEOF'
# -*- coding: utf-8 -*-
"""tts_preview.py - friendly voice-preview command router for Kokoro TTS.

Accepted examples:
  quick preview voices
  preview all voices
  preview voice onyx
  __PREVIEW_QUICK__

Exit codes:
  0 = preview command recognized/handled
  1 = malformed preview command or unknown voice
  2 = not a preview command
"""

import os
import re
import socket
import subprocess
import sys
import time

HOST, PORT = "127.0.0.1", 59001

VOICES = {
    "American male": ["am_onyx", "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael", "am_santa"],
    "American female": ["af_alloy", "af_aoede", "af_bella", "af_heart", "af_jessica", "af_kore", "af_nicole", "af_nova", "af_river", "af_sarah", "af_sky"],
    "British female": ["bf_alice", "bf_emma", "bf_isabella", "bf_lily"],
    "British male": ["bm_daniel", "bm_fable", "bm_george", "bm_lewis"],
}

# One short representative per category for quick preview.
CATEGORY_REPS = {
    "American male": ["am_onyx"],
    "American female": ["af_sky"],
    "British female": ["bf_emma"],
    "British male": ["bm_daniel"],
}

SAMPLE = "Hello! This is how I sound. You can ask to switch to this voice anytime."
QUICK_PHRASES = {
    "quick preview voices",
    "quick voice preview",
    "preview voices",
    "voice preview",
}
FULL_PHRASES = {
    "preview all voices",
    "full preview voices",
    "play all voices",
}
SINGLE_RE = re.compile(r"^(preview|test|hear) voice ([a-z0-9_ -]+)$")

ALL_VOICES = [voice for voices in VOICES.values() for voice in voices]
ALIASES = {}
for voice in ALL_VOICES:
    suffix = voice.split("_", 1)[1]
    ALIASES.setdefault(suffix, []).append(voice)
    ALIASES.setdefault(voice, []).append(voice)


def normalize(text):
    text = (text or "").strip().strip('"\'')
    text = text.replace("\u201c", '"').replace("\u201d", '"').replace("\u2018", "'").replace("\u2019", "'")
    text = text.lower()
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def resolve_voice(name):
    key = normalize(name).replace(" ", "_").replace("-", "_")
    if key in ALL_VOICES:
        return key
    matches = ALIASES.get(key, [])
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        raise ValueError(f"Ambiguous voice alias '{name}': {', '.join(matches)}")
    raise ValueError(f"Unknown voice '{name}'. Try a full voice ID like am_onyx or af_sky.")


def parse_command(raw):
    original = (raw or "").strip()
    text = normalize(original)
    upper = original.upper().strip()

    if upper == "__PREVIEW_QUICK__":
        return ("quick", None)
    if upper == "__PREVIEW_ALL__":
        return ("all", None)
    if upper.startswith("__PREVIEW_VOICE__:"):
        return ("voice", resolve_voice(original.split(":", 1)[1].strip()))

    if text in QUICK_PHRASES:
        return ("quick", None)
    if text in FULL_PHRASES:
        return ("all", None)

    match = SINGLE_RE.fullmatch(text)
    if match:
        return ("voice", resolve_voice(match.group(2).strip()))

    # Phrases that look like a preview request but are not whitelisted should fail loudly.
    if text.startswith(("preview", "test voice", "hear voice")):
        raise ValueError("Preview command not recognized. Try 'quick preview voices', 'preview all voices', or 'preview voice onyx'.")

    return (None, None)


def display_action(mode, voice=None):
    if mode == "quick":
        return "preview_voices.py --category"
    if mode == "all":
        return "preview_voices.py"
    if mode == "voice":
        return f"preview_voices.py {voice}"
    return "not a preview command"


def send(text, timeout=5):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect((HOST, PORT))
        s.sendall(text.encode("utf-8"))


def send_recv(text, timeout=5):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        s.connect((HOST, PORT))
        s.sendall(text.encode("utf-8"))
        s.shutdown(socket.SHUT_WR)
        data = b""
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            data += chunk
    return data.decode("utf-8", errors="replace").strip()


def get_current_voice():
    try:
        return send_recv("__GETVOICE__") or "am_onyx"
    except Exception:
        return "am_onyx"


def set_voice(name):
    send(f"__VOICE:{name}__")


def stop_speech():
    try:
        send("__STOP__", timeout=1)
    except Exception:
        pass


def preview_voice(category, name, delay=5.0):
    label = f"{category} - {name.split('_', 1)[1]}"
    print(f"  {label}", flush=True)
    set_voice(name)
    time.sleep(0.2)
    send(f"{label}. {SAMPLE}")
    time.sleep(delay)


def run_preview(mode, voice=None):
    original = get_current_voice()
    print(f"Starting voice preview. Will restore '{original}' when done.", flush=True)
    try:
        if mode == "voice":
            category = next((cat for cat, names in VOICES.items() if voice in names), "Voice")
            preview_voice(category, voice, delay=6.0)
        elif mode == "quick":
            for category, names in CATEGORY_REPS.items():
                print(f"[{category}]", flush=True)
                for name in names:
                    preview_voice(category, name, delay=6.0)
        elif mode == "all":
            for category, names in VOICES.items():
                print(f"[{category}]", flush=True)
                for name in names:
                    preview_voice(category, name, delay=4.5)
    except KeyboardInterrupt:
        stop_speech()
        print("Stopped.", flush=True)
    finally:
        try:
            set_voice(original)
            time.sleep(0.2)
        except Exception:
            pass
        print("Voice preview done.", flush=True)


def launch_background(mode, voice=None):
    args = [sys.executable, os.path.abspath(__file__), "--run-preview", mode]
    if voice:
        args.append(voice)
    kwargs = {}
    if os.name == "nt":
        kwargs["creationflags"] = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kwargs)


def main(argv):
    dry_run = False
    args = list(argv)
    if "--run-preview" in args:
        idx = args.index("--run-preview")
        mode = args[idx + 1] if len(args) > idx + 1 else ""
        voice = args[idx + 2] if len(args) > idx + 2 else None
        if mode not in {"quick", "all", "voice"}:
            print("Invalid internal preview mode.", file=sys.stderr)
            return 1
        run_preview(mode, voice)
        return 0

    if "--dry-run" in args:
        dry_run = True
        args.remove("--dry-run")

    raw = " ".join(args).strip()
    if not raw:
        print("No preview command provided.", file=sys.stderr)
        return 2

    try:
        mode, voice = parse_command(raw)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if not mode:
        print("Not a preview command.")
        return 2

    action = display_action(mode, voice)
    if dry_run:
        print(action)
        return 0

    launch_background(mode, voice)
    print(f"Starting: {action}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
PYEOF
chmod +x "$KOKORO_DIR/tts_preview.py"
echo "[6/9] Writing shell scripts..."

cat > "$CLAUDE_DIR/tts_hook.sh" << SHEOF
#!/bin/bash
TOGGLE_FILE="\$HOME/.claude/tts_enabled.txt"
TTS_SCRIPT="\$HOME/.claude/kokoro/tts_speak.py"
TTS_SERVER="\$HOME/.claude/kokoro/tts_server.py"
PORT=$PORT

if [ ! -f "\$TOGGLE_FILE" ]; then exit 0; fi
STATE=\$(tr '[:upper:]' '[:lower:]' < "\$TOGGLE_FILE" | tr -d '[:space:]')
if [ "\$STATE" != "on" ]; then exit 0; fi

STDIN_CONTENT=\$(cat)
if [ -z "\$STDIN_CONTENT" ]; then exit 0; fi

TEXT=\$(echo "\$STDIN_CONTENT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('last_assistant_message', ''), end='')
except: pass
" 2>/dev/null)

if [ -z "\$TEXT" ]; then exit 0; fi

if echo "\$TEXT" | python3 -c "
import sys, socket
s = socket.socket()
s.settimeout(2)
try:
    s.connect(('127.0.0.1', \$PORT))
    s.sendall(sys.stdin.buffer.read())
    s.close()
    exit(0)
except: exit(1)
" 2>/dev/null; then
    exit 0
fi

python3 "\$TTS_SERVER" &
sleep 2.5
echo "\$TEXT" | python3 -c "
import sys, socket
s = socket.socket()
s.settimeout(2)
try:
    s.connect(('127.0.0.1', \$PORT))
    s.sendall(sys.stdin.buffer.read())
    s.close()
except: pass
" 2>/dev/null || true
SHEOF
chmod +x "$CLAUDE_DIR/tts_hook.sh"

cat > "$CLAUDE_DIR/toggle_tts.sh" << SHEOF
#!/bin/bash
FILE="\$HOME/.claude/tts_enabled.txt"
if [ "\$1" = "on" ] || [ "\$1" = "off" ]; then
    echo "\$1" > "\$FILE"; echo "TTS \$1"; exit 0
fi
if [ ! -f "\$FILE" ]; then echo "on" > "\$FILE"; echo "TTS on"
else
    STATE=\$(cat "\$FILE" | tr -d '[:space:]')
    if [ "\$STATE" = "on" ]; then echo "off" > "\$FILE"; echo "TTS off"
    else echo "on" > "\$FILE"; echo "TTS on"; fi
fi
SHEOF
chmod +x "$CLAUDE_DIR/toggle_tts.sh"

cat > "$CLAUDE_DIR/restart_tts.sh" << SHEOF
#!/bin/bash
LABEL="$PLIST_LABEL"
launchctl bootout "gui/\$(id -u)/\$LABEL" 2>/dev/null || true
sleep 1
launchctl bootstrap "gui/\$(id -u)" "\$HOME/Library/LaunchAgents/\$LABEL.plist"
echo "TTS server restarted."
SHEOF
chmod +x "$CLAUDE_DIR/restart_tts.sh"

cat > "$CLAUDE_DIR/stop_tts.sh" << SHEOF
#!/bin/bash
python3 -c "
import socket
s = socket.socket()
s.settimeout(2)
try:
    s.connect(('127.0.0.1', $PORT))
    s.sendall(b'__STOP__')
    s.close()
except: pass
"
SHEOF
chmod +x "$CLAUDE_DIR/stop_tts.sh"

cat > "$CLAUDE_DIR/status_tts.sh" << 'SHEOF'
#!/bin/bash
if python3 -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('127.0.0.1',59001)); s.close()" 2>/dev/null; then
    echo "TTS server is running."
else
    echo "TTS server is NOT running. Run: bash ~/.claude/restart_tts.sh"
fi
SHEOF
chmod +x "$CLAUDE_DIR/status_tts.sh"

cat > "$CLAUDE_DIR/uninstall_tts.sh" << SHEOF
#!/bin/bash
# =============================================================================
# uninstall_tts.sh - Remove Claude Code TTS (Kokoro) from this machine.
# =============================================================================

LABEL="$PLIST_LABEL"
PLIST="$PLIST_PATH"
CLAUDE_DIR="\$HOME/.claude"

echo ""
echo "============================================"
echo " Claude Code TTS Uninstaller"
echo "============================================"
echo ""

echo "[1/5] Stopping TTS server and hotkey daemon..."
launchctl bootout "gui/\$(id -u)/\$LABEL" 2>/dev/null || true
pkill -f tts_server.py 2>/dev/null || true
launchctl bootout "gui/\$(id -u)/com.user.kokoro-tts-hotkey" 2>/dev/null || true
pkill -f tts_hotkey.py 2>/dev/null || true
echo "      Done."

echo "[2/5] Removing launchd plists..."
rm -f "\$PLIST"
rm -f "\$HOME/Library/LaunchAgents/com.user.kokoro-tts-hotkey.plist"
echo "      Done."

echo "[3/5] Removing Automator stop shortcut..."
rm -rf "\$HOME/Library/Services/Stop TTS.workflow"
/System/Library/CoreServices/pbs -update 2>/dev/null || true
echo "      Done."

echo "[4/5] Removing hook from settings.json..."
python3 -c "
import json, os
path = os.path.expanduser('~/.claude/settings.json')
if not os.path.exists(path): exit(0)
with open(path) as f: s = json.load(f)
if 'Stop' in s.get('hooks', {}):
    s['hooks']['Stop'][0]['hooks'] = [
        h for h in s['hooks']['Stop'][0]['hooks'] if 'tts_hook' not in h.get('command','')
    ]
    with open(path, 'w') as f: json.dump(s, f, indent=2)
    print('      Done.')
else:
    print('      Hook not found, skipping.')
"

echo "[5/5] Removing TTS files..."
rm -f "\$CLAUDE_DIR/tts_hook.sh" "\$CLAUDE_DIR/tts_enabled.txt"
rm -f "\$CLAUDE_DIR/toggle_tts.sh" "\$CLAUDE_DIR/restart_tts.sh"
rm -f "\$CLAUDE_DIR/stop_tts.sh" "\$CLAUDE_DIR/status_tts.sh"
rm -f "\$CLAUDE_DIR/uninstall_tts.sh" "\$CLAUDE_DIR/CLAUDE.md"
rm -rf "\$CLAUDE_DIR/kokoro"
echo "      Done."

echo ""
echo "============================================"
echo " TTS removed. Python packages (kokoro-onnx,"
echo " sounddevice, numpy) were left in place."
echo " Remove with: pip3 uninstall kokoro-onnx sounddevice"
echo "============================================"
echo ""
SHEOF
chmod +x "$CLAUDE_DIR/uninstall_tts.sh"

# CLAUDE.md
cat > "$CLAUDE_DIR/CLAUDE.md" << SHEOF
# Claude Code — Global Instructions

## Text-to-Speech

A local Kokoro TTS server runs on port 59001. Every assistant response is spoken automatically via the Stop hook — no action needed from Claude.

### Changing the voice
When the user asks to change the voice, run:
    python3 $KOKORO_DIR/set_voice.py VOICENAME

IMPORTANT: Never change the user's voice unless they explicitly ask.

Available voices:
- American male:   am_onyx (default), am_adam, am_echo, am_eric, am_fenrir, am_liam, am_michael, am_santa
- American female: af_alloy, af_aoede, af_bella, af_heart, af_jessica, af_kore, af_nicole, af_nova, af_river, af_sarah, af_sky
- British female:  bf_alice, bf_emma, bf_isabella, bf_lily
- British male:    bm_daniel, bm_fable, bm_george, bm_lewis

### Checking current voice
    python3 $KOKORO_DIR/set_voice.py --current

### Changing speed
When the user says "speak faster" or "speak slower", run:
    python3 $KOKORO_DIR/set_speed.py --up
    python3 $KOKORO_DIR/set_speed.py --down
When the user gives a specific speed (e.g. "set speed to 1.5"), run:
    python3 $KOKORO_DIR/set_speed.py 1.5
Speed range: 0.5 (slow) to 2.5 (fast). Step size: 0.2x.

### Previewing voices
When the user asks "quick preview voices", "preview all voices", "preview voice <name>", or similar direct preview commands, run:
    python3 $KOKORO_DIR/tts_preview.py "<user request>"
Examples:
    python3 $KOKORO_DIR/tts_preview.py "quick preview voices"
    python3 $KOKORO_DIR/tts_preview.py "preview all voices"
    python3 $KOKORO_DIR/tts_preview.py "preview voice onyx"
Short aliases such as onyx, sky, and daniel are supported. Do not trigger previews for explanatory text about previews.

### Other controls
    bash $CLAUDE_DIR/toggle_tts.sh on|off    (toggle TTS)
    bash $CLAUDE_DIR/restart_tts.sh          (restart server)
    bash $CLAUDE_DIR/status_tts.sh           (check server)
    bash $CLAUDE_DIR/stop_tts.sh             (stop current speech)

### Hook note
The Stop hook uses bash (tts_hook.sh). Do NOT change it to a background process — it must complete synchronously to ensure the response is spoken.
SHEOF

echo "on" > "$CLAUDE_DIR/tts_enabled.txt"
echo "      Done."

# --- 7. Update settings.json -------------------------------------------------
echo "[7/9] Updating Claude Code settings.json..."
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_CMD="bash $CLAUDE_DIR/tts_hook.sh"

$PYTHON - << PYEOF
import json, os, sys

path = os.path.expanduser("~/.claude/settings.json")
hook_cmd = "$HOOK_CMD"

if os.path.exists(path):
    with open(path) as f:
        settings = json.load(f)
else:
    settings = {"hooks": {}}

if "hooks" not in settings:
    settings["hooks"] = {}

new_hook = {"type": "command", "command": hook_cmd, "async": True}

if "Stop" not in settings["hooks"]:
    settings["hooks"]["Stop"] = [{"hooks": [new_hook]}]
else:
    existing = settings["hooks"]["Stop"][0]["hooks"]
    if not any("tts_hook" in h.get("command","") for h in existing):
        existing.append(new_hook)
    else:
        print("      Hook already present, skipping.")
        sys.exit(0)

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
PYEOF
echo "      Done."

# --- 8. Set up launchd auto-start --------------------------------------------
echo "[8/9] Setting up launchd auto-start and launching server..."

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_PATH" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON</string>
        <string>$KOKORO_DIR/tts_server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.claude/tts_server.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.claude/tts_server.log</string>
</dict>
</plist>
PLISTEOF

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true

# --- Ctrl+Option+X global stop hotkey (pynput; needs Accessibility permission) ---
HOTKEY_PLIST_LABEL="com.user.kokoro-tts-hotkey"
HOTKEY_PLIST_PATH="$HOME/Library/LaunchAgents/$HOTKEY_PLIST_LABEL.plist"
cat > "$KOKORO_DIR/tts_hotkey.py" << 'PYEOF'
# -*- coding: utf-8 -*-
"""
Safe global TTS hotkey daemon (macOS).
Registers Ctrl+Option+X via pynput and sends Kokoro's shared __STOP__ command to
127.0.0.1:59001. Requires Accessibility permission for the launching process
(System Settings > Privacy & Security > Accessibility). Without it the hotkey
silently does nothing — a macOS security requirement, not a bug.
"""
import os
import socket
import time

HOST = "127.0.0.1"
PORT = 59001
LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs", "tts_hotkey.log")


def log(message):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}"
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def send_stop():
    try:
        with socket.create_connection((HOST, PORT), timeout=1.0) as sock:
            sock.sendall(b"__STOP__")
        log("Ctrl+Option+X sent __STOP__")
    except Exception as exc:
        log(f"Ctrl+Option+X failed to send __STOP__: {exc}")


def main():
    try:
        from pynput import keyboard
    except Exception as exc:
        log(f"pynput unavailable, hotkey disabled: {exc}")
        return
    log("Hotkey daemon starting (Ctrl+Option+X). Needs Accessibility permission.")
    with keyboard.GlobalHotKeys({"<ctrl>+<alt>+x": send_stop}) as h:
        h.join()


if __name__ == "__main__":
    main()
PYEOF
cat > "$HOTKEY_PLIST_PATH" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$HOTKEY_PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON</string>
        <string>$KOKORO_DIR/tts_hotkey.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.claude/tts_hotkey.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.claude/tts_hotkey.log</string>
</dict>
</plist>
PLISTEOF
launchctl bootout "gui/$(id -u)/$HOTKEY_PLIST_LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOTKEY_PLIST_PATH" 2>/dev/null || true
echo "      Ctrl+Option+X stop hotkey installed (pynput)."
echo "      IMPORTANT: macOS needs Accessibility permission for the hotkey to work:"
echo "        System Settings > Privacy & Security > Accessibility  (add & enable: $PYTHON)"

echo "      Waiting for server to load model (~10 seconds)..."
sleep 10

if python3 -c "import socket; s=socket.socket(); s.settimeout(2); s.connect(('127.0.0.1',$PORT)); s.close()" 2>/dev/null; then
    echo "      Server running."
else
    echo -e "      ${YELLOW}WARNING: Server did not respond. Try running: bash ~/.claude/restart_tts.sh${NC}"
fi

# --- 9. Set up Ctrl+Option+X stop shortcut via Automator --------------------
echo "[9/9] Setting up Ctrl+Option+X stop shortcut..."

SERVICES_DIR="$HOME/Library/Services"
WORKFLOW_DIR="$SERVICES_DIR/Stop TTS.workflow/Contents"
mkdir -p "$WORKFLOW_DIR"

# Write the Automator workflow document.wflow
cat > "$WORKFLOW_DIR/document.wflow" << 'WFEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AMApplicationBuild</key>
    <string>523</string>
    <key>AMApplicationVersion</key>
    <string>2.10</string>
    <key>AMDocumentVersion</key>
    <string>2</string>
    <key>actions</key>
    <array>
        <dict>
            <key>action</key>
            <dict>
                <key>AMAccepts</key>
                <dict>
                    <key>Container</key>
                    <string>List</string>
                    <key>Optional</key>
                    <true/>
                    <key>Types</key>
                    <array><string>com.apple.cocoa.string</string></array>
                </dict>
                <key>AMActionVersion</key>
                <string>2.0.3</string>
                <key>AMApplication</key>
                <array><string>Automator</string></array>
                <key>AMParameterProperties</key>
                <dict>
                    <key>COMMAND_STRING</key>
                    <dict/>
                    <key>CheckedForUserDefaultShell</key>
                    <dict/>
                    <key>inputMethod</key>
                    <dict/>
                    <key>shell</key>
                    <dict/>
                    <key>source</key>
                    <dict/>
                </dict>
                <key>AMProvides</key>
                <dict>
                    <key>Container</key>
                    <string>List</string>
                    <key>Types</key>
                    <array><string>com.apple.cocoa.string</string></array>
                </dict>
                <key>ActionBundlePath</key>
                <string>/System/Library/Automator/Run Shell Script.action</string>
                <key>ActionName</key>
                <string>Run Shell Script</string>
                <key>ActionParameters</key>
                <dict>
                    <key>COMMAND_STRING</key>
                    <string>bash ~/.claude/stop_tts.sh</string>
                    <key>CheckedForUserDefaultShell</key>
                    <true/>
                    <key>inputMethod</key>
                    <integer>0</integer>
                    <key>shell</key>
                    <string>/bin/bash</string>
                    <key>source</key>
                    <string></string>
                </dict>
                <key>BundleIdentifier</key>
                <string>com.apple.RunShellScript</string>
                <key>CFBundleVersion</key>
                <string>2.0.3</string>
                <key>CanShowSelectedItemsWhenRun</key>
                <false/>
                <key>CanShowWhenRun</key>
                <true/>
                <key>Category</key>
                <array><string>AMCategoryUtilities</string></array>
                <key>Class Name</key>
                <string>RunShellScriptAction</string>
                <key>InputUUID</key>
                <string>B9D1A2C3-4E5F-6789-ABCD-EF0123456789</string>
                <key>Keywords</key>
                <array><string>Shell</string><string>Script</string><string>Command</string></array>
                <key>OutputUUID</key>
                <string>A1B2C3D4-E5F6-7890-ABCD-EF1234567890</string>
                <key>UUID</key>
                <string>C3D4E5F6-7890-ABCD-EF12-34567890ABCD</string>
                <key>UnlocalizedApplications</key>
                <array><string>Automator</string></array>
                <key>arguments</key>
                <dict>
                    <key>0</key>
                    <dict>
                        <key>default value</key>
                        <integer>0</integer>
                        <key>name</key>
                        <string>inputMethod</string>
                        <key>required</key>
                        <string>0</string>
                        <key>type</key>
                        <string>0</string>
                        <key>uuid</key>
                        <string>0</string>
                    </dict>
                </dict>
                <key>isViewVisible</key>
                <true/>
                <key>location</key>
                <string>309.500000:253.000000</string>
                <key>nibPath</key>
                <string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/English.lproj/main.nib</string>
            </dict>
            <key>isViewVisible</key>
            <true/>
        </dict>
    </array>
    <key>connectors</key>
    <dict/>
    <key>workflowMetaData</key>
    <dict>
        <key>workflowTypeIdentifier</key>
        <string>com.apple.Automator.servicesMenu</string>
    </dict>
</dict>
</plist>
WFEOF

# Write Info.plist
cat > "$WORKFLOW_DIR/Info.plist" << 'INFEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Stop TTS</string>
            </dict>
            <key>NSMessage</key>
            <string>runWorkflowAsService</string>
            <key>NSRequiredContext</key>
            <dict/>
            <key>NSSendTypes</key>
            <array/>
        </dict>
    </array>
</dict>
</plist>
INFEOF

# Register the service
/System/Library/CoreServices/pbs -update 2>/dev/null || true

# Assign Ctrl+Option+X keyboard shortcut via defaults
defaults write pbs NSServicesStatus -dict-add '"(null) - Stop TTS - runWorkflowAsService"' '{
    "key_equivalent" = "^~x";
    "enabled_context_menu" = 1;
    "enabled_services_menu" = 1;
    "presentation_modes" = { "ContextMenu" = 1; "ServicesMenu" = 1; };
}' 2>/dev/null || true

echo "      Done. Press Ctrl+Option+X to stop speech mid-reply."
echo "      (You may see a one-time permissions prompt the first time you use it.)"

echo ""
echo "============================================"
echo " Setup complete!"
echo "============================================"
echo ""
echo " Version: v$VERSION  |  Voice: am_onyx  |  Speed: 1.1x"
echo ""
echo " Toggle:       tell Claude 'turn voice on' or 'turn voice off'"
echo " Change voice: tell Claude 'switch to voice sky'"
echo "               27 voices — American and British, male and female"
echo " Change speed: tell Claude 'speak faster' or 'speak slower'"
echo "               or: python3 ~/.claude/kokoro/set_speed.py 1.3"
echo " Stop:         press Ctrl+Option+X"
echo " Status:       bash ~/.claude/status_tts.sh"
echo " Uninstall:    bash ~/.claude/uninstall_tts.sh"
echo ""
