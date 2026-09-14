#!/usr/bin/env python3
"""GDM build/restore regressions using private resources and a mocked sudo."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('builder', REPO / 'tools/build-gdm-resource.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


@unittest.skipUnless(shutil.which('glib-compile-resources') and shutil.which('gresource'),
                     'GDM resource compiler/tools not installed')
class GdmSecurityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='aura-gdm-security-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'cache/WhiteSur-gtk-theme'
        self.assets = self.source / 'other/gdm/theme'
        self.assets.mkdir(parents=True)
        for name in builder.FILES:
            data = b'static asset'
            if name.startswith('gnome-shell-') and name.endswith('.css'):
                data = b'window { background-image: url("resource:///org/gnome/shell/theme/background.png"); }'
            (self.assets / name).write_bytes(data)
        (self.root / 'stock.css').write_text('/* original */')
        (self.root / 'stock.svg').write_text('<svg/>')
        xml = self.root / 'stock.xml'
        xml.write_text('<gresources><gresource prefix="/org/gnome/shell/theme">'
                       '<file alias="gdm.css">stock.css</file>'
                       '<file alias="distro-extra.svg">stock.svg</file>'
                       '</gresource></gresources>')
        self.original = self.root / 'system.gresource'
        self.output = self.root / 'built.gresource'
        subprocess.run(['glib-compile-resources', '--sourcedir=' + str(self.root),
                        '--target=' + str(self.original), str(xml)], check=True)
        self.stock_bytes = self.original.read_bytes()
        self.conf = self.root / 'config'
        self.conf.mkdir()
        self.env = dict(os.environ, HOME=str(self.root / 'home'), AURA_GLASS_CONF=str(self.conf),
                        SECURITY_ROOT=str(self.root), SECURITY_TARGET=str(self.original),
                        SECURITY_SOURCE=str(self.source), SECURITY_CALLS=str(self.root / 'calls'))

    def shell(self, code):
        # Every privileged operation is intercepted; only fixture files change.
        prelude = r'''
set -eu
. "$1/lib/common.sh"
. "$1/lib/steps-gdm.sh"
CONF_DIR="$SECURITY_ROOT/config"
SRC_CACHE="$SECURITY_ROOT/cache"
DRY_RUN=0
have() { return 0; }
have_image_processor() { return 0; }
clone_pinned() { :; }
detect_gdm_theme_files() { printf '%s\n' "$SECURITY_TARGET"; }
resolve_gdm_wallpaper_source() { printf '%s\n' "$SECURITY_SOURCE/other/gdm/theme/background.png"; }
generate_gdm_wallpaper() { command cp "$1" "$2"; }
install_gdm_sync_unit() { :; }
uninstall_gdm_sync_unit() { :; }
mock_sudo() {
    printf '%s\n' "$*" >> "$SECURITY_CALLS"
    case "$1" in
        cp)
            case "${@: -1}" in
                "$SECURITY_ROOT"/*) command "$@" ;;
                *) return 0 ;;
            esac ;;
        install)
            [ "${@: -1}" = "$SECURITY_TARGET" ] || return 98
            cat > "$SECURITY_TARGET" ;;
        mkdir|chown|chmod|rm|update-alternatives) return 0 ;;
        *) return 97 ;;
    esac
}
sudo() { mock_sudo "$@"; }
'''
        return subprocess.run(['bash', '-c', prelude + code, 'test', str(REPO)],
                              env=self.env, capture_output=True, text=True, timeout=30)

    def test_static_build_preserves_distribution_resources(self):
        builder.build(self.source, self.original, self.output)
        css = subprocess.check_output(['gresource', 'extract', str(self.output), builder.PREFIX + 'gdm.css'])
        self.assertIn(b'file:///usr/share/backgrounds/aura-gdm.png', css)
        extra = subprocess.check_output(['gresource', 'extract', str(self.output), builder.PREFIX + 'distro-extra.svg'])
        self.assertEqual(extra, b'<svg/>')
        self.assertEqual(self.original.read_bytes(), self.stock_bytes)

    def test_upstream_scripts_and_manifest_are_never_executed(self):
        marker = self.root / 'executed'
        (self.source / 'tweaks.sh').write_text('#!/bin/sh\ntouch ' + str(marker) + '\n')
        (self.assets.parent / 'gnome-shell-theme.gresource.xml').write_text('malicious manifest')
        builder.build(self.source, self.original, self.output)
        self.assertFalse(marker.exists())

    def test_incomplete_assets_leave_existing_output_untouched(self):
        (self.assets / 'gnome-shell-dark.css').unlink()
        self.output.write_bytes(b'previous result')
        with self.assertRaises(ValueError):
            builder.build(self.source, self.original, self.output)
        self.assertEqual(self.output.read_bytes(), b'previous result')

    def test_linked_assets_are_rejected(self):
        path = self.assets / 'gnome-shell-dark.css'
        original = self.root / 'linked.css'
        path.rename(original)
        path.symlink_to(original)
        with self.assertRaises(ValueError):
            builder.build(self.source, self.original, self.output)

    def test_install_preserves_first_backup_and_uninstall_ignores_cache_script(self):
        result = self.shell('install_gdm default\ninstall_gdm default\n')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        backup = Path(str(self.original) + '.aura-backup')
        self.assertEqual(backup.read_bytes(), self.stock_bytes)
        self.assertNotEqual(self.original.read_bytes(), self.stock_bytes)
        (self.source / 'tweaks.sh').write_text('#!/bin/sh\nexit 0\n')
        result = self.shell('uninstall_gdm\n')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.original.read_bytes(), self.stock_bytes)
        calls = (self.root / 'calls').read_text().splitlines()
        self.assertFalse(any(line.startswith(('bash ', 'sh ', 'python')) for line in calls))

    def test_backup_failure_prevents_resource_installation(self):
        result = self.shell('sudo() { if [ "$1" = cp ] && [ "${@: -1}" = "${SECURITY_TARGET}.aura-backup" ]; then return 1; fi; mock_sudo "$@"; }; install_gdm default\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.original.read_bytes(), self.stock_bytes)

    def test_invalid_existing_backup_prevents_resource_installation(self):
        Path(str(self.original) + '.aura-backup').write_bytes(b'invalid')
        result = self.shell('install_gdm default\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.original.read_bytes(), self.stock_bytes)
        calls = (self.root / 'calls').read_text()
        self.assertNotIn('install -o root', calls)


if __name__ == '__main__':
    unittest.main()
