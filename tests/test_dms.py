"""DMS migration tests; no compositor required."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DESKTOP = ROOT / 'home/desktop'
spec = importlib.util.spec_from_file_location('seed_dms', DESKTOP / 'seed_dms.py')
seed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(seed)
DEFAULTS = {'settings': {'acLockTimeout': 300, 'showWeather': False},
            'policy': {'customPowerActionLock': '/bin/desktop-lock'},
            'session': {'wallpaperPath': '/home/u/wallpaper.png'}}

class SeedTests(unittest.TestCase):
    def test_hibernate_policy_migrates_without_enabling_idle_suspend(self):
        defaults = dict(DEFAULTS, settings=dict(DEFAULTS['settings'], acSuspendBehavior=1,
                        batterySuspendBehavior=1, acSuspendTimeout=0, batterySuspendTimeout=0))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); config = root / 'config'; state = root / 'state'
            path = config / 'DankMaterialShell/settings.json'
            path.parent.mkdir(parents=True)
            path.write_text(json.dumps({'acSuspendBehavior': 0, 'batterySuspendBehavior': 0,
                                        'acSuspendTimeout': 1200, 'theme': 'mine'}))
            seed.seed(config, state, defaults)
            data = json.loads(path.read_text())
            self.assertEqual(data['acSuspendBehavior'], 1)
            self.assertEqual(data['batterySuspendBehavior'], 1)
            self.assertEqual(data['acSuspendTimeout'], 1200)
            self.assertEqual(data['batterySuspendTimeout'], 0)
            self.assertEqual(data['theme'], 'mine')
            data['batterySuspendBehavior'] = 2
            path.write_text(json.dumps(data))
            seed.seed(config, state, defaults)
            self.assertEqual(json.loads(path.read_text()), data)

    def test_first_start_creates_writable_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            seed.seed(root / 'config', root / 'state', DEFAULTS)
            for path in root.rglob('*'):
                if path.is_file():
                    self.assertFalse(path.is_symlink())
                    self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertTrue((root / 'config/hypr/dms/outputs.lua').exists())
    def test_gui_choices_survive_rebuild(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); config = root / 'config'; state = root / 'state'
            seed.seed(config, state, DEFAULTS)
            settings = config / 'DankMaterialShell/settings.json'
            settings.write_text(json.dumps({'acLockTimeout': 900, 'theme': 'my-theme', 'customPowerActionLock': '/old/store/lock'}))
            session = state / 'DankMaterialShell/session.json'
            session.write_text(json.dumps({'wallpaperPath': '/home/u/another.png'}))
            outputs = config / 'hypr/dms/outputs.lua'
            outputs.write_text('-- user-selected arrangement\n')
            seed.seed(config, state, DEFAULTS)
            data = json.loads(settings.read_text())
            self.assertEqual(data['acLockTimeout'], 900)
            self.assertEqual(data['theme'], 'my-theme')
            self.assertEqual(data['customPowerActionLock'], '/bin/desktop-lock')
            self.assertEqual(json.loads(session.read_text())['wallpaperPath'], '/home/u/another.png')
            self.assertEqual(outputs.read_text(), '-- user-selected arrangement\n')
    def test_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            seed.seed(root / 'config', root / 'state', DEFAULTS)
            before = {str(p): (p.read_bytes(), p.stat().st_mtime_ns) for p in root.rglob('*') if p.is_file()}
            seed.seed(root / 'config', root / 'state', DEFAULTS)
            after = {str(p): (p.read_bytes(), p.stat().st_mtime_ns) for p in root.rglob('*') if p.is_file()}
            self.assertEqual(before, after)
    def test_bad_json_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); path = root / 'DankMaterialShell/settings.json'
            path.parent.mkdir(); path.write_text('{ broken')
            with self.assertRaises(ValueError): seed.seed(root, root / 'state', DEFAULTS)
            self.assertEqual(path.read_text(), '{ broken')
    def test_symlink_is_not_followed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); path = root / 'DankMaterialShell/settings.json'
            path.parent.mkdir(); target = root / 'target'; target.write_text('{}')
            path.symlink_to(target)
            with self.assertRaises(ValueError): seed.seed(root, root / 'state', DEFAULTS)
            self.assertEqual(target.read_text(), '{}')

class MigrationTests(unittest.TestCase):
    def test_private_history_policy(self):
        text = (DESKTOP / 'dms.nix').read_text()
        self.assertIn('"DankMaterialShell/clsettings.json"', text)
        self.assertIn('disabled = true;', text)
        self.assertNotIn('"DankMaterialShell/settings.json".text', text)
        self.assertNotIn('"hypr/dms/outputs.lua".text', text)
    def test_no_duplicate_shell_services(self):
        text = (DESKTOP / 'default.nix').read_text()
        self.assertNotIn('./waybar.nix', text)
        for name in ('dotfiles-hyprpaper =', 'dotfiles-notifications =', 'dotfiles-polkit ='):
            self.assertNotIn(name, text)
        # DMS startup belongs to the NixOS module / upstream packaged service.
        self.assertNotIn('systemd.user.services.dms', (DESKTOP / 'dms.nix').read_text())

    def test_dms_uses_upstream_systemd_service(self):
        text = (ROOT / 'nixos/desktop.nix').read_text()
        self.assertIn('programs.dms-shell', text)
        self.assertIn('systemd = {', text)
        self.assertIn('enable = true;', text)
        self.assertIn('target = "graphical-session.target";', text)
        self.assertIn('ConditionEnvironment =', text)
        self.assertIn('"XDG_CURRENT_DESKTOP=Hyprland"', text)
        self.assertNotIn('systemd.enable = false;', text)
    def test_zoom_and_portal_routing(self):
        text = (ROOT / 'nixos/desktop.nix').read_text()
        self.assertIn('programs.zoom-us.enable = true;', text)
        self.assertIn('xdg.portal.config.hyprland', text)
        self.assertNotIn('xdg.portal.config.Hyprland', text)
        self.assertNotIn('pkgs.zoom-us', (ROOT / 'home/home.nix').read_text())
    def test_release_and_state_versions(self):
        text = (ROOT / 'flake.nix').read_text()
        self.assertIn('nixos-26.05', text); self.assertIn('release-26.05', text)
        lock = json.loads((ROOT / 'flake.lock').read_text())['nodes']
        self.assertEqual(lock[lock['root']['inputs']['nixpkgs']]['original']['ref'], 'nixos-26.05')
        self.assertIn('stateVersion = "25.11"', (ROOT / 'home/home.nix').read_text())
        self.assertIn('stateVersion = "24.05"', (ROOT / 'nixos/configuration.nix').read_text())
    def test_failed_lock_never_unlocks_or_resumes(self):
        for failed in (False, True):
            with self.subTest(failed=failed), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); binaries = root / 'bin'; binaries.mkdir()
                log = root / 'calls'
                for name in ('desktop-clipboard', 'loginctl', 'notify-send', 'systemctl', 'hyprlock'):
                    status = 1 if name == 'hyprlock' and failed else 0
                    file = binaries / name
                    file.write_text(f'#!/bin/sh\nprintf "%s\\n" "{name} $*" >> "$CALL_LOG"\nexit {status}\n')
                    file.chmod(0o755)
                env = dict(os.environ, PATH=str(binaries) + ':' + os.environ['PATH'], XDG_RUNTIME_DIR=directory, CALL_LOG=str(log))
                result = subprocess.run(['bash', str(DESKTOP / 'lock.sh')], env=env)
                calls = log.read_text()
                self.assertIn('desktop-clipboard pause', calls)
                self.assertEqual(result.returncode, int(failed))
                if failed:
                    self.assertNotIn('loginctl unlock-session', calls)
                    self.assertNotIn('desktop-clipboard resume', calls)
                    self.assertTrue((root / 'dotfiles-screen-locked').exists())
                else:
                    self.assertIn('loginctl unlock-session', calls)
                    self.assertIn('desktop-clipboard resume', calls)
                    self.assertFalse((root / 'dotfiles-screen-locked').exists())

if __name__ == '__main__':
    unittest.main()
