from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FlakeProfileTests(unittest.TestCase):
    def run_script(self, script, marker=None, override=None, args=(), configured='nixos'):
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
            commands = {
                'git': 'printf "git %s\\n" "$*" >> "$TEST_LOG"',
                'nix': 'printf "nix %s\\n" "$*" >> "$TEST_LOG"; printf %s "$CONFIGURED_HOST"',
                'sudo': 'printf "sudo %s\\n" "$*" >> "$TEST_LOG"',
            }
            for name, body in commands.items():
                stub = base / name
                stub.write_text('#!/bin/sh\n' + body + '\n')
                stub.chmod(0o755)
            env = dict(os.environ, PATH=str(base) + ':' + os.environ['PATH'],
                       TEST_LOG=str(log), TARGET_HOST='nixos', CONFIGURED_HOST=configured)
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

    def test_wrong_host_is_rejected_before_rebuild(self):
        for script in ('install.sh', 'update.sh'):
            with self.subTest(script=script):
                result, log = self.run_script(script, marker='nixos-windows', configured='other')
                self.assertEqual(result.returncode, 2)
                self.assertNotIn('sudo', log)


if __name__ == '__main__':
    unittest.main()
