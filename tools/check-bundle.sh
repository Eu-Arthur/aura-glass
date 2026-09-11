#!/usr/bin/env bash
# Assert aura-glass-bundle archives, inspects, and restores theme bundles.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
BUNDLE_BIN="$REPO_ROOT/bin/aura-glass-bundle"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help
[ -x "$BUNDLE_BIN" ] || note "bin/aura-glass-bundle is not executable"
out_help="$("$BUNDLE_BIN" --help)" || note "aura-glass-bundle --help failed"
[[ "$out_help" == *"aura-glass-bundle"* ]] || note "--help missing aura-glass-bundle"
[[ "$out_help" == *"export"* ]] || note "--help missing export command"
[[ "$out_help" == *"apply"* ]] || note "--help missing apply command"
[[ "$out_help" == *"inspect"* ]] || note "--help missing inspect command"

TMP_BASE="${XDG_RUNTIME_DIR:-/tmp}"
TMP_DIR="$(mktemp -d "$TMP_BASE/aura-bundle-test-XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

export AURA_GLASS_CONF="$TMP_DIR/config/aura-glass"
mkdir -p "$AURA_GLASS_CONF"

printf 'purple\n' > "$AURA_GLASS_CONF/accent"
printf 'visionos\n' > "$AURA_GLASS_CONF/current-profile"
printf 'neon\n' > "$AURA_GLASS_CONF/glow"

test_bundle="$TMP_DIR/my-ice.auraglass"

# Export bundle
"$BUNDLE_BIN" export "$test_bundle" --name "Nordic Ice" --author "Arthur" >/dev/null 2>&1 || note "bundle export failed"
[ -f "$test_bundle" ] || note "exported bundle file not created"

# Inspect bundle
out_inspect="$("$BUNDLE_BIN" inspect "$test_bundle")" || note "bundle inspect failed"
[[ "$out_inspect" == *"Nordic Ice"* ]] || note "inspect missing bundle name"
[[ "$out_inspect" == *"Arthur"* ]] || note "inspect missing author"
[[ "$out_inspect" == *"purple"* ]] || note "inspect missing accent color"
[[ "$out_inspect" == *"neon"* ]] || note "inspect missing glow style"

# Test export to default bundles dir and list
"$BUNDLE_BIN" export --name "Saved Setup" >/dev/null 2>&1 || note "bundle default export failed"
out_list="$("$BUNDLE_BIN" list)" || note "bundle list failed"
[[ "$out_list" == *"saved-setup.auraglass"* ]] || note "bundle list missing exported bundle"

# Test apply in a new isolated config directory
APPLY_CONF="$TMP_DIR/apply-config/aura-glass"
mkdir -p "$APPLY_CONF"

AURA_GLASS_CONF="$APPLY_CONF" "$BUNDLE_BIN" apply "$test_bundle" >/dev/null 2>&1 || note "bundle apply failed"
[ -f "$APPLY_CONF/glow" ] || note "glow setting not restored during apply"
grep -q "neon" "$APPLY_CONF/glow" || note "glow setting value incorrect after apply"

# 3. Check CLI delegation
out_cli="$("$CLI" bundle --help)" || note "aura-glass bundle delegation failed"
[[ "$out_cli" == *"aura-glass-bundle"* ]] || note "CLI delegation missing aura-glass-bundle"

if [ "$fail" -eq 1 ]; then
    printf 'check-bundle.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-bundle.sh: passed (bundle packaging, inspect, apply, & CLI verified)\n'
