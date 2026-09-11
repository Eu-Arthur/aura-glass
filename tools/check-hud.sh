#!/usr/bin/env bash
# Assert aura-glass-hud triggers visual HUD toasts and OSD rules are present.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
HUD_BIN="$REPO_ROOT/bin/aura-glass-hud"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help
[ -x "$HUD_BIN" ] || note "bin/aura-glass-hud is not executable"
out_help="$("$HUD_BIN" --help)" || note "aura-glass-hud --help failed"
[[ "$out_help" == *"aura-glass-hud"* ]] || note "--help missing aura-glass-hud"
[[ "$out_help" == *"toast"* ]] || note "--help missing toast command"
[[ "$out_help" == *"mode"* ]] || note "--help missing mode command"

# 2. Check status output
out_status="$("$HUD_BIN" status)" || note "hud status failed"
[[ "$out_status" == *"Aura Glass HUD & OSD Status"* ]] || note "status output missing header"
[[ "$out_status" == *"VisionOS Pill OSD"* ]] || note "status output missing VisionOS Pill OSD indicator"

# 3. Test toast execution
out_toast="$("$HUD_BIN" toast "Workspace Switch" "Switched to Workspace 2" 2>&1)" || note "hud toast failed"
[[ "$out_toast" == *"[AURA GLASS HUD]"* ]] || note "hud toast output missing HUD indicator"
[[ "$out_toast" == *"Workspace Switch"* ]] || note "hud toast missing title"

# 4. Test mode, accent, profile, glow toasts
out_mode="$("$HUD_BIN" mode 2>&1)" || note "hud mode failed"
[[ "$out_mode" == *"Aura Glass Mode"* ]] || note "hud mode missing title"

out_accent="$("$HUD_BIN" accent 2>&1)" || note "hud accent failed"
[[ "$out_accent" == *"Aura Glass Accent"* ]] || note "hud accent missing title"

out_profile="$("$HUD_BIN" profile 2>&1)" || note "hud profile failed"
[[ "$out_profile" == *"Aura Glass Profile"* ]] || note "hud profile missing title"

out_glow="$("$HUD_BIN" glow 2>&1)" || note "hud glow failed"
[[ "$out_glow" == *"Aura Glass Window Glow"* ]] || note "hud glow missing title"

# 5. Check OSD CSS rule in shell-50-dialogs.css
grep -q "\.osd-window" "$REPO_ROOT/css/shell-50-dialogs.css" || note "missing .osd-window rule in shell-50-dialogs.css"

# 6. Check CLI delegation
out_cli="$("$CLI" hud --help)" || note "aura-glass hud delegation failed"
[[ "$out_cli" == *"aura-glass-hud"* ]] || note "CLI delegation missing aura-glass-hud"

if [ "$fail" -eq 1 ]; then
    printf 'check-hud.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-hud.sh: passed (HUD toasts, mode/accent triggers, & OSD CSS verified)\n'
