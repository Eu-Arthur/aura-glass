#!/usr/bin/env bash
# aura-glass — unit tests for bash, zsh, and fish shell completions.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

pass() { printf '    \033[0;32m✓\033[0m %s\n' "$*"; }
fail() { printf '    \033[0;31m✗\033[0m %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

# 1. Syntax validations
if bash -n "$REPO_ROOT/completions/aura-glass.bash"; then
    pass "Bash completion syntax is valid (bash -n)"
else
    fail "Bash completion syntax check failed"
fi

if command -v zsh >/dev/null 2>&1; then
    if zsh -n "$REPO_ROOT/completions/_aura-glass"; then
        pass "Zsh completion syntax is valid (zsh -n)"
    else
        fail "Zsh completion syntax check failed"
    fi
else
    pass "Zsh not available in PATH (skipped zsh -n)"
fi

# 2. Verify file presence
for f in "completions/aura-glass.bash" "completions/_aura-glass" "completions/aura-glass.fish"; do
    if [ -s "$REPO_ROOT/$f" ]; then
        pass "Completion file exists and non-empty: $f"
    else
        fail "Missing completion file: $f"
    fi
done

# 3. Verify key options exist in Bash completion
for opt in "--accent" "--glass-mode" "--radius-preset" "--font" "--icons" "--cursors" \
           "aura-glass-backup" "aura-glass-mode" "aura-glass-doctor" "aura-glass-ext"; do
    if grep -q -- "$opt" "$REPO_ROOT/completions/aura-glass.bash"; then
        pass "Bash completion contains option: $opt"
    else
        fail "Bash completion missing option: $opt"
    fi
done

# 4. Verify key options exist in Zsh completion
for opt in "--accent" "--glass-mode" "--radius-preset" "--font" "--icons" "--cursors" \
           "aura-glass-backup" "aura-glass-mode" "aura-glass-doctor" "aura-glass-ext"; do
    if grep -q -- "$opt" "$REPO_ROOT/completions/_aura-glass"; then
        pass "Zsh completion contains option: $opt"
    else
        fail "Zsh completion missing option: $opt"
    fi
done

# 5. Verify key options exist in Fish completion
for opt in "accent" "glass-mode" "radius-preset" "font" "icons" "cursors" \
           "aura-glass-backup" "aura-glass-mode" "aura-glass-doctor" "aura-glass-ext"; do
    if grep -q -- "$opt" "$REPO_ROOT/completions/aura-glass.fish"; then
        pass "Fish completion contains option: $opt"
    else
        fail "Fish completion missing option: $opt"
    fi
done

# 6. Functional test: sourcing in a subshell
if (
    set +u
    # Mock complete builtin if needed or run directly
    source "$REPO_ROOT/completions/aura-glass.bash"
); then
    pass "Bash completion loads cleanly without runtime errors"
else
    fail "Bash completion raised an error when sourced"
fi

if [ "$FAILURES" -gt 0 ]; then
    printf '\nFailed %d checks.\n' "$FAILURES" >&2
    exit 1
fi

printf '\nAll shell completion checks passed.\n'
exit 0
