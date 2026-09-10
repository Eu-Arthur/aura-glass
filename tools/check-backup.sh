#!/usr/bin/env bash
# aura-glass — unit tests for bin/aura-glass-backup.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO_ROOT/bin/aura-glass-backup"
FAILURES=0

pass() { printf '    \033[0;32m✓\033[0m %s\n' "$*"; }
fail() { printf '    \033[0;31m✗\033[0m %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aura-test-backup.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
export AURA_GLASS_DIR="$HOME/.config/aura-glass"
mkdir -p "$AURA_GLASS_DIR"

# 1. Help and basic argument handling
if "$BIN" --help >/dev/null 2>&1; then
    pass "Help command returns 0"
else
    fail "Help command failed"
fi

if "$BIN" >/dev/null 2>&1; then
    fail "Running without arguments should exit with error"
else
    pass "Running without arguments properly exits with error"
fi

# 2. Setup mock configuration
printf 'teal\n' > "$AURA_GLASS_DIR/accent"
printf 'transparent\n' > "$AURA_GLASS_DIR/glass-mode"
printf 'soft\n' > "$AURA_GLASS_DIR/radius-preset"

# 3. Test export
OUT_ARCHIVE="$TMP_DIR/test-profile.tar.gz"
if "$BIN" export "$OUT_ARCHIVE" >/dev/null 2>&1; then
    pass "Export profile created successfully"
else
    fail "Export profile failed"
fi

if [ -f "$OUT_ARCHIVE" ] && [ -s "$OUT_ARCHIVE" ]; then
    pass "Export archive exists and is non-empty"
else
    fail "Export archive is missing or empty"
fi

# 4. Test verify
if "$BIN" verify "$OUT_ARCHIVE" >/dev/null 2>&1; then
    pass "Verify recognizes valid archive"
else
    fail "Verify rejected valid archive"
fi

# 5. Test traversal / security protection
MALICIOUS_STAGE="$TMP_DIR/malicious_stage"
mkdir -p "$MALICIOUS_STAGE"
printf 'evil\n' > "$MALICIOUS_STAGE/payload"
MALICIOUS_TAR="$TMP_DIR/malicious.tar.gz"
# Create tar with relative ../ path
(
    cd "$TMP_DIR"
    tar -czf "$MALICIOUS_TAR" --transform 's|^malicious_stage|../escaped|' malicious_stage 2>/dev/null || \
    tar -czf "$MALICIOUS_TAR" malicious_stage
)

# Even if transform failed, create an archive with absolute /etc
if ! tar -tzf "$MALICIOUS_TAR" | grep -q '\.\./'; then
    # Force ../ entry using python tarfile
    python3 - <<PY
import tarfile, io
with tarfile.open('$MALICIOUS_TAR', 'w:gz') as tar:
    ti = tarfile.TarInfo('../escaped_file.txt')
    ti.size = 4
    tar.addfile(ti, io.BytesIO(b'test'))
PY
fi

if "$BIN" verify "$MALICIOUS_TAR" >/dev/null 2>&1; then
    fail "Security violation: verify accepted archive with path traversal"
else
    pass "Security check: verify correctly rejected path traversal"
fi

if "$BIN" import "$MALICIOUS_TAR" >/dev/null 2>&1; then
    fail "Security violation: import extracted archive with path traversal"
else
    pass "Security check: import correctly blocked path traversal"
fi

# 6. Test create and list
if "$BIN" create "custom_tag" >/dev/null 2>&1; then
    pass "Create backup with custom tag succeeded"
else
    fail "Create backup failed"
fi

LIST_OUT="$("$BIN" list)"
if printf '%s\n' "$LIST_OUT" | grep -q "custom_tag"; then
    pass "Backup listed in 'aura-glass-backup list'"
else
    fail "Backup not found in list output: $LIST_OUT"
fi

# 7. Test restore round-trip
# Modify current settings
printf 'red\n' > "$AURA_GLASS_DIR/accent"
printf 'solid\n' > "$AURA_GLASS_DIR/glass-mode"

if "$BIN" restore "$OUT_ARCHIVE" >/dev/null 2>&1; then
    pass "Restore executed without error"
else
    fail "Restore command failed"
fi

RESTORED_ACCENT="$(head -n 1 "$AURA_GLASS_DIR/accent" 2>/dev/null || echo "")"
RESTORED_MODE="$(head -n 1 "$AURA_GLASS_DIR/glass-mode" 2>/dev/null || echo "")"

if [ "$RESTORED_ACCENT" = "teal" ] && [ "$RESTORED_MODE" = "transparent" ]; then
    pass "Restore correctly recovered accent (teal) and mode (transparent)"
else
    fail "Restore data mismatch: accent='$RESTORED_ACCENT', mode='$RESTORED_MODE'"
fi

# 8. Check directory permissions
DIR_PERM="$(stat -c "%a" "$AURA_GLASS_DIR" 2>/dev/null || stat -f "%Lp" "$AURA_GLASS_DIR" 2>/dev/null || echo "")"
if [ "$DIR_PERM" = "700" ]; then
    pass "Restored directory permissions are secure (700)"
else
    fail "Directory permissions insecure: $DIR_PERM"
fi

if [ "$FAILURES" -gt 0 ]; then
    printf '\nFailed %d checks in aura-glass-backup.\n' "$FAILURES" >&2
    exit 1
fi

printf '\nAll aura-glass-backup tests passed.\n'
exit 0
