#!/usr/bin/env bash
# Assert aura-glass-browser handles Firefox profile discovery, userChrome.css, and lifecycle.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
BROWSER_BIN="$REPO_ROOT/bin/aura-glass-browser"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help
[ -x "$BROWSER_BIN" ] || note "bin/aura-glass-browser is not executable"
out_help="$("$BROWSER_BIN" --help)" || note "aura-glass-browser --help failed"
[[ "$out_help" == *"aura-glass-browser"* ]] || note "--help output missing command name"

# 2. Check snippet generation
out_snippet="$("$BROWSER_BIN" snippet)" || note "browser snippet failed"
[[ "$out_snippet" == *"Aura Glass — Frosted Glass Theme for Firefox"* ]] || note "missing header in snippet"
[[ "$out_snippet" == *"backdrop-filter: blur"* ]] || note "missing backdrop-filter in snippet"
[[ "$out_snippet" == *"var(--aura-glass-accent)"* ]] || note "missing accent variable in snippet"

# 3. Test in isolated environment with simulated Firefox profile
TEST_DIR="$(mktemp -d)"
export AURA_GLASS_CONF="$TEST_DIR/conf"
export MOZ_CONFIG_HOME="$TEST_DIR/mozilla/firefox"
mkdir -p "$AURA_GLASS_CONF" "$MOZ_CONFIG_HOME/mock.default-release"
touch "$MOZ_CONFIG_HOME/mock.default-release/prefs.js"
trap 'rm -rf "$TEST_DIR"' EXIT

# Set accent and radius tokens
printf 'red\n' > "$AURA_GLASS_CONF/accent"
printf 'soft\n' > "$AURA_GLASS_CONF/radius-preset"

# 4. Check status with profile present
out_status="$("$BROWSER_BIN" status)" || note "browser status failed"
[[ "$out_status" == *"mock.default-release"* ]] || note "mock profile not listed in status"

# 5. Check enable
"$BROWSER_BIN" firefox enable >/dev/null 2>&1 || note "firefox enable failed"
css_file="$MOZ_CONFIG_HOME/mock.default-release/chrome/userChrome.css"
[ -f "$css_file" ] || note "userChrome.css not generated"
grep -q "Aura Glass" "$css_file" || note "userChrome.css missing Aura Glass identifier"
grep -q "#e62d42" "$css_file" || note "userChrome.css missing red accent hex"
grep -q "16px" "$css_file" || note "userChrome.css missing soft 16px radius"

user_js="$MOZ_CONFIG_HOME/mock.default-release/user.js"
[ -f "$user_js" ] || note "user.js not created"
grep -q "toolkit.legacyUserProfileCustomizations.stylesheets" "$user_js" || note "missing pref in user.js"

# 6. Check backup creation on re-apply
"$BROWSER_BIN" firefox enable >/dev/null 2>&1 || note "second firefox enable failed"
[ -f "$css_file.aurabackup" ] || note "aurabackup file not created"

# 7. Check disable
"$BROWSER_BIN" firefox disable >/dev/null 2>&1 || note "firefox disable failed"
[ ! -f "$css_file.aurabackup" ] || note "aurabackup not restored"

# 8. Check CLI delegation via aura-glass
out_cli_browser="$("$CLI" browser status)" || note "aura-glass browser status delegation failed"
[[ "$out_cli_browser" == *"mock.default-release"* ]] || note "CLI browser delegation missing output"

if [ "$fail" -eq 1 ]; then
    printf 'check-browser.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-browser.sh: passed (profile detection, userChrome.css, & lifecycle verified)\n'
