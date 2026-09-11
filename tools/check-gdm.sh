#!/usr/bin/env bash
# aura-glass — unit tests for GDM fallback handling and wallpaper resolution.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

pass() { printf '    \033[0;32m✓\033[0m %s\n' "$*"; }
fail() { printf '    \033[0;31m✗\033[0m %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aura-test-gdm.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
export CONF_DIR="$HOME/.config/aura-glass"
export SRC_CACHE="$HOME/.cache/aura-glass/src"
mkdir -p "$CONF_DIR" "$SRC_CACHE"

# Source common helpers and distro detection
# shellcheck source=lib/common.sh
. "$REPO_ROOT/lib/common.sh"
# shellcheck source=lib/distro.sh
. "$REPO_ROOT/lib/distro.sh"
DISTRO_FAMILY="debian"

# Source GDM steps
# shellcheck source=lib/steps-gdm.sh
. "$REPO_ROOT/lib/steps-gdm.sh"

# 1. detect_gdm_theme_files returns a valid string
gdm_theme_file="$(detect_gdm_theme_files)"
if [ -n "$gdm_theme_file" ]; then
    pass "detect_gdm_theme_files returned: $gdm_theme_file"
else
    fail "detect_gdm_theme_files returned empty string"
fi

# 2. Procedural fallback generation produces valid PNG
procedural_dst="$TMP_DIR/procedural-test.png"
if generate_gdm_wallpaper "procedural" "$procedural_dst"; then
    if [ -s "$procedural_dst" ] && python3 -c "from PIL import Image; im = Image.open('$procedural_dst'); assert im.format == 'PNG' and im.size == (2560, 1440)" 2>/dev/null; then
        pass "generate_gdm_wallpaper procedural creates valid 2560x1440 PNG"
    else
        fail "generate_gdm_wallpaper procedural produced invalid or empty file"
    fi
else
    fail "generate_gdm_wallpaper procedural execution failed"
fi

# 3. XML slideshow resolution and fallback
dummy_img="$TMP_DIR/dummy_sample.png"
# Create a small valid test image using python
python3 -c "from PIL import Image; Image.new('RGB', (100, 100), color=(100, 150, 200)).save('$dummy_img')"

dummy_xml="$TMP_DIR/slideshow.xml"
cat > "$dummy_xml" <<EOF
<background>
  <static>
    <duration>1795.0</duration>
    <file>$dummy_img</file>
  </static>
</background>
EOF

xml_dst="$TMP_DIR/xml-output.png"
if generate_gdm_wallpaper "$dummy_xml" "$xml_dst"; then
    if [ -s "$xml_dst" ] && python3 -c "from PIL import Image; im = Image.open('$xml_dst'); assert im.format == 'PNG' and im.size == (2560, 1440)" 2>/dev/null; then
        pass "generate_gdm_wallpaper correctly resolves XML slideshow and outputs blurred PNG"
    else
        fail "generate_gdm_wallpaper XML resolution produced invalid file"
    fi
else
    fail "generate_gdm_wallpaper failed with XML slideshow"
fi

# 4. resolve_gdm_wallpaper_source with explicit background
custom_bg="$TMP_DIR/custom_bg.png"
cp -f "$dummy_img" "$custom_bg"
src_resolved="$(resolve_gdm_wallpaper_source "$custom_bg")"
if [ "$src_resolved" = "$custom_bg" ]; then
    pass "resolve_gdm_wallpaper_source honors explicit custom background"
else
    fail "resolve_gdm_wallpaper_source expected '$custom_bg', got '$src_resolved'"
fi

# 5. resolve_gdm_wallpaper_source with invalid explicit background falls back
src_invalid="$(resolve_gdm_wallpaper_source "/nonexistent/path/aura_fake.jpg")"
if [ "$src_invalid" != "/nonexistent/path/aura_fake.jpg" ] && [ -n "$src_invalid" ]; then
    pass "resolve_gdm_wallpaper_source falls back when explicit path does not exist"
else
    fail "resolve_gdm_wallpaper_source did not fall back for missing path"
fi

# 6. Dry run safety of install_gdm
DRY_RUN=1
WANT_GDM_MONITORS=0
if install_gdm "default" >/dev/null 2>&1; then
    pass "install_gdm executes cleanly in DRY_RUN mode"
else
    fail "install_gdm failed in DRY_RUN mode"
fi

# 7. Dry run safety of uninstall_gdm
if uninstall_gdm >/dev/null 2>&1; then
    pass "uninstall_gdm executes cleanly in DRY_RUN mode"
else
    fail "uninstall_gdm failed in DRY_RUN mode"
fi

if [ "$FAILURES" -gt 0 ]; then
    printf '\nFailed %d checks in check-gdm.sh.\n' "$FAILURES" >&2
    exit 1
fi
