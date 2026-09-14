"""Restricted data archives for theme imports (no tar links or special files)."""

import argparse
import json
import os
from pathlib import PurePosixPath
import re
import shutil
import sys
import tarfile
import tempfile

MAX_BYTES = 512 * 1024 * 1024
MAX_MEMBERS = 10000
BUNDLE_FILES = {"manifest.json", "profile.json", "wallpaper.png"}


def members_checked(archive, bundle=False):
    members = []
    seen = set()
    total = 0
    for member in archive:
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts or "\x00" in member.name:
            raise ValueError("absolute or traversal path in archive")
        if not (member.isfile() or member.isdir()) or member.issparse():
            raise ValueError("links, sparse and special files are forbidden")
        name = str(path)
        if name == "." and not member.isdir():
            raise ValueError("invalid root entry")
        if path.parts and path.parts[0] in {"repo-path", "gdm-backup-path"}:
            raise ValueError("backup cannot replace trusted local installation paths")
        if name in seen:
            raise ValueError("duplicate archive path")
        if bundle and name != "." and (name not in BUNDLE_FILES or not member.isfile()):
            raise ValueError("unexpected bundle entry")
        seen.add(name)
        total += member.size
        if member.size < 0 or total > MAX_BYTES or len(seen) > MAX_MEMBERS:
            raise ValueError("archive exceeds import size or entry limit")
        members.append(member)
    file_names = {str(PurePosixPath(m.name)) for m in members if m.isfile()}
    for member in members:
        for parent in PurePosixPath(member.name).parents:
            if str(parent) in file_names:
                raise ValueError("file used as an archive directory")
    return members


def manifest_checked(archive):
    member = next((m for m in archive.getmembers()
                   if str(PurePosixPath(m.name)) == "manifest.json"), None)
    if member is None or member.size > 65536:
        raise ValueError("missing or oversized manifest.json")
    with archive.extractfile(member) as stream:
        data = json.load(stream)
    if not isinstance(data, dict):
        raise ValueError("manifest must be an object")
    for key in ("accent", "profile", "mode", "glow", "sound", "name", "author", "date"):
        value = data.get(key, "")
        if not isinstance(value, str) or any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ValueError("invalid manifest text field: " + key)
    profile = data.get("profile", "")
    if profile and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 _-]{0,127}", profile):
        raise ValueError("invalid profile name")
    choices = {
        "accent": {"", "default", "auto", "blue", "teal", "green", "yellow", "orange", "red", "pink", "purple", "slate"},
        "mode": {"", "frosted", "transparent", "solid", "eco", "auto"},
        "glow": {"", "off", "subtle", "neon", "accent"},
        "sound": {"", "enabled", "disabled"},
    }
    for key, allowed in choices.items():
        if data.get(key, "") not in allowed:
            raise ValueError("invalid manifest setting: " + key)
    return data


def directory_fd(root_fd, parts, create=False):
    """Walk from an open directory without following destination symlinks."""
    fd = os.dup(root_fd)
    try:
        for part in parts:
            if create:
                try:
                    os.mkdir(part, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def extract_checked(archive, members, destination):
    # Validate and read the entire archive into private staging before changing
    # the destination. Ignore archive ownership and permissions completely.
    with tempfile.TemporaryDirectory(prefix="aura-import-") as stage:
        for i, member in enumerate(members):
            if member.isfile():
                with archive.extractfile(member) as src, open(os.path.join(stage, str(i)), "wb") as dst:
                    shutil.copyfileobj(src, dst)
        os.makedirs(destination, mode=0o700, exist_ok=True)
        root_fd = os.open(destination, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            for i, member in enumerate(members):
                parts = PurePosixPath(member.name).parts
                parent_fd = directory_fd(root_fd, parts if member.isdir() else parts[:-1], create=True)
                try:
                    if member.isfile():
                        # Replace via rename: an existing symlink/hardlink is
                        # replaced itself, never opened or written through.
                        name = ".aura-import-" + os.urandom(16).hex()
                        fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                     0o600, dir_fd=parent_fd)
                        try:
                            with os.fdopen(fd, "wb") as dst, open(os.path.join(stage, str(i)), "rb") as src:
                                shutil.copyfileobj(src, dst)
                            os.replace(name, parts[-1], src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
                        finally:
                            try:
                                os.unlink(name, dir_fd=parent_fd)
                            except FileNotFoundError:
                                pass
                finally:
                    os.close(parent_fd)
        finally:
            os.close(root_fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("verify", "extract", "bundle-inspect", "bundle-extract"))
    parser.add_argument("archive")
    parser.add_argument("destination", nargs="?")
    args = parser.parse_args()
    try:
        with tarfile.open(args.archive, "r:gz") as archive:
            bundle = args.action.startswith("bundle-")
            members = members_checked(archive, bundle)
            data = manifest_checked(archive) if bundle else None
            if args.action in ("extract", "bundle-extract"):
                if args.destination is None:
                    raise ValueError("missing extraction destination")
                extract_checked(archive, members, args.destination)
            if args.action == "bundle-inspect":
                print(json.dumps(data))
            elif args.action == "bundle-extract":
                for key in ("accent", "profile", "mode", "glow", "sound", "name"):
                    sys.stdout.buffer.write(data.get(key, "").encode() + b"\0")
    except (OSError, ValueError, tarfile.TarError, EOFError) as exc:
        print("error: unsafe or invalid archive: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
