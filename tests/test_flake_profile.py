from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FlakeProfileTests(unittest.TestCase):
    def run_script(self, script, marker=None, override=None, args=(), configured='nixos', device_state='valid', missing_mount=''):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            log = base / 'commands'
            profile = base / 'profile'
            if marker is not None:
                profile.write_text(marker + '\n')
            # Isolate the machine-specific profile marker; execute the actual script.
            source = (ROOT / script).read_text().replace(
                '/etc/dotfiles-nixos-flake-profile', str(profile))
            runner = base / script
            runner.write_text(source)
            (base / 'scripts').mkdir()
            (base / 'scripts/check-boot-filesystems.sh').write_text(
                (ROOT / 'scripts/check-boot-filesystems.sh').read_text())
            mounted = base / 'mounted-device'
            mounted.touch()
            expected = base / 'configured-device'
            if device_state == 'valid':
                expected.symlink_to(mounted)
            elif device_state == 'wrong':
                expected.touch()
            # 'missing' models the obsolete UUID's absent /dev/disk/by-uuid link.
            commands = {
                'git': 'printf "git %s\\n" "$*" >> "$TEST_LOG"',
                'nix': 'printf "nix %s\\n" "$*" >> "$TEST_LOG"; '
                       'case "$*" in *networking.hostName) printf %s "$CONFIGURED_HOST" ;; '
                       '*) printf %s "$EXPECTED_DEVICE" ;; esac',
                'findmnt': 'printf "findmnt %s\\n" "$*" >> "$TEST_LOG"; '
                           '[ "$6" != "$MISSING_MOUNT" ] || exit 1; printf %s "$MOUNTED_DEVICE"',
                'sudo': 'printf "sudo %s\\n" "$*" >> "$TEST_LOG"',
            }
            for name, body in commands.items():
                stub = base / name
                stub.write_text('#!/bin/sh\n' + body + '\n')
                stub.chmod(0o755)
            env = dict(os.environ, PATH=str(base) + ':' + os.environ['PATH'],
                       TEST_LOG=str(log), TARGET_HOST='nixos', CONFIGURED_HOST=configured, EXPECTED_DEVICE=str(expected),
                       MOUNTED_DEVICE=str(mounted), MISSING_MOUNT=missing_mount)
            env.pop('NIXOS_FLAKE_PROFILE', None)
            if override is not None:
                env['NIXOS_FLAKE_PROFILE'] = override
            result = subprocess.run(['sh', str(runner), *args], env=env,
                                    capture_output=True, text=True)
            return result, log.read_text()

    def test_windows_marker_is_used_by_both_scripts(self):
        for script in ('install.sh', 'update.sh'):
            with self.subTest(script=script):
                result, log = self.run_script(script, marker='nixos-windows')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('sudo nixos-rebuild switch --flake .#nixos-windows', log)
                self.assertNotIn('sudo nixos-rebuild switch --flake .#nixos\n', log)
                if script == 'update.sh':
                    self.assertIn('git pull --ff-only', log)
                else:
                    self.assertNotIn('git pull', log)

    def test_profile_precedence_and_hostname_fallback(self):
        for script in ('install.sh', 'update.sh'):
            for marker, override, args, expected in (
                (None, None, (), 'nixos'),
                ('nixos-windows', 'nixos', (), 'nixos'),
                ('nixos', 'nixos', ('nixos-windows',), 'nixos-windows'),
            ):
                with self.subTest(script=script, expected=expected, args=args):
                    result, log = self.run_script(script, marker, override, args)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn('sudo nixos-rebuild switch --flake .#' + expected + '\n', log)

    def test_stale_uuid_is_rejected_before_rebuild(self):
        for script in ('install.sh', 'update.sh'):
            with self.subTest(script=script):
                result, log = self.run_script(script, marker='nixos-windows', device_state='missing')
                self.assertEqual(result.returncode, 2)
                self.assertIn('references missing device', result.stderr)
                self.assertNotIn('sudo', log)

    def test_existing_but_wrong_device_is_rejected_before_rebuild(self):
        for script in ('install.sh', 'update.sh'):
            with self.subTest(script=script):
                result, log = self.run_script(script, marker='nixos-windows', device_state='wrong')
                self.assertEqual(result.returncode, 2)
                self.assertIn('Refusing to change boot configuration', result.stderr)
                self.assertNotIn('sudo', log)

    def test_shared_esp_must_be_mounted(self):
        for script in ('install.sh', 'update.sh'):
            with self.subTest(script=script):
                result, log = self.run_script(script, marker='nixos-windows', missing_mount='/efi')
                self.assertEqual(result.returncode, 2)
                self.assertIn('/efi is not mounted', result.stderr)
                self.assertNotIn('sudo', log)

    def test_wrong_host_is_rejected_before_rebuild(self):
        for script in ('install.sh', 'update.sh'):
            with self.subTest(script=script):
                result, log = self.run_script(script, marker='nixos-windows', configured='other')
                self.assertEqual(result.returncode, 2)
                self.assertNotIn('sudo', log)


if __name__ == '__main__':
    unittest.main()
