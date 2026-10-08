"""Check SSH routing, argument preservation and terminal compatibility offline."""
import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
ZSH = shutil.which('zsh')


@unittest.skipUnless(ZSH, 'requires zsh')
class SshTests(unittest.TestCase):
    def test_kitty_and_normal_ssh_preserve_arguments_and_exit_status(self):
        arguments = ['-p', '2222', 'user@example.invalid', 'printf %s "a b"']
        command = ('PATH="$1"; shift; source "$1"; shift; task_term_before=$TERM; ssh "$@"; '
                   'task_ssh_result=$?; [[ $TERM == $task_term_before ]] || exit 99; '
                   'exit "$task_ssh_result"')
        cases = [
            ('xterm-kitty', True, True, True, 'kitten', 'xterm-kitty'),
            ('xterm-kitty', False, True, True, 'ssh', 'xterm-256color'),
            ('xterm-kitty', True, False, True, 'ssh', 'xterm-256color'),
            ('xterm-kitty', True, True, False, 'ssh', 'xterm-256color'),
            ('xterm-256color', True, True, True, 'ssh', 'xterm-256color'),
        ]
        for term, tty, helper, window, expected, remote_term in cases:
            with self.subTest(term=term, tty=tty, helper=helper, window=window), tempfile.TemporaryDirectory() as directory:
                for name in ['ssh', *(['kitten'] if helper else [])]:
                    path = Path(directory) / name
                    path.write_text(f'#!{sys.executable}\nimport json, os, sys\n'
                                    f'print(json.dumps([{name!r}, os.environ["TERM"], sys.argv[1:]]))\n'
                                    'sys.exit(17)\n')
                    path.chmod(0o755)
                env = {**os.environ, 'PATH': directory, 'TERM': term,
                       'KITTY_WINDOW_ID': '1' if window else ''}
                master, slave = pty.openpty()
                try:
                    result = subprocess.run(
                        [ZSH, '-f', '-c', command, 'ssh-test', directory, str(ROOT / 'home/ssh.zsh'), *arguments],
                        env=env, stdin=slave if tty else subprocess.DEVNULL,
                        stdout=slave if tty else subprocess.PIPE,
                        stderr=subprocess.PIPE, timeout=5)
                    if tty:
                        self.assertTrue(select.select([master], [], [], 1)[0], result.stderr.decode())
                    output = os.read(master, 4096) if tty else result.stdout
                finally:
                    os.close(slave)
                    os.close(master)
                self.assertEqual(result.returncode, 17, result.stderr.decode())
                self.assertEqual(json.loads(output),
                                 [expected, remote_term, (['ssh'] if expected == 'kitten' else []) + arguments])


if __name__ == '__main__':
    unittest.main()
