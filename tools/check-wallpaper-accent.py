#!/usr/bin/env python3
"""
Test suite for tools/wallpaper-accent.py.
Validates color classification boundaries, synthetic image extraction, and JSON schema.
"""

import sys
import os
import tempfile
import json
import subprocess
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXTRACTOR = os.path.join(REPO_ROOT, 'tools', 'wallpaper-accent.py')

# Import functions directly
sys.path.insert(0, os.path.join(REPO_ROOT, 'tools'))
import importlib.util
spec = importlib.util.spec_from_file_location("wallpaper_accent", EXTRACTOR)
wa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wa)

failures = 0
def assert_eq(actual, expected, msg=""):
    global failures
    if actual != expected:
        print(f"  ✗ FAIL: expected {expected!r}, got {actual!r}. {msg}")
        failures += 1
    else:
        print(f"  ✓ PASS: {msg or expected}")

print("=== Testing wallpaper-accent ===")

# 1. Hue classification
print("\n[1/3] Testing Hue & Saturation Classification")
assert_eq(wa.classify_hue(0, 0.8, 0.8), "red", "0 deg is red")
assert_eq(wa.classify_hue(355, 0.8, 0.8), "red", "355 deg is red")
assert_eq(wa.classify_hue(30, 0.8, 0.8), "orange", "30 deg is orange")
assert_eq(wa.classify_hue(55, 0.8, 0.8), "yellow", "55 deg is yellow")
assert_eq(wa.classify_hue(120, 0.8, 0.8), "green", "120 deg is green")
assert_eq(wa.classify_hue(175, 0.8, 0.8), "teal", "175 deg is teal")
assert_eq(wa.classify_hue(220, 0.8, 0.8), "blue", "220 deg is blue")
assert_eq(wa.classify_hue(270, 0.8, 0.8), "purple", "270 deg is purple")
assert_eq(wa.classify_hue(320, 0.8, 0.8), "pink", "320 deg is pink")
assert_eq(wa.classify_hue(220, 0.05, 0.8), "slate", "low saturation maps to slate")
assert_eq(wa.classify_hue(220, 0.8, 0.05), "slate", "low value maps to slate")

# 2. Synthetic test images
print("\n[2/3] Testing Synthetic Images")
if HAS_PIL:
    with tempfile.TemporaryDirectory() as tmpdir:
        test_cases = [
            ("red.png", (240, 20, 30), "red"),
            ("blue.png", (40, 120, 240), "blue"),
            ("green.png", (40, 180, 50), "green"),
            ("gray.png", (130, 130, 130), "slate"),
        ]
        for filename, rgb, expected in test_cases:
            p = os.path.join(tmpdir, filename)
            img = Image.new("RGB", (64, 64), rgb)
            img.save(p)

            accent, _ = wa.extract_accent_from_image(p)
            assert_eq(accent, expected, f"synthetic {filename} detected as {expected}")

            # Test CLI flag --wallpaper
            out = subprocess.check_output([sys.executable, EXTRACTOR, '--wallpaper', p, '--quiet'], text=True).strip()
            assert_eq(out, expected, f"CLI output for {filename}")
else:
    print("  (Pillow not installed; testing graceful fallback behavior)")
    accent, _ = wa.extract_accent_from_image("/nonexistent/file.png")
    assert_eq(accent, "blue", "fallback to blue when image cannot be processed")

# 3. CLI JSON schema
print("\n[3/3] Testing CLI JSON schema")
res = subprocess.check_output([sys.executable, EXTRACTOR, '--json'], text=True)
data = json.loads(res)
assert_eq("accent" in data, True, "JSON has 'accent'")
assert_eq("hex" in data, True, "JSON has 'hex'")
assert_eq("wallpaper" in data, True, "JSON has 'wallpaper'")
assert_eq("details" in data, True, "JSON has 'details'")

if failures > 0:
    print(f"\ncheck-wallpaper-accent.py: FAILED ({failures} errors)")
    sys.exit(1)

print("\ncheck-wallpaper-accent.py: passed (all color classification and CLI tests verified)")
sys.exit(0)
