#!/usr/bin/env bash
# Assert aura-glass-profile functions correctly with built-in and custom profiles.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
PROFILE_BIN="$REPO_ROOT/bin/aura-glass-profile"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Executable permissions & help
[ -x "$PROFILE_BIN" ] || note "bin/aura-glass-profile is not executable"
out_help="$("$PROFILE_BIN" --help)" || note "aura-glass profile --help failed"
[[ "$out_help" =~ "aura-glass-profile" ]] || note "--help output missing command name"

# 2. Test in isolated environment
TEST_CONF="$(mktemp -d)"
export AURA_GLASS_CONF="$TEST_CONF"
trap 'rm -rf "$TEST_CONF"' EXIT

# 3. Test profile listing (human and JSON)
out_list="$("$PROFILE_BIN" list)" || note "profile list failed"
[[ "$out_list" =~ "sonoma" ]] || note "missing sonoma in profile list"
[[ "$out_list" =~ "visionos" ]] || note "missing visionos in profile list"
[[ "$out_list" =~ "nordic" ]] || note "missing nordic in profile list"

json_list="$("$PROFILE_BIN" list --json)" || note "profile list --json failed"
printf '%s' "$json_list" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert "profiles" in data, "missing profiles key"
ids = [p["id"] for p in data["profiles"]]
assert "sonoma" in ids and "visionos" in ids and "cyberpunk" in ids, f"missing expected profiles in {ids}"
' || note "profile list --json schema invalid"

# 4. Test current command
out_current="$("$PROFILE_BIN" current)" || note "profile current failed"
[[ "$out_current" =~ "Active Atmosphere Profile" ]] || note "missing header in profile current"

json_current="$("$PROFILE_BIN" current --json)" || note "profile current --json failed"
printf '%s' "$json_current" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert "mode" in data and "radius" in data and "profile" in data
' || note "profile current --json schema invalid"

# 5. Test apply built-in profile
"$PROFILE_BIN" apply sonoma >/dev/null 2>&1 || note "profile apply sonoma failed"
[ -f "$TEST_CONF/current-profile" ] || note "current-profile file not written"
[[ "$(cat "$TEST_CONF/current-profile")" = "sonoma" ]] || note "current-profile is not sonoma"
[[ "$(cat "$TEST_CONF/radius-preset")" = "soft" ]] || note "radius-preset not updated to soft for sonoma"

# 6. Test save custom profile
"$PROFILE_BIN" save my-preset --description "My custom preset" >/dev/null 2>&1 || note "profile save failed"
[ -f "$TEST_CONF/profiles/my-preset.json" ] || note "saved profile json not created"

# 7. Test export & import
out_export="$("$PROFILE_BIN" export my-preset)" || note "profile export failed"
[[ "$out_export" =~ "my-preset" ]] || note "exported content missing profile name"

export_file="$TEST_CONF/export.json"
"$PROFILE_BIN" export my-preset "$export_file" >/dev/null 2>&1 || note "profile export to file failed"
[ -f "$export_file" ] || note "exported file not created"

"$PROFILE_BIN" remove my-preset >/dev/null 2>&1 || note "profile remove failed"
[ ! -f "$TEST_CONF/profiles/my-preset.json" ] || note "profile file still exists after removal"

"$PROFILE_BIN" import "$export_file" >/dev/null 2>&1 || note "profile import failed"
[ -f "$TEST_CONF/profiles/export.json" ] || [ -f "$TEST_CONF/profiles/my-preset.json" ] || note "imported profile not restored"

# 8. Test dispatcher delegation via aura-glass
out_cli_prof="$("$CLI" profile current)" || note "aura-glass profile current delegation failed"
[[ "$out_cli_prof" =~ "Active Atmosphere Profile" ]] || note "CLI profile delegation missing output"

if [ "$fail" -eq 1 ]; then
    printf 'check-profile.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-profile.sh: passed (profiles CRUD, JSON, & CLI integration verified)\n'
