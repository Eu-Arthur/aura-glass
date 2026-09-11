#!/usr/bin/env bash
# Assert aura-glass-wallpaper generates procedural wallpapers and integrates with CLI.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
WALLPAPER_BIN="$REPO_ROOT/bin/aura-glass-wallpaper"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help
[ -x "$WALLPAPER_BIN" ] || note "bin/aura-glass-wallpaper is not executable"
out_help="$("$WALLPAPER_BIN" --help)" || note "aura-glass-wallpaper --help failed"
[[ "$out_help" == *"aura-glass-wallpaper"* ]] || note "--help output missing command name"
[[ "$out_help" == *"--mesh"* ]] || note "--help missing --mesh option"
[[ "$out_help" == *"--aurora"* ]] || note "--help missing --aurora option"
[[ "$out_help" == *"--obsidian"* ]] || note "--help missing --obsidian option"

# 2. Test procedural generation with test resolution (fast)
TMP_DIR="$(mktemp -d /tmp/aura-wallpaper-test-XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

mesh_img="$TMP_DIR/mesh.png"
"$WALLPAPER_BIN" generate --mesh --accent purple --width 480 --height 270 --output "$mesh_img" >/dev/null 2>&1 || note "mesh wallpaper generation failed"
[ -f "$mesh_img" ] || note "mesh wallpaper file not created"

aurora_img="$TMP_DIR/aurora.png"
"$WALLPAPER_BIN" generate --aurora --accent teal --width 480 --height 270 --output "$aurora_img" >/dev/null 2>&1 || note "aurora wallpaper generation failed"
[ -f "$aurora_img" ] || note "aurora wallpaper file not created"

obsidian_img="$TMP_DIR/obsidian.png"
"$WALLPAPER_BIN" generate --obsidian --accent blue --width 480 --height 270 --output "$obsidian_img" >/dev/null 2>&1 || note "obsidian wallpaper generation failed"
[ -f "$obsidian_img" ] || note "obsidian wallpaper file not created"

# 3. Validate image dimensions and format via Pillow
python3 -c "
from PIL import Image
for path, w, h in [('$mesh_img', 480, 270), ('$aurora_img', 480, 270), ('$obsidian_img', 480, 270)]:
    with Image.open(path) as im:
        assert im.format == 'PNG', f'{path} format is {im.format}, expected PNG'
        assert im.size == (w, h), f'{path} size is {im.size}, expected ({w}, {h})'
" || note "Generated wallpaper image validation failed"

# 4. Check CLI delegation via aura-glass
out_cli="$("$CLI" wallpaper --help)" || note "aura-glass wallpaper delegation failed"
[[ "$out_cli" == *"aura-glass-wallpaper"* ]] || note "CLI delegation output missing aura-glass-wallpaper"

if [ "$fail" -eq 1 ]; then
    printf 'check-wallpaper.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-wallpaper.sh: passed (mesh, aurora, obsidian generation & CLI verified)\n'
