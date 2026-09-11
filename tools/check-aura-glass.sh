#!/usr/bin/env bash
# Assert aura-glass unified CLI dispatches correctly to subcommands and handles status/help.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Executable and help
[ -x "$CLI" ] || note "bin/aura-glass is not executable"

out_help="$("$CLI" --help 2>&1)" || note "aura-glass --help failed"
[[ "$out_help" =~ "aura-glass <COMMAND>" ]] || note "--help output missing command usage"
[[ "$out_help" =~ "status" ]] || note "--help missing 'status' subcommand"
[[ "$out_help" =~ "doctor" ]] || note "--help missing 'doctor' subcommand"
[[ "$out_help" =~ "mode" ]] || note "--help missing 'mode' subcommand"

# Short -h
out_h="$("$CLI" -h 2>&1)" || note "aura-glass -h failed"
[[ "$out_h" =~ "aura-glass <COMMAND>" ]] || note "-h output missing usage"

# 2. Version
out_ver="$("$CLI" --version 2>&1)" || note "aura-glass --version failed"
[[ "$out_ver" =~ "aura-glass v" ]] || note "--version output missing version string"

out_ver_sub="$("$CLI" version 2>&1)" || note "aura-glass version failed"
[[ "$out_ver_sub" =~ "aura-glass v" ]] || note "'version' subcommand missing version string"

# 3. Status dashboard
out_status="$("$CLI" status 2>&1)" || note "aura-glass status failed"
[[ "$out_status" =~ "Aura Glass" ]] || note "status dashboard missing header"
[[ "$out_status" =~ "Glass Mode" ]] || note "status dashboard missing Glass Mode field"
[[ "$out_status" =~ "Shell Theme" ]] || note "status dashboard missing Shell Theme field"

# 4. Dispatching to subcommands
out_doctor="$("$CLI" doctor --quiet 2>&1 || true)"
[ -z "$out_doctor" ] || note "aura-glass doctor --quiet produced unexpected output: $out_doctor"

out_mode_help="$("$CLI" mode --help 2>&1)" || note "aura-glass mode --help failed"
[[ "$out_mode_help" =~ "aura-glass-mode" ]] || note "aura-glass mode didn't delegate to aura-glass-mode"

out_backup_help="$("$CLI" backup --help 2>&1)" || note "aura-glass backup --help failed"
[[ "$out_backup_help" =~ "aura-glass-backup" ]] || note "aura-glass backup didn't delegate to aura-glass-backup"

out_ext_help="$("$CLI" ext --help 2>&1)" || note "aura-glass ext --help failed"
[[ "$out_ext_help" =~ "aura-glass-ext" ]] || note "aura-glass ext didn't delegate to aura-glass-ext"

# 5. Accent commands
out_accent_get="$("$CLI" accent get 2>&1)" || note "aura-glass accent get failed"
[ -n "$out_accent_get" ] || note "aura-glass accent get returned empty output"

out_accent_json="$("$CLI" accent auto --json 2>&1)" || note "aura-glass accent auto --json failed"
[[ "$out_accent_json" =~ "\"accent\":" ]] || note "aura-glass accent auto --json missing 'accent' key"

# 6. Shortcut commands
out_shortcut_status="$("$CLI" shortcut status 2>&1)" || note "aura-glass shortcut status failed"
[[ "$out_shortcut_status" =~ "Keyboard Shortcuts" ]] || note "shortcut status missing header"

"$CLI" shortcut enable >/dev/null 2>&1 || note "aura-glass shortcut enable failed"
out_shortcut_en="$("$CLI" shortcut status 2>&1)" || note "aura-glass shortcut status after enable failed"
[[ "$out_shortcut_en" =~ "<Super><Alt>g" ]] || note "shortcut status missing enabled <Super><Alt>g"

"$CLI" shortcut disable >/dev/null 2>&1 || note "aura-glass shortcut disable failed"
out_shortcut_dis="$("$CLI" shortcut status 2>&1)" || note "aura-glass shortcut status after disable failed"
[[ "$out_shortcut_dis" =~ "not installed" ]] || note "shortcut status not showing 'not installed' after disable"

# 7. Unknown command error handling
set +e
err_out="$("$CLI" nonexistent-subcommand-xyz 2>&1)"
err_code=$?
set -e
[ "$err_code" -ne 0 ] || note "aura-glass nonexistent-subcommand-xyz should have exited with non-zero code"
[[ "$err_out" =~ "unknown command" ]] || note "error message missing 'unknown command'"

if [ "$fail" -eq 1 ]; then
    printf 'check-aura-glass.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-aura-glass.sh: passed (CLI dispatching & status verified)\n'
