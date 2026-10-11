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
    # Apply the requested motion fix to existing profiles once, then keep GUI choices.
    motion_path = state_home / "dotfiles/dms-motion-v1.json"
    motion = read_object(motion_path)
    if not motion.get("applied"):
        for key in ("syncComponentAnimationSpeeds", "modalAnimationSpeed"):
            if key in defaults["settings"]:
                settings[key] = defaults["settings"][key]
    apps_path = state_home / "dotfiles/dms-running-apps-v1.json"
    apps = read_object(apps_path)
    if not apps.get("applied"):
        migrate_running_apps(settings)
    # Replace the old unset power policy once; later Power & Sleep choices survive.
    power_path = state_home / "dotfiles/dms-power-v1.json"
    power = read_object(power_path)
    if not power.get("applied"):
        for key in ("acProfileName", "batteryProfileName", "batteryAutoPowerSaver",
                    "lowerDisplayRefreshRateOnBattery", "batteryPostLockMonitorTimeout"):
            if key in defaults["settings"]:
                settings[key] = defaults["settings"][key]
    sleep_path = state_home / "dotfiles/dms-s4-v1.json"
    sleep = read_object(sleep_path)
    sleep_options = {key: defaults["settings"][key]
                     for key in ("acSuspendBehavior", "batterySuspendBehavior")
                     if key in defaults["settings"]}
    if sleep_options and not sleep.get("applied"):
        settings.update(sleep_options)
    write_object(settings_path, settings)
    if not motion.get("applied"):
        write_object(motion_path, {"applied": True})
    if not apps.get("applied"):
        write_object(apps_path, {"applied": True})
    if not power.get("applied"):
        write_object(power_path, {"applied": True})
    if sleep_options and not sleep.get("applied"):
        write_object(sleep_path, {"applied": True})

    session_path = state_home / "DankMaterialShell/session.json"
    session = read_object(session_path)
    for key, value in defaults["session"].items():
        session.setdefault(key, value)
    write_object(session_path, session)

    # Plugin preferences are stored separately by DMS. Enable this extension
    # initially, while preserving later GUI choices and other plugins.
    if defaults.get("plugins"):
        plugins_path = config_home / "DankMaterialShell/plugin_settings.json"
        plugins = read_object(plugins_path)
        for name, options in defaults["plugins"].items():
            current = plugins.setdefault(name, {})
            for key, value in options.items():
                current.setdefault(key, value)
        write_object(plugins_path, plugins)

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


def migrate_running_apps(settings: dict) -> None:
    """Change the existing bars once; later GUI customization survives rebuilds."""
    options = {"runningAppsCurrentWorkspace": False, "runningAppsCurrentMonitor": False,
               "runningAppsGroupByApp": True, "runningAppsCompactMode": True}
    settings.update(options)
    for bar in settings.get("barConfigs", []):
        groups = [bar.setdefault(key, []) for key in ("leftWidgets", "centerWidgets", "rightWidgets")]
        def widget_id(widget):
            return widget if isinstance(widget, str) else widget.get("id", widget.get("widgetId"))
        present = any(widget_id(w) == "runningApps" for group in groups for w in group)
        for group in groups:
            replacement = []
            for widget in group:
                name = widget_id(widget)
                if name == "focusedWindow":
                    if present:
                        continue
                    widget = "runningApps"
                    present = True
                elif name == "runningApps" and isinstance(widget, dict):
                    widget.update(options)
                replacement.append(widget)
            group[:] = replacement
        if not present:
            groups[0].append("runningApps")


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
