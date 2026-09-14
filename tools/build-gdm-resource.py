#!/usr/bin/env python3
"""Build a GDM theme from static assets, without running upstream scripts."""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

PREFIX = "/org/gnome/shell/theme/"
FILES = (
    "calendar-today.svg", "calendar-today-light.svg", "gnome-shell-dark.css",
    "gnome-shell-light.css", "gnome-shell-high-contrast.css", "gnome-shell-start.svg",
    "pad-osd.css", "workspace-placeholder.svg", "background.png",
)
ALIASES = {
    "gdm.css": "gnome-shell-dark.css",
    "gdm3.css": "gnome-shell-dark.css",
    "gnome-shell.css": "gnome-shell-dark.css",
    "Yaru/gnome-shell.css": "gnome-shell-light.css",
    "Yaru/gnome-shell-dark.css": "gnome-shell-dark.css",
    "Yaru/gnome-shell-high-contrast.css": "gnome-shell-high-contrast.css",
    "Yaru-dark/gnome-shell.css": "gnome-shell-dark.css",
}
MAX_BYTES = 64 * 1024 * 1024


def build(source, original, output):
    resources = {}
    names = subprocess.check_output(["gresource", "list", str(original)], text=True).splitlines()
    if not names or len(names) > 4096:
        raise ValueError("invalid original theme resource list")
    total = 0
    for name in names:
        if not name.startswith(PREFIX):
            raise ValueError("original resource contains entries outside the theme namespace")
        data = subprocess.check_output(["gresource", "extract", str(original), name])
        total += len(data)
        if total > MAX_BYTES:
            raise ValueError("original resource exceeds theme size limit")
        resources[name[len(PREFIX):]] = data

    # Ignore upstream manifests, shell scripts and preprocessors. Only this
    # explicit set of static files may replace the distribution's resources.
    for name in FILES:
        path = source / "other/gdm/theme" / name
        if path.is_symlink() or not path.is_file():
            raise ValueError("missing or linked static asset: " + name)
        with path.open("rb") as stream:
            data = stream.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ValueError("oversized static asset: " + name)
        if name.startswith("gnome-shell-") and name.endswith(".css"):
            old = b"resource:///org/gnome/shell/theme/background.png"
            if old not in data:
                raise ValueError("upstream CSS no longer contains the expected background URL")
            data = data.replace(old, b"file:///usr/share/backgrounds/aura-gdm.png")
        resources[name] = data
    for alias, source_name in ALIASES.items():
        resources[alias] = resources[source_name]
    if sum(map(len, resources.values())) > MAX_BYTES:
        raise ValueError("compiled theme input exceeds size limit")

    with tempfile.TemporaryDirectory(prefix="aura-gdm-build-", dir=output.parent) as directory:
        stage = Path(directory)
        document = ET.Element("gresources")
        group = ET.SubElement(document, "gresource", prefix=PREFIX.rstrip("/"))
        for index, (alias, data) in enumerate(sorted(resources.items())):
            filename = f"asset-{index}"
            (stage / filename).write_bytes(data)
            ET.SubElement(group, "file", alias=alias).text = filename
        manifest = stage / "theme.xml"
        ET.ElementTree(document).write(manifest, encoding="utf-8", xml_declaration=True)
        compiled = stage / "theme.gresource"
        subprocess.run(["glib-compile-resources", "--sourcedir=" + str(stage),
                        "--target=" + str(compiled), str(manifest)], check=True)
        compiled_names = subprocess.check_output(["gresource", "list", str(compiled)], text=True).splitlines()
        if set(compiled_names) != {PREFIX + name for name in resources}:
            raise ValueError("compiled theme resource validation failed")
        os.replace(compiled, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("original", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error("theme compilation must run as the regular user")
    try:
        build(args.source, args.original, args.output)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print("error: could not build GDM theme: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
