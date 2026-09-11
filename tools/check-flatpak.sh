#!/usr/bin/env bash
# Assert aura-glass-flatpak manages sandbox stylesheets and integrates with CLI.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
FLATPAK_BIN="$REPO_ROOT/bin/aura-glass-flatpak"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help
[ -x "$FLATPAK_BIN" ] || note "bin/aura-glass-flatpak is not executable"
out_help="$("$FLATPAK_BIN" --help)" || note "aura-glass-flatpak --help failed"
[[ "$out_help" == *"aura-glass-flatpak"* ]] || note "--help missing aura-glass-flatpak"
[[ "$out_help" == *"sync"* ]] || note "--help missing sync command"
[[ "$out_help" == *"revert"* ]] || note "--help missing revert command"

# 2. Test in isolated environment
TMP_DIR="$(mktemp -d /tmp/aura-flatpak-test-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

export AURA_GLASS_FLATPAK_VAR="$TMP_DIR/var/app"
export XDG_CONFIG_HOME="$TMP_DIR/config"

# Create mock GTK source styles
mkdir -p "$XDG_CONFIG_HOME/gtk-4.0" "$XDG_CONFIG_HOME/gtk-3.0"
printf '/* Mock GTK 4 */\nwindow { background-color: rgba(0,0,0,0.5); }\n' > "$XDG_CONFIG_HOME/gtk-4.0/gtk.css"
printf '/* Mock GTK 3 */\nwindow { background-color: rgba(0,0,0,0.5); }\n' > "$XDG_CONFIG_HOME/gtk-3.0/gtk.css"

# Create mock Flatpak apps
mkdir -p "$AURA_GLASS_FLATPAK_VAR/org.mozilla.firefox"
mkdir -p "$AURA_GLASS_FLATPAK_VAR/org.gnome.TextEditor"

# Status initial
out_status_init="$("$FLATPAK_BIN" status)" || note "flatpak status init failed"
[[ "$out_status_init" == *"2 detected"* ]] || note "initial app count incorrect"
[[ "$out_status_init" == *"0 / 2"* ]] || note "initial themed count incorrect"

# Sync
"$FLATPAK_BIN" sync >/dev/null 2>&1 || note "flatpak sync failed"

[ -L "$AURA_GLASS_FLATPAK_VAR/org.mozilla.firefox/config/gtk-4.0/gtk.css" ] || note "Firefox GTK4 symlink not created"
[ -L "$AURA_GLASS_FLATPAK_VAR/org.mozilla.firefox/config/gtk-3.0/gtk.css" ] || note "Firefox GTK3 symlink not created"
[ -L "$AURA_GLASS_FLATPAK_VAR/org.gnome.TextEditor/config/gtk-4.0/gtk.css" ] || note "TextEditor GTK4 symlink not created"

# Status after sync
out_status_synced="$("$FLATPAK_BIN" status)" || note "flatpak status after sync failed"
[[ "$out_status_synced" == *"2 / 2"* ]] || note "synced count incorrect"

# Revert
"$FLATPAK_BIN" revert >/dev/null 2>&1 || note "flatpak revert failed"
[ ! -L "$AURA_GLASS_FLATPAK_VAR/org.mozilla.firefox/config/gtk-4.0/gtk.css" ] || note "Firefox GTK4 symlink not removed"
[ ! -L "$AURA_GLASS_FLATPAK_VAR/org.gnome.TextEditor/config/gtk-4.0/gtk.css" ] || note "TextEditor GTK4 symlink not removed"

# 3. Check CLI delegation
out_cli="$("$CLI" flatpak --help)" || note "aura-glass flatpak delegation failed"
[[ "$out_cli" == *"aura-glass-flatpak"* ]] || note "CLI delegation missing aura-glass-flatpak"

if [ "$fail" -eq 1 ]; then
    printf 'check-flatpak.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-flatpak.sh: passed (Flatpak sandbox CSS syncing, revert, & CLI verified)\n'
