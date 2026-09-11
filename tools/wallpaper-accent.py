#!/usr/bin/env python3
"""
aura-glass — dynamic wallpaper accent color extractor.

Analyzes the current or given desktop wallpaper image, quantizes dominant colors
in HSV space, and maps the harmonious dominant tone to one of GNOME's 9 native
accent colors (blue, teal, green, yellow, orange, red, pink, purple, slate).
"""

import sys
import os
import argparse
import json
import urllib.parse
import subprocess
import colorsys

ACCENTS = {
    'purple': {'hex': '#9141ac', 'rgb': (0x91, 0x41, 0xac)},
    'blue':   {'hex': '#3584e4', 'rgb': (0x35, 0x84, 0xe4)},
    'teal':   {'hex': '#2190a4', 'rgb': (0x21, 0x90, 0xa4)},
    'green':  {'hex': '#3a944a', 'rgb': (0x3a, 0x94, 0x4a)},
    'yellow': {'hex': '#c88800', 'rgb': (0xc8, 0x88, 0x00)},
    'orange': {'hex': '#ed5b00', 'rgb': (0xed, 0x5b, 0x00)},
    'red':    {'hex': '#e62d42', 'rgb': (0xe6, 0x2d, 0x42)},
    'pink':   {'hex': '#d56199', 'rgb': (0xd5, 0x61, 0x99)},
    'slate':  {'hex': '#6f8396', 'rgb': (0x6f, 0x83, 0x96)},
}

def classify_hue(h_deg, s, v):
    """Classify hue degree and saturation into GNOME accent keywords."""
    if s < 0.14 or v < 0.10:
        return 'slate'
    if 345 <= h_deg or h_deg < 15:
        return 'red'
    elif 15 <= h_deg < 45:
        return 'orange'
    elif 45 <= h_deg < 70:
        return 'yellow'
    elif 70 <= h_deg < 155:
        return 'green'
    elif 155 <= h_deg < 195:
        return 'teal'
    elif 195 <= h_deg < 250:
        return 'blue'
    elif 250 <= h_deg < 295:
        return 'purple'
    elif 295 <= h_deg < 345:
        return 'pink'
    return 'slate'

def get_current_wallpaper_path():
    """Retrieve active wallpaper path from GNOME GSettings."""
    try:
        scheme_out = subprocess.check_output(
            ['gsettings', 'get', 'org.gnome.desktop.interface', 'color-scheme'],
            text=True, stderr=subprocess.DEVNULL
        ).strip().strip("'")
    except Exception:
        scheme_out = 'default'

    key = 'picture-uri-dark' if 'dark' in scheme_out else 'picture-uri'
    uri = ''
    try:
        uri = subprocess.check_output(
            ['gsettings', 'get', 'org.gnome.desktop.background', key],
            text=True, stderr=subprocess.DEVNULL
        ).strip().strip("'")
    except Exception:
        pass

    if not uri or uri == "''":
        try:
            uri = subprocess.check_output(
                ['gsettings', 'get', 'org.gnome.desktop.background', 'picture-uri'],
                text=True, stderr=subprocess.DEVNULL
            ).strip().strip("'")
        except Exception:
            pass

    if uri:
        parsed = urllib.parse.urlparse(uri)
        if parsed.scheme in ('file', ''):
            path = urllib.parse.unquote(parsed.path)
            if os.path.isfile(path):
                return path

    return None

