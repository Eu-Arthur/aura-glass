#!/usr/bin/env bash
# Assert aura-glass-glow manages specular rim light and halo stylesheets.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
GLOW_BIN="$REPO_ROOT/bin/aura-glass-glow"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help
[ -x "$GLOW_BIN" ] || note "bin/aura-glass-glow is not executable"
out_help="$("$GLOW_BIN" --help)" || note "aura-glass-glow --help failed"
[[ "$out_help" == *"aura-glass-glow"* ]] || note "--help missing aura-glass-glow"
[[ "$out_help" == *"subtle"* ]] || note "--help missing subtle style"
[[ "$out_help" == *"neon"* ]] || note "--help missing neon style"

# 2. Test status, enable, disable in isolated environment
TMP_DIR="$(mktemp -d /tmp/aura-glow-test-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

export XDG_CONFIG_HOME="$TMP_DIR/config"
mkdir -p "$XDG_CONFIG_HOME/aura-glass"

out_init_status="$("$GLOW_BIN" status)" || note "glow status failed"
[[ "$out_init_status" == *"disabled (off)"* ]] || note "initial status not off"

# Enable neon glow
"$GLOW_BIN" on --style neon >/dev/null 2>&1 || note "glow on --style neon failed"
[ -f "$XDG_CONFIG_HOME/aura-glass/glow" ] || note "glow flag file not created"
[ -f "$XDG_CONFIG_HOME/aura-glass/gtk4-glow.css" ] || note "gtk4-glow.css not created"
[ -f "$XDG_CONFIG_HOME/aura-glass/gtk3-glow.css" ] || note "gtk3-glow.css not created"

grep -q "box-shadow" "$XDG_CONFIG_HOME/aura-glass/gtk4-glow.css" || note "gtk4-glow.css missing box-shadow"
grep -q "window:focus" "$XDG_CONFIG_HOME/aura-glass/gtk4-glow.css" || note "gtk4-glow.css missing window:focus"

out_neon_status="$("$GLOW_BIN" status)" || note "glow status after enable failed"
[[ "$out_neon_status" == *"neon"* ]] || note "status does not reflect neon preset"

# Toggle off
"$GLOW_BIN" toggle >/dev/null 2>&1 || note "glow toggle failed"
[ ! -f "$XDG_CONFIG_HOME/aura-glass/glow" ] || note "glow flag not removed after toggle"

# Toggle on
"$GLOW_BIN" toggle >/dev/null 2>&1 || note "glow toggle back on failed"
[ -f "$XDG_CONFIG_HOME/aura-glass/glow" ] || note "glow flag not restored after toggle"

# Explicit off
"$GLOW_BIN" off >/dev/null 2>&1 || note "glow off failed"
[ ! -f "$XDG_CONFIG_HOME/aura-glass/glow" ] || note "glow flag not removed after off"

# 3. CLI delegation
out_cli="$("$CLI" glow --help)" || note "aura-glass glow delegation failed"
[[ "$out_cli" == *"aura-glass-glow"* ]] || note "CLI delegation missing aura-glass-glow"

if [ "$fail" -eq 1 ]; then
    printf 'check-glow.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-glow.sh: passed (specular rim & halo generation, toggles, & CLI verified)\n'
