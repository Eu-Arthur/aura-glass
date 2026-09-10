#!/usr/bin/env bash
# Assert aura-glass-doctor outputs valid diagnostics and JSON.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$REPO_ROOT/bin/aura-glass-doctor"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help flag
[ -x "$DOCTOR" ] || note "bin/aura-glass-doctor is not executable"
out_help="$("$DOCTOR" --help)" || note "aura-glass-doctor --help failed"
[[ "$out_help" =~ "aura-glass-doctor" ]] || note "--help output missing command name"

# 2. Check JSON mode
json_out="$("$DOCTOR" --json 2>/dev/null || true)"
[ -n "$json_out" ] || note "aura-glass-doctor --json produced empty output"

# Validate JSON parsing and schema with python
printf '%s' "$json_out" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert "summary" in data, "missing summary in doctor JSON"
assert "checks" in data, "missing checks in doctor JSON"
assert "ok" in data["summary"], "missing ok count"
assert isinstance(data["checks"], list), "checks must be a list"
for c in data["checks"]:
    assert "name" in c and "status" in c, f"invalid check item: {c}"
' || note "doctor JSON schema validation failed"

# 3. Check install.sh --doctor delegation
out_install_help="$("$REPO_ROOT/install.sh" --doctor --help 2>&1)" || note "install.sh --doctor --help failed"
[[ "$out_install_help" =~ "aura-glass-doctor" ]] || note "install.sh --doctor did not delegate to doctor"

# 4. Check quiet flag
quiet_out="$("$DOCTOR" --quiet 2>&1 || true)"
[ -z "$quiet_out" ] || note "aura-glass-doctor --quiet produced unexpected output: $quiet_out"

if [ "$fail" -eq 1 ]; then
    printf 'check-doctor.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-doctor.sh: passed (JSON schema & delegation verified)\n'
