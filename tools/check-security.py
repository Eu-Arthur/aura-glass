#!/usr/bin/env python3
"""Security regressions; all commands and payloads run in temporary fixtures."""
import io
import gzip
import json
import os
from pathlib import Path
import shutil
import signal
import time
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile

REPO = Path(__file__).resolve().parents[1]


class SecurityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aura-security-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fixture = self.root / "checkout"
        self.conf = self.root / "config"
        self.conf.mkdir()
        (self.fixture / "bin").mkdir(parents=True)
        (self.fixture / "lib").mkdir()
        for name in ("bundle", "backup", "profile", "bench", "sound", "wallpaper", "apps", "daemon", "flatpak"):
            shutil.copy2(REPO / "bin" / ("aura-glass-" + name), self.fixture / "bin")
        shutil.copy2(REPO / "lib/safe_archive.py", self.fixture / "lib")
        self.mock = self.root / "mocks"
        self.mock.mkdir()
        self.calls = self.root / "side-effects"
        for name in ("aura-glass", "aura-glass-apply", "aura-glass-mode", "aura-glass-glow",
                     "gsettings", "dconf", "systemctl", "notify-send"):
            path = self.mock / name
            path.write_text('#!/bin/sh\nprintf "called\\n" >> "$SECURITY_CALLS"\nexit 0\n')
            path.chmod(0o755)
        for name in ("aura-glass", "aura-glass-apply", "aura-glass-glow"):
            shutil.copy2(self.mock / name, self.fixture / "bin")
        self.env = dict(os.environ, HOME=str(self.root / "home"),
                        XDG_CONFIG_HOME=str(self.root / "xdg-config"),
                        XDG_DATA_HOME=str(self.root / "data"),
                        AURA_GLASS_CONF=str(self.conf), AURA_GLASS_DIR=str(self.conf),
                        PATH=str(self.mock) + ":" + os.environ["PATH"],
                        SECURITY_CALLS=str(self.calls),
                        DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent/aura-security-bus")

    def run_cli(self, name, *args, ok=True):
        result = subprocess.run([str(self.fixture / "bin" / ("aura-glass-" + name)), *map(str, args)],
                                env=self.env, cwd=self.root, capture_output=True, text=True, timeout=30)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def archive(self, name, entries):
        path = self.root / name
        with tarfile.open(path, "w:gz") as archive:
            for entry, content in entries:
                if isinstance(entry, str):
                    info = tarfile.TarInfo(entry)
                else:
                    info = entry
                if content is not None:
                    info.size = len(content)
                archive.addfile(info, io.BytesIO(content) if content is not None else None)
        return path

    def bundle(self, name="bundle.auraglass", manifest=None, extra=()):
        return self.archive(name, [("manifest.json", json.dumps(manifest or {"name": "Demo"}).encode()), *extra])

    def test_bundle_metadata_is_data(self):
        marker = self.root / "executed"
        title = f'$(touch {marker}) `touch {marker}` "quoted"'
        path = self.bundle(manifest={"name": title})
        self.run_cli("bundle", "apply", path)
        self.assertFalse(marker.exists())

    def test_export_quotes_roundtrip_and_default_name_confined(self):
        title = "Arthur's ../theme"
        path = self.root / "Arthur's bundle.auraglass"
        self.run_cli("bundle", "export", path, "--name", title, "--author", "L'utilisateur")
        self.assertIn(title, self.run_cli("bundle", "inspect", path).stdout)
        self.run_cli("bundle", "export", "--name", "../../escaped")
        self.assertFalse((self.root / "escaped.auraglass").exists())
        self.assertEqual(len(list((self.conf / "bundles").glob("*.auraglass"))), 1)

    def test_python_injection_filename_is_literal(self):
        marker = self.root / "python-executed"
        # The payload has no path separator and is a valid Linux filename.
        filename = "x'); __import__('pathlib').Path('python-executed').touch(); #.auraglass"
        path = self.bundle(name=filename)
        result = self.run_cli("bundle", "inspect", path)
        self.assertIn("Demo", result.stdout)
        self.assertFalse(marker.exists())

    def test_reject_bundle_before_applying_settings(self):
        for manifest in ({"profile": "../../escaped", "accent": "red"},
                         {"profile": "/absolute"}, {"name": []}, {"glow": "evil"}):
            with self.subTest(manifest=manifest):
                self.run_cli("bundle", "apply", self.bundle(manifest=manifest), ok=False)
                self.assertFalse(self.calls.exists())
                self.assertFalse((self.conf / "accent").exists())
        corrupt = self.root / "corrupt.auraglass"
        corrupt.write_bytes(b"invalid")
        self.run_cli("bundle", "apply", corrupt, ok=False)
        self.assertFalse(self.calls.exists())

    def test_archives_reject_unsafe_member_types_and_paths(self):
        entries = []
        for name in ("../escaped", "/absolute", "a/../../escaped"):
            entries.append((tarfile.TarInfo(name), b"evil"))
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE, tarfile.CHRTYPE):
            info = tarfile.TarInfo("link")
            info.type = kind
            info.linkname = "../escaped"
            entries.append((info, None))
        for index, entry in enumerate(entries):
            with self.subTest(index=index):
                path = self.archive("bad.tar.gz", [entry])
                self.run_cli("backup", "verify", path, ok=False)
                self.run_cli("backup", "import", path, ok=False)
                path = self.bundle(extra=[entry])
                self.run_cli("bundle", "apply", path, ok=False)
        self.assertFalse(self.calls.exists())
        self.assertFalse((self.root / "escaped").exists())

    def test_reject_duplicate_members_and_checkout_redirection(self):
        for entries in ([("accent", b"red"), ("accent", b"blue")],
                        [("repo-path", b"/attacker/checkout")],
                        [("accent", b"red"), ("accent/file", b"bad")]):
            self.run_cli("backup", "verify", self.archive("bad.tar.gz", entries), ok=False)
        path = self.bundle(extra=[("manifest.json", b'{}')])
        self.run_cli("bundle", "apply", path, ok=False)

    def test_declared_archive_size_limit(self):
        info = tarfile.TarInfo("oversized")
        info.size = 512 * 1024 * 1024 + 1
        # Only a header is written; the test allocates no oversized payload.
        archive = self.root / "oversized.tar.gz"
        with gzip.open(archive, "wb") as stream:
            stream.write(info.tobuf() + b"\0" * 1024)
        self.run_cli("backup", "verify", archive, ok=False)
        self.assertFalse(self.calls.exists())

    def test_profile_list_treats_filenames_as_data(self):
        profiles = self.conf / "profiles"
        profiles.mkdir()
        (profiles / "x").write_text("{}")
        filename = "x')); __import__('pathlib').Path('executed').touch(); #.json"
        (profiles / filename).write_text(json.dumps({"description": "safe"}))
        self.assertIn("safe", self.run_cli("profile", "list").stdout)
        self.assertFalse((self.root / "executed").exists())

    def test_backup_does_not_write_through_existing_links(self):
        outside = self.root / "outside"
        outside.mkdir()
        target = outside / "value"
        target.write_text("original")
        (self.conf / "accent").symlink_to(target)
        archive = self.archive("valid.tar.gz", [("accent", b"blue")])
        helper = self.fixture / "lib/safe_archive.py"
        result = subprocess.run([sys.executable, str(helper), "extract", str(archive), str(self.conf)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_text(), "original")
        self.assertEqual((self.conf / "accent").read_text(), "blue")
        (self.conf / "profiles").symlink_to(outside, target_is_directory=True)
        archive = self.archive("parent.tar.gz", [("profiles/value", b"evil")])
        result = subprocess.run([sys.executable, str(helper), "extract", str(archive), str(self.conf)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), "original")

    def test_profile_names_cannot_escape(self):
        for name in ("../../escaped", str(self.root / "escaped"), "../escaped", "bad\nname"):
            profile = self.root / "import.json"
            profile.write_text(json.dumps({"name": name}))
            self.run_cli("profile", "import", profile, ok=False)
            self.run_cli("profile", "save", name, ok=False)
            self.run_cli("profile", "remove", name, ok=False)
        self.assertFalse((self.root / "escaped.json").exists())

    def test_profile_description_quotes_roundtrip(self):
        description = "Arthur's theme; __import__('os'); $(false)"
        self.run_cli("profile", "save", "my-theme", "--description", description)
        data = json.loads(self.run_cli("profile", "export", "my-theme").stdout)
        self.assertEqual(data["description"], description)
        profile = self.root / "Arthur's profile.json"
        profile.write_text(json.dumps(data))
        self.run_cli("profile", "import", profile)

    def test_installed_backup_finds_archive_helper(self):
        (self.fixture / "lib/aura-glass").mkdir()
        (self.fixture / "lib/safe_archive.py").rename(self.fixture / "lib/aura-glass/safe_archive.py")
        self.run_cli("backup", "verify", self.archive("valid.tar.gz", [("accent", b"blue")]))

    def vscode_settings(self, content):
        path = Path(self.env["XDG_CONFIG_HOME"]) / "Code/User/settings.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_vscode_unsupported_settings_are_never_overwritten(self):
        for content in ('{// security preference\n"security.workspace.trust.enabled": true,\n}',
                        '{"security.workspace.trust.enabled": true,}',
                        '{"unfinished":', '[]',
                        '{"workbench.colorCustomizations": null}',
                        '{"setting": 1, "setting": 2}', '{"setting": NaN}'):
            with self.subTest(content=content):
                path = self.vscode_settings(content)
                self.run_cli("apps", "apply", "vscode", ok=False)
                self.assertEqual(path.read_text(), content)
                self.assertFalse(path.with_suffix(".json.aurabackup").exists())

    def test_vscode_roundtrip_keeps_security_settings_and_first_backup(self):
        original = '{"security.workspace.trust.enabled": true, "workbench.colorCustomizations": {"editor.foreground": "#abcdef"}}\n'
        path = self.vscode_settings(original)
        self.run_cli("apps", "apply", "vscode")
        self.run_cli("apps", "apply", "vscode")
        data = json.loads(path.read_text())
        self.assertIs(data["security.workspace.trust.enabled"], True)
        self.assertEqual(data["workbench.colorCustomizations"]["editor.foreground"], "#abcdef")
        self.assertEqual(path.with_suffix(".json.aurabackup").read_text(), original)
        self.run_cli("apps", "revert", "vscode")
        self.assertEqual(path.read_text(), original)

    def test_vscode_refuses_settings_and_backup_links(self):
        path = self.vscode_settings('{}')
        outside = self.root / "external-settings"
        outside.write_text('{"protected": true}')
        for target in (path, path.with_suffix(".json.aurabackup")):
            for kind in ("symlink", "hardlink"):
                with self.subTest(target=target.name, kind=kind):
                    target.unlink(missing_ok=True)
                    if kind == "symlink":
                        target.symlink_to(outside)
                    else:
                        os.link(outside, target)
                    self.run_cli("apps", "apply", "vscode", ok=False)
                    self.assertEqual(outside.read_text(), '{"protected": true}')
                    target.unlink()
            if target == path:
                path.write_text('{}')

    def test_vscode_invalid_utf8_remains_intact(self):
        path = self.vscode_settings('{}')
        path.write_bytes(b'{"value":"\xff"}')
        self.run_cli("apps", "apply", "vscode", ok=False)
        self.assertEqual(path.read_bytes(), b'{"value":"\xff"}')

    def test_vscode_backup_failure_preserves_settings(self):
        path = self.vscode_settings('{"protected": true}')
        path.with_suffix(".json.aurabackup").mkdir()
        self.run_cli("apps", "apply", "vscode", ok=False)
        self.assertEqual(path.read_text(), '{"protected": true}')

    def test_vscode_can_create_missing_settings(self):
        path = self.vscode_settings('{}')
        path.unlink()
        self.run_cli("apps", "apply", "vscode")
        self.assertIn("workbench.colorCustomizations", json.loads(path.read_text()))
        self.assertFalse(path.with_suffix(".json.aurabackup").exists())

    def test_vscode_dangling_backup_link_cannot_create_external_file(self):
        path = self.vscode_settings('{"protected": true}')
        outside = self.root / "must-not-be-created"
        path.with_suffix(".json.aurabackup").symlink_to(outside)
        self.run_cli("apps", "apply", "vscode", ok=False)
        self.assertFalse(outside.exists())
        self.assertEqual(path.read_text(), '{"protected": true}')

    def test_vscode_write_failure_keeps_original_and_cleans_temporary_file(self):
        path = self.vscode_settings('{"protected": true}')
        code = (REPO / "bin/aura-glass-apps").read_text().split("<<'PYTHON'\n", 1)[1].split('\nPYTHON', 1)[0]
        harness = '''import sys
from unittest.mock import patch
source = sys.argv.pop(1)
with patch("os.replace", side_effect=OSError("simulated write failure")):
    exec(compile(source, "vscode-styling", "exec"))
'''
        result = subprocess.run([sys.executable, '-c', harness, code, '#3584e4', str(path)],
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("simulated write failure", result.stderr)
        self.assertEqual(path.read_text(), '{"protected": true}')
        self.assertEqual(path.with_suffix(".json.aurabackup").read_text(), path.read_text())
        self.assertEqual(list(path.parent.glob('.aura-settings-*')), [])

    def flatpak_fixture(self):
        root = self.root / "sandboxes"
        app = root / "org.example.App"
        app.mkdir(parents=True)
        self.env["AURA_GLASS_FLATPAK_VAR"] = str(root)
        for version in ("gtk-4.0", "gtk-3.0"):
            source = Path(self.env["XDG_CONFIG_HOME"]) / version
            source.mkdir(parents=True)
            (source / "gtk.css").write_text("/* theme */")
        flatpak = self.mock / "flatpak"
        flatpak.write_text('#!/bin/sh\nprintf "%s\\n" "$@" >> "$SECURITY_CALLS"\n')
        flatpak.chmod(0o755)
        return app

    def test_flatpak_revert_preserves_other_permission_overrides(self):
        self.flatpak_fixture()
        self.run_cli("flatpak", "revert")
        args = self.calls.read_text().splitlines()
        self.assertNotIn("--reset", args)
        self.assertIn("--nofilesystem=xdg-config/gtk-4.0", args)
        self.assertIn("--unset-env=GTK_THEME", args)

    def test_flatpak_does_not_hide_override_failures(self):
        self.flatpak_fixture()
        (self.mock / "flatpak").write_text("#!/bin/sh\nexit 1\n")
        self.run_cli("flatpak", "override", ok=False)
        self.run_cli("flatpak", "revert", ok=False)

    def test_flatpak_backup_link_cannot_overwrite_host_file(self):
        app = self.flatpak_fixture()
        gtk = app / "config/gtk-4.0"
        gtk.mkdir(parents=True)
        (gtk / "gtk.css").write_text("attacker-controlled data")
        outside = self.root / "host-file"
        outside.write_text("original")
        (gtk / "gtk.css.aurabackup").symlink_to(outside)
        self.run_cli("flatpak", "sync", ok=False)
        self.assertEqual(outside.read_text(), "original")

    def test_flatpak_does_not_follow_app_config_directory_link(self):
        app = self.flatpak_fixture()
        outside = self.root / "outside"
        outside.mkdir()
        (app / "config").symlink_to(outside, target_is_directory=True)
        self.run_cli("flatpak", "sync", ok=False)
        self.assertEqual(list(outside.iterdir()), [])

    def test_flatpak_roundtrip_keeps_first_backup_and_unrelated_links(self):
        app = self.flatpak_fixture()
        gtk = app / "config/gtk-4.0"
        gtk.mkdir(parents=True)
        (gtk / "gtk.css").write_text("original")
        self.run_cli("flatpak", "sync")
        self.run_cli("flatpak", "sync")
        self.run_cli("flatpak", "revert")
        self.assertEqual((gtk / "gtk.css").read_text(), "original")
        (gtk / "gtk.css").unlink()
        outside = self.root / "custom.css"
        outside.write_text("custom")
        (gtk / "gtk.css").symlink_to(outside)
        self.run_cli("flatpak", "revert")
        self.assertTrue((gtk / "gtk.css").is_symlink())

    def test_daemon_stop_cannot_kill_unrelated_process(self):
        sleeper = subprocess.Popen(["sleep", "30"])
        try:
            (self.conf / "daemon.pid").write_text(str(sleeper.pid))
            self.run_cli("daemon", "stop")
            self.assertIsNone(sleeper.poll())
        finally:
            sleeper.terminate()
            sleeper.wait(timeout=5)

    def test_daemon_rejects_group_and_invalid_pids_in_status(self):
        # Status sends no signal: even a regression cannot kill a process group.
        for pid in ("0", "-1", "1", "invalid", "999999999999999999999"):
            (self.conf / "daemon.pid").write_text(pid)
            self.assertIn("Inactive", self.run_cli("daemon", "status").stdout)

    def test_daemon_can_stop_its_own_process(self):
        proc = subprocess.Popen([str(self.fixture / "bin/aura-glass-daemon"), "run"],
                                env=self.env, cwd=self.root, start_new_session=True,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 5
            while not (self.conf / "daemon.pid").exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertIn("Active (running", self.run_cli("daemon", "status").stdout)
            self.run_cli("daemon", "stop")
            self.assertEqual(proc.wait(timeout=5), 0)
        finally:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=5)

    def test_syntax_validation_checks_second_script(self):
        valid = self.root / "first.sh"
        broken = self.root / "second script.sh"
        valid.write_text("true\n")
        broken.write_text("if then\n")
        for relative in ("tools/check-all.sh", "tools/hooks/pre-commit"):
            code = (REPO / relative).read_text()
            body = code.split("syntax_shell() {", 1)[1].split("\n}", 1)[0]
            invocation = 'syntax_shell "$1" "$2"' if relative.endswith("check-all.sh") else 'TMP="$3"; syntax_shell'
            script = "syntax_shell() {" + body + "\n}\n" + invocation
            result = subprocess.run(["bash", "-c", script, "test", str(valid), str(broken), str(self.root)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, relative)
            self.assertIn(str(broken), result.stderr)

    def run_ego_install(self, url, archive_uuid="test@aura.invalid", broken=False):
        archive = self.root / "extension.zip"
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr("metadata.json", "invalid" if broken else json.dumps({"uuid": archive_uuid, "shell-version": ["50"]}))
        metadata = self.root / "ego.json"
        metadata.write_text(json.dumps({"download_url": url}))
        script = r'''set -eu
. "$1/lib/common.sh"
. "$1/lib/steps-extensions.sh"
EXT_DIR="$2/extensions"
GNOME_MAJOR=50
curl() {
    local output="" arg
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -fsSLo|-sLo|-o) output="$2"; shift ;;
        esac
        shift
    done
    if [ -n "$output" ]; then
        printf 'download\n' >> "$SECURITY_CALLS"
        cp "$SECURITY_ZIP" "$output"
    else
        cat "$SECURITY_META"
    fi
}
gnome-extensions() { printf 'install\n' >> "$SECURITY_CALLS"; }
install_ext_ego test@aura.invalid
'''
        # Record neither tokens nor real network calls: the downloader is a stub.
        return subprocess.run(["bash", "-c", script, "test", str(REPO), str(self.root)],
                              cwd=self.root, env=dict(self.env, SECURITY_ZIP=str(archive), SECURITY_META=str(metadata)),
                              capture_output=True, text=True)

    def test_extension_download_rejects_external_or_malformed_urls(self):
        for url in ("@evil.invalid/payload", "//evil.invalid/payload", "https://evil.invalid/payload",
                    "/download-extension/a.zip\nextra", "/unrelated/path"):
            result = self.run_ego_install(url)
            self.assertNotEqual(result.returncode, 0, url)
            self.assertFalse(self.calls.exists())

    def test_extension_download_checks_uuid_and_accepts_expected_extension(self):
        url = "/download-extension/test.shell-extension.zip?version_tag=1"
        result = self.run_ego_install(url, archive_uuid="unwanted@aura.invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("install", self.calls.read_text())
        self.calls.unlink()
        result = self.run_ego_install(url)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("install", self.calls.read_text())

    def test_extension_download_rejects_broken_metadata(self):
        result = self.run_ego_install("/download-extension/a.zip", broken=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("install", self.calls.read_text())

    def test_download_helpers_reject_non_https_urls(self):
        # An HTTP/file URL is rejected by curl before any network/file read.
        for function in ("fetch_tarball_pinned", "fetch_zip_pinned"):
            script = '. "$1/lib/common.sh"; ' + function + ' "$2" invalid "$3"'
            result = subprocess.run(["bash", "-c", script, "test", str(REPO),
                                     "http://127.0.0.1:1/archive", str(self.root / "download")],
                                    env=self.env, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("disabled", result.stderr.lower())
            self.assertFalse((self.root / "download").exists())

    def test_backup_rejects_and_does_not_export_gdm_restore_path(self):
        path = self.archive("gdm.tar.gz", [("gdm-backup-path", b"/untrusted/backup")])
        self.run_cli("backup", "verify", path, ok=False)
        (self.conf / "gdm-backup-path").write_text("/untrusted/backup")
        target = self.root / "export.tar.gz"
        self.run_cli("backup", "export", target)
        with tarfile.open(target) as archive:
            self.assertNotIn("./gdm-backup-path", archive.getnames())

    def test_gdm_restore_ignores_imported_backup_path(self):
        payload = self.root / "untrusted-backup"
        payload.write_text("untrusted")
        (self.conf / "gdm-backup-path").write_text(str(payload))
        script = r'''set -eu
. "$1/lib/common.sh"
. "$1/lib/steps-gdm.sh"
CONF_DIR="$2/config"
SRC_CACHE="$2/absent-cache"
DRY_RUN=0
detect_gdm_theme_files() { printf '%s\n' "$SECURITY_TARGET"; }
uninstall_gdm_sync_unit() { :; }
sudo() { printf '%s\n' "$*" >> "$SECURITY_CALLS"; return 1; }
uninstall_gdm
'''
        result = subprocess.run(["bash", "-c", script, "test", str(REPO), str(self.root)],
                                env=dict(self.env, SECURITY_TARGET=str(self.root / "gdm.gresource")),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        if self.calls.exists():
            self.assertNotIn(str(payload), self.calls.read_text())

    def test_checksum_mismatch_stops_before_unpacking(self):
        script = '''set -eu
. "$1/lib/common.sh"
curl() { local dst=""; while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then dst="$2"; shift; fi; shift; done; printf changed > "$dst"; }
unzip() { touch "$SECURITY_CALLS"; }
fetch_zip_pinned https://example.invalid/font.zip invalid "$2" warn
'''
        result = subprocess.run(["bash", "-c", script, "test", str(REPO), str(self.root / "fonts")], env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.calls.exists())
        self.assertFalse((self.root / "fonts").exists())


if __name__ == "__main__":
    unittest.main()
