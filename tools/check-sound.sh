#!/usr/bin/env bash
# Assert aura-glass-sound synthesizes acoustic chimes, builds theme, and integrates with CLI.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
SOUND_BIN="$REPO_ROOT/bin/aura-glass-sound"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help
[ -x "$SOUND_BIN" ] || note "bin/aura-glass-sound is not executable"
out_help="$("$SOUND_BIN" --help)" || note "aura-glass-sound --help failed"
[[ "$out_help" == *"aura-glass-sound"* ]] || note "--help missing aura-glass-sound"
[[ "$out_help" == *"preview"* ]] || note "--help missing preview command"

# 2. Test status, enable, disable in isolated environment
TMP_DIR="$(mktemp -d /tmp/aura-sound-test-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

export XDG_DATA_HOME="$TMP_DIR/data"
export XDG_CONFIG_HOME="$TMP_DIR/config"
mkdir -p "$XDG_CONFIG_HOME/aura-glass"

out_init_status="$("$SOUND_BIN" status)" || note "sound status failed"
[[ "$out_init_status" == *"inactive"* ]] || note "initial status not inactive"

# Enable sound theme (synthesizes WAV chimes and index.theme)
"$SOUND_BIN" enable >/dev/null 2>&1 || note "sound enable failed"
[ -f "$XDG_CONFIG_HOME/aura-glass/sound-theme-active" ] || note "sound-theme-active flag not created"

THEME_DIR="$XDG_DATA_HOME/sounds/aura-glass"
[ -f "$THEME_DIR/index.theme" ] || note "index.theme not created"

for chime in bell screen-capture window-tile audio-volume-change; do
    wav_file="$THEME_DIR/stereo/${chime}.wav"
    [ -f "$wav_file" ] || note "Chime $chime.wav not found at $wav_file"
done

# Validate WAV audio headers and PCM parameters via standard Python wave module
python3 -c "
import wave, glob, sys
wavs = glob.glob('$THEME_DIR/stereo/*.wav')
assert len(wavs) >= 4, f'expected at least 4 wav files, found {len(wavs)}'
for wpath in wavs:
    with wave.open(wpath, 'rb') as w:
        assert w.getnchannels() == 1, f'{wpath} channels={w.getnchannels()}, expected 1'
        assert w.getsampwidth() == 2, f'{wpath} sampwidth={w.getsampwidth()}, expected 2 (16-bit)'
        assert w.getframerate() == 44100, f'{wpath} framerate={w.getframerate()}, expected 44100'
        assert w.getnframes() > 1000, f'{wpath} nframes={w.getnframes()}, expected > 1000'
" || note "WAV chime synthesis audio validation failed"

# Test preview
out_preview="$("$SOUND_BIN" preview bell 2>&1)" || note "sound preview bell failed"
[[ "$out_preview" == *"bell"* ]] || note "preview output missing chime name"

# Disable sound theme
"$SOUND_BIN" disable >/dev/null 2>&1 || note "sound disable failed"
[ ! -f "$XDG_CONFIG_HOME/aura-glass/sound-theme-active" ] || note "sound-theme-active flag not removed after disable"

# 3. Check CLI delegation via aura-glass
out_cli="$("$CLI" sound --help)" || note "aura-glass sound delegation failed"
[[ "$out_cli" == *"aura-glass-sound"* ]] || note "CLI delegation missing aura-glass-sound"

if [ "$fail" -eq 1 ]; then
    printf 'check-sound.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-sound.sh: passed (acoustic chime synthesis, WAV validation, & CLI verified)\n'
