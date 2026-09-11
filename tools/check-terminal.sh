#!/usr/bin/env bash
# Assert aura-glass-terminal outputs correct config snippets and updates terminal configurations.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
TERM_BIN="$REPO_ROOT/bin/aura-glass-terminal"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help
[ -x "$TERM_BIN" ] || note "bin/aura-glass-terminal is not executable"
out_help="$("$TERM_BIN" --help)" || note "aura-glass-terminal --help failed"
[[ "$out_help" =~ "aura-glass-terminal" ]] || note "--help output missing command name"

# 2. Test status output
out_status="$("$TERM_BIN" status)" || note "terminal status failed"
[[ "$out_status" =~ "Modern Terminal Blur & Glass Integration" ]] || note "terminal status missing header"
[[ "$out_status" =~ "ghostty" ]] || note "terminal status missing ghostty"
[[ "$out_status" =~ "kitty" ]] || note "terminal status missing kitty"
[[ "$out_status" =~ "alacritty" ]] || note "terminal status missing alacritty"

# 3. Test snippet generation
snip_ghostty="$("$TERM_BIN" snippet ghostty frosted)" || note "snippet ghostty frosted failed"
[[ "$snip_ghostty" == *"background-opacity = 0.85"* ]] || note "wrong ghostty frosted opacity"
[[ "$snip_ghostty" == *"background-blur-radius = 20"* ]] || note "wrong ghostty frosted blur"

snip_ghostty_solid="$("$TERM_BIN" snippet ghostty solid)" || note "snippet ghostty solid failed"
[[ "$snip_ghostty_solid" == *"background-opacity = 1.00"* ]] || note "wrong ghostty solid opacity"
[[ "$snip_ghostty_solid" == *"background-blur-radius = 0"* ]] || note "wrong ghostty solid blur"

snip_kitty="$("$TERM_BIN" snippet kitty frosted)" || note "snippet kitty frosted failed"
[[ "$snip_kitty" == *"background_opacity 0.85"* ]] || note "wrong kitty frosted opacity"
[[ "$snip_kitty" == *"background_blur 20"* ]] || note "wrong kitty frosted blur"

snip_alacritty="$("$TERM_BIN" snippet alacritty frosted)" || note "snippet alacritty frosted failed"
[[ "$snip_alacritty" == *"opacity = 0.85"* ]] || note "wrong alacritty frosted opacity"
[[ "$snip_alacritty" == *"blur = true"* ]] || note "wrong alacritty frosted blur"

snip_alacritty_solid="$("$TERM_BIN" snippet alacritty solid)" || note "snippet alacritty solid failed"
[[ "$snip_alacritty_solid" == *"blur = false"* ]] || note "wrong alacritty solid blur"

# 4. Test apply in isolated environment
TEST_CONF="$(mktemp -d)"
export AURA_GLASS_CONF="$TEST_CONF"
export XDG_CONFIG_HOME="$TEST_CONF/config"
mkdir -p "$XDG_CONFIG_HOME"
trap 'rm -rf "$TEST_CONF"' EXIT

"$TERM_BIN" apply ghostty >/dev/null 2>&1 || note "terminal apply ghostty failed"
ghostty_conf="$XDG_CONFIG_HOME/ghostty/config"
[ -f "$ghostty_conf" ] || note "ghostty config file not created"
grep -q "background-opacity = 0.85" "$ghostty_conf" || note "missing opacity in ghostty config"

# Test backup generation on second apply
"$TERM_BIN" apply ghostty >/dev/null 2>&1 || note "second terminal apply ghostty failed"
[ -f "$ghostty_conf.aurabackup" ] || note "backup file not created on re-apply"

# 5. Check CLI delegation via aura-glass
out_cli_term="$("$CLI" terminal status)" || note "aura-glass terminal status delegation failed"
[[ "$out_cli_term" =~ "Modern Terminal Blur & Glass Integration" ]] || note "CLI terminal status missing output"

if [ "$fail" -eq 1 ]; then
    printf 'check-terminal.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-terminal.sh: passed (terminal snippets, apply, backups, & CLI delegation verified)\n'
