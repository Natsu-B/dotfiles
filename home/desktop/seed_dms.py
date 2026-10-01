#!/usr/bin/env python3
"""Seed writable DMS state without replacing user display/personalization settings."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import stat
import tempfile


def read_object(path: Path) -> dict:
    if path.is_symlink():
        raise ValueError(f"Refusing to replace a symlink: {path}")
    if not path.exists():
        return {}
    if not path.is_file() or path.stat().st_uid != os.getuid():
        raise ValueError(f"Not an owned regular file: {path}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return value


def write_object(path: Path, value: dict) -> None:
    text = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    if path.exists() and path.read_text(encoding="utf-8") == text:
        return
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".dotfiles-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(text)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def seed(config_home: Path, state_home: Path, defaults: dict) -> None:
    settings_path = config_home / "DankMaterialShell/settings.json"
    settings = read_object(settings_path)
    for key, value in defaults["settings"].items():
        settings.setdefault(key, value)
    # Reapply the deliberately shared lock/logout paths before DMS starts.
    # Other settings remain writable and survive rebuilds.
    settings.update(defaults["policy"])
    write_object(settings_path, settings)

    session_path = state_home / "DankMaterialShell/session.json"
    session = read_object(session_path)
    for key, value in defaults["session"].items():
        session.setdefault(key, value)
    write_object(session_path, session)

    dms_dir = config_home / "hypr/dms"
    dms_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    for name in ("outputs", "layout", "colors", "cursor", "windowrules"):
        path = dms_dir / f"{name}.lua"
        if path.is_symlink():
            raise ValueError(f"DMS needs a writable file, not a symlink: {path}")
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            if not stat.S_ISREG(path.stat().st_mode):
                raise ValueError(f"Expected a regular Lua file: {path}")
        else:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                stream.write("-- Managed interactively by DankMaterialShell.\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("defaults", type=Path)
    args = parser.parse_args()
    home = Path.home()
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    state_home = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state"))
    seed(config_home, state_home, json.loads(args.defaults.read_text(encoding="utf-8")))


if __name__ == "__main__":
    main()
