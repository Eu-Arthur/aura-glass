#!/usr/bin/env bash
# aura-glass — unified test runner.
#
# Runs syntax validation on all shell scripts, then runs all test suites under tools/.
# Returns exit code 0 if all tests pass, 1 if any fails.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$REPO_ROOT/tools"

C_BLD=$'\033[1m'
C_RED=$'\033[1;31m'
C_GRN=$'\033[1;32m'
C_YEL=$'\033[1;33m'
C_CYA=$'\033[1;36m'
C_DIM=$'\033[2m'
C_OFF=$'\033[0m'

printf '%s=== Aura Glass Test Suite ===%s\n\n' "$C_BLD" "$C_OFF"

total=0
passed=0
failed=0
start_time=$(date +%s)

run_test() {
    local label="$1"; shift
    local cmd=("$@")

    total=$((total + 1))
    printf '  %-35s ' "$label..."
    
    local out rc=0
    out="$("${cmd[@]}" 2>&1)" || rc=$?

    if [ "$rc" -eq 0 ]; then
        passed=$((passed + 1))
        printf '%s[ PASS ]%s\n' "$C_GRN" "$C_OFF"
    else
        failed=$((failed + 1))
        printf '%s[ FAIL ]%s (exit %s)\n' "$C_RED" "$C_OFF" "$rc"
        if [ -n "$out" ]; then
            printf '%s%s%s\n' "$C_DIM" "$out" "$C_OFF" | sed 's/^/    /'
        fi
    fi
}

# 1. Syntax and permissions checks
printf '%s[1/3] Syntax & Integrity Validation%s\n' "$C_CYA" "$C_OFF"
run_test "bash-syntax-all" bash -n "$REPO_ROOT/install.sh" "$REPO_ROOT/uninstall.sh" \
    "$REPO_ROOT"/lib/*.sh "$REPO_ROOT"/bin/* "$REPO_ROOT"/completions/*.bash \
    "$TOOLS_DIR"/*.sh "$TOOLS_DIR"/hooks/*

run_test "python-syntax-all" python3 -m py_compile "$REPO_ROOT"/gui/*.py "$TOOLS_DIR"/*.py

check_bin_executable() {
    local f missing=0
    for f in "$REPO_ROOT"/bin/*; do
        [ -f "$f" ] || continue
        if [ ! -x "$f" ]; then
            printf 'not executable: %s\n' "$f"
            missing=$((missing + 1))
        fi
    done
    return "$missing"
}
run_test "bin-executable-permissions" check_bin_executable

if command -v shellcheck >/dev/null 2>&1; then
    run_test "shellcheck-lint" shellcheck -x "$REPO_ROOT/install.sh" "$REPO_ROOT/uninstall.sh" "$REPO_ROOT"/bin/* "$REPO_ROOT"/lib/*.sh
fi

# 2. Shell test scripts
printf '\n%s[2/3] Shell Test Suites%s\n' "$C_CYA" "$C_OFF"
for t in "$TOOLS_DIR"/check-*.sh; do
    [ "${t##*/}" = "check-all.sh" ] && continue
    [ -f "$t" ] || continue
    run_test "${t##*/}" bash "$t"
done

# 3. Python test suites
printf '\n%s[3/3] Python Test Suites%s\n' "$C_CYA" "$C_OFF"
for t in "$TOOLS_DIR"/check-*.py; do
    [ -f "$t" ] || continue
    run_test "${t##*/}" python3 "$t"
done

end_time=$(date +%s)
duration=$((end_time - start_time))

printf '\n%s----------------------------------------%s\n' "$C_DIM" "$C_OFF"
if [ "$failed" -eq 0 ]; then
    printf '%sAll %d test suites passed in %ds!%s\n\n' "$C_GRN" "$total" "$duration" "$C_OFF"
    exit 0
else
    printf '%sTests failed: %d failed, %d passed out of %d in %ds.%s\n\n' "$C_RED" "$failed" "$passed" "$total" "$duration" "$C_OFF"
    exit 1
fi
