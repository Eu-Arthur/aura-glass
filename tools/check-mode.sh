#!/usr/bin/env bash
# aura-glass — unit tests for bin/aura-glass-mode.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO_ROOT/bin/aura-glass-mode"
FAILURES=0

pass() { printf '    \033[0;32m✓\033[0m %s\n' "$*"; }
fail() { printf '    \033[0;31m✗\033[0m %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aura-test-mode.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
export AURA_GLASS_DIR="$HOME/.config/aura-glass"
mkdir -p "$AURA_GLASS_DIR"

# Mock notify-send
MOCK_BIN="$TMP_DIR/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$HOME/notifications.log"
EOF
chmod +x "$MOCK_BIN/notify-send"
export PATH="$MOCK_BIN:$PATH"

# 1. Help check
if "$BIN" --help >/dev/null 2>&1; then
    pass "Help command returns 0"
else
    fail "Help command failed"
fi

# 2. Initial state (defaults to frosted)
INITIAL="$("$BIN")"
if [ "$INITIAL" = "frosted" ]; then
    pass "Default glass mode is frosted"
else
    fail "Initial mode expected 'frosted', got '$INITIAL'"
fi

# 3. Set mode to transparent
"$BIN" set transparent >/dev/null 2>&1
CUR="$("$BIN" get)"
if [ "$CUR" = "transparent" ] && [ ! -f "$AURA_GLASS_DIR/styling-off" ]; then
    pass "Set mode to transparent succeeded"
else
    fail "Set mode transparent failed: current='$CUR'"
fi

# 4. Set mode directly via shorthand (solid)
"$BIN" solid >/dev/null 2>&1
CUR="$("$BIN")"
if [ "$CUR" = "solid" ] && [ -f "$AURA_GLASS_DIR/styling-off" ]; then
    pass "Set mode to solid succeeded and created styling-off marker"
else
    fail "Set mode solid failed: current='$CUR'"
fi

# 5. Toggle cycling
# Currently solid -> next should be frosted
"$BIN" toggle >/dev/null 2>&1
CUR="$("$BIN")"
if [ "$CUR" = "frosted" ] && [ ! -f "$AURA_GLASS_DIR/styling-off" ]; then
    pass "Toggle from solid transitioned to frosted"
else
    fail "Toggle failed: expected frosted, got '$CUR'"
fi

# Frosted -> next should be transparent
"$BIN" toggle >/dev/null 2>&1
CUR="$("$BIN")"
if [ "$CUR" = "transparent" ]; then
    pass "Toggle from frosted transitioned to transparent"
else
    fail "Toggle failed: expected transparent, got '$CUR'"
fi

# Transparent -> next should be solid
"$BIN" toggle >/dev/null 2>&1
CUR="$("$BIN")"
if [ "$CUR" = "solid" ]; then
    pass "Toggle from transparent transitioned to solid"
else
    fail "Toggle failed: expected solid, got '$CUR'"
fi

# 6. Reject invalid modes
if "$BIN" set ultra-opaque >/dev/null 2>&1; then
    fail "Set unknown mode should have failed"
else
    pass "Set unknown mode properly rejected"
fi

# 7. Notification dispatch test
"$BIN" frosted --notify >/dev/null 2>&1
if [ -f "$HOME/notifications.log" ] && grep -qi "frosted" "$HOME/notifications.log"; then
    pass "Desktop notification was dispatched via notify-send"
else
    fail "Notification not found in notifications.log"
fi

if [ "$FAILURES" -gt 0 ]; then
    printf '\nFailed %d checks in aura-glass-mode.\n' "$FAILURES" >&2
    exit 1
fi

printf '\nAll aura-glass-mode tests passed.\n'
exit 0
