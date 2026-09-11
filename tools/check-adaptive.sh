#!/usr/bin/env bash
# Assert aura-glass-adaptive handles circadian day/night phases and CLI delegation.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
ADAPTIVE_BIN="$REPO_ROOT/bin/aura-glass-adaptive"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help
[ -x "$ADAPTIVE_BIN" ] || note "bin/aura-glass-adaptive is not executable"
out_help="$("$ADAPTIVE_BIN" --help)" || note "aura-glass-adaptive --help failed"
[[ "$out_help" == *"aura-glass-adaptive"* ]] || note "--help output missing command name"

# 2. Test in isolated environment
TEST_CONF="$(mktemp -d)"
export AURA_GLASS_CONF="$TEST_CONF"
trap 'rm -rf "$TEST_CONF"' EXIT

# 3. Check status when disabled
out_status="$("$ADAPTIVE_BIN" status)" || note "adaptive status failed"
[[ "$out_status" == *"Circadian & Adaptive Glass Status"* ]] || note "missing status header"
[[ "$out_status" == *"disabled"* ]] || note "status not showing disabled"

# 4. Check enable with custom day and night profiles
"$ADAPTIVE_BIN" enable --day sonoma --night nordic >/dev/null 2>&1 || note "adaptive enable failed"
[ -f "$TEST_CONF/adaptive-mode" ] || note "adaptive-mode marker file not created"
[ -f "$TEST_CONF/adaptive-day" ] || note "adaptive-day file not created"
[ -f "$TEST_CONF/adaptive-night" ] || note "adaptive-night file not created"
[[ "$(cat "$TEST_CONF/adaptive-day")" == "sonoma" ]] || note "adaptive-day content incorrect"
[[ "$(cat "$TEST_CONF/adaptive-night")" == "nordic" ]] || note "adaptive-night content incorrect"

# 5. Check trigger commands
"$ADAPTIVE_BIN" trigger night >/dev/null 2>&1 || note "adaptive trigger night failed"
[ -f "$TEST_CONF/adaptive-phase" ] || note "adaptive-phase file not created"
[[ "$(cat "$TEST_CONF/adaptive-phase")" == "night" ]] || note "adaptive-phase is not night"

"$ADAPTIVE_BIN" trigger day >/dev/null 2>&1 || note "adaptive trigger day failed"
[[ "$(cat "$TEST_CONF/adaptive-phase")" == "day" ]] || note "adaptive-phase is not day"

# 6. Check sync command
out_sync="$("$ADAPTIVE_BIN" sync 2>&1)" || note "adaptive sync failed"
[ -n "$out_sync" ] || note "adaptive sync produced no output"

# 7. Check disable
"$ADAPTIVE_BIN" disable >/dev/null 2>&1 || note "adaptive disable failed"
[ ! -f "$TEST_CONF/adaptive-mode" ] || note "adaptive-mode file still exists after disable"

# 8. Check CLI delegation via aura-glass
out_cli_adaptive="$("$CLI" adaptive status)" || note "aura-glass adaptive status delegation failed"
[[ "$out_cli_adaptive" == *"Circadian & Adaptive Glass Status"* ]] || note "CLI adaptive status missing output"

if [ "$fail" -eq 1 ]; then
    printf 'check-adaptive.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-adaptive.sh: passed (adaptive phases, triggers, & CLI delegation verified)\n'