def extract_accent_from_image(image_path):
    """Open image, quantize palette and compute dominant GNOME accent."""
    try:
        from PIL import Image
    except ImportError:
        return 'blue', {'error': 'PIL/Pillow not installed; defaulting to blue'}

    if not image_path or not os.path.isfile(image_path):
        return 'blue', {'error': f'Wallpaper file not found: {image_path}'}

    try:
        with Image.open(image_path) as img:
            rgb_img = img.convert('RGB')
            # Downscale for performance while keeping enough color resolution
            thumb = rgb_img.resize((120, 120))
            # Quantize to 8 palette entries
            quantized = thumb.quantize(colors=8, method=Image.Quantize.MEDIANCUT).convert('RGB')
            colors = quantized.getcolors(120 * 120) or []

            accent_scores = {k: 0.0 for k in ACCENTS}
            total_chroma = 0.0

            for count, (r, g, b) in colors:
                h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
                accent = classify_hue(h * 360.0, s, v)
                # Give higher weight to saturated, visible colors
                score = count * (s ** 1.3) * (v ** 0.8)
                accent_scores[accent] += score
                if accent != 'slate':
                    total_chroma += score

            # If the image is entirely monochrome / grayscale, select slate
            if total_chroma < 10.0:
                winner = 'slate'
            else:
                winner = max(accent_scores, key=accent_scores.get)

            return winner, {
                'wallpaper': image_path,
                'accent': winner,
                'hex': ACCENTS[winner]['hex'],
                'scores': {k: round(v, 2) for k, v in accent_scores.items() if v > 0}
            }
    except Exception as e:
        return 'blue', {'error': str(e)}

def apply_accent(accent):
    """Apply the chosen accent to GNOME GSettings and Aura Glass configuration."""
    conf_dir = os.environ.get('AURA_GLASS_DIR') or os.path.expanduser('~/.config/aura-glass')
    os.makedirs(conf_dir, exist_ok=True)

    # 1. GNOME Interface accent-color
    try:
        subprocess.run(
            ['gsettings', 'set', 'org.gnome.desktop.interface', 'accent-color', accent],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except Exception:
        pass

    # 2. Persist to aura-glass config
    accent_file = os.path.join(conf_dir, 'accent')
    with open(accent_file, 'w', encoding='utf-8') as f:
        f.write(f"{accent}\n")

    marker_file = os.path.join(conf_dir, 'accent-from-wallpaper')
    try:
        with open(marker_file, 'w', encoding='utf-8') as f:
            f.write("1\n")
    except Exception:
        pass

    # 3. Call aura-glass-apply if available to re-splice CSS stylesheets
    apply_bin = os.path.expanduser('~/.local/bin/aura-glass-apply')
    if not os.path.isfile(apply_bin):
        repo_apply = os.path.join(os.path.dirname(__file__), '..', 'bin', 'aura-glass-apply')
        if os.path.isfile(repo_apply):
            apply_bin = repo_apply

    if os.path.isfile(apply_bin) and os.access(apply_bin, os.X_OK):
        try:
            subprocess.run([apply_bin], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

def main():
    parser = argparse.ArgumentParser(description="Extract dominant accent color from wallpaper.")
    parser.add_argument('-w', '--wallpaper', help="Path to wallpaper image file")
    parser.add_argument('-a', '--apply', action='store_true', help="Apply detected accent to GNOME and Aura Glass")
    parser.add_argument('-j', '--json', action='store_true', help="Output results in JSON format")
    parser.add_argument('-q', '--quiet', action='store_true', help="Print only the winning accent name")

    args = parser.parse_args()

    wallpaper_path = args.wallpaper or get_current_wallpaper_path()
    accent, meta = extract_accent_from_image(wallpaper_path)

    if args.apply:
        apply_accent(accent)

    if args.json:
        payload = {
            'accent': accent,
            'hex': ACCENTS.get(accent, {}).get('hex', '#3584e4'),
            'wallpaper': wallpaper_path,
            'details': meta
        }
        print(json.dumps(payload, indent=2))
    elif args.quiet:
        print(accent)
    else:
        status_msg = f"✓ Wallpaper accent detected: {accent.capitalize()} ({ACCENTS.get(accent, {}).get('hex')})"
        if args.apply:
            status_msg += " [applied to GNOME & Aura Glass]"
        print(status_msg)
        if wallpaper_path:
            print(f"  Source: {wallpaper_path}")

if __name__ == '__main__':
    main()
