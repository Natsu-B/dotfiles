"""Execute the real remote listing payload against a temporary archive."""
import base64
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/mac-data-sync-browse'


class RemoteListingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.archive = Path(self.temporary.name) / 'data'
        self.archive.mkdir()
        folder = self.archive / '日本語 folder'
        folder.mkdir()
        (folder / 'report.txt').write_text('nested content')
        (self.archive / 'root.txt').write_text('root content')
        (self.archive / 'link').symlink_to(folder, target_is_directory=True)
        # Run precisely the quoted heredoc sent through SSH. Adapt only the
        # macOS utility paths and archive location for the Linux test runner.
        self.payload = SCRIPT.read_text().split("<<'REMOTE'\n", 1)[1].split('\nREMOTE\n', 1)[0]
        self.payload = self.payload.replace('"$HOME/data"', shlex.quote(str(self.archive)))
        self.payload = self.payload.replace('/usr/bin/base64 -D', shlex.quote(shutil.which('base64')) + ' -d')
        self.payload = self.payload.replace('/usr/bin/find', shlex.quote(shutil.which('find')))

    def listing(self, relative):
        env = dict(os.environ, MAC_REL_B64=base64.b64encode(relative.encode()).decode())
        return subprocess.run(['bash', '-s'], input=self.payload, env=env,
                              text=True, capture_output=True)

    def test_root_uses_actual_names_and_remains_shallow(self):
        result = self.listing('')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertCountEqual(result.stdout.rstrip('\x00').split('\x00'),
                              ['D\t日本語 folder', 'F\troot.txt'])

    def test_nested_folder_with_unicode_and_spaces(self):
        result = self.listing('日本語 folder')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'F\treport.txt\x00')

    def test_symlinks_and_traversal_cannot_be_opened(self):
        for relative in ('link', '..', '../data', '日本語 folder/..'):
            with self.subTest(relative=relative):
                self.assertNotEqual(self.listing(relative).returncode, 0)


if __name__ == '__main__':
    unittest.main()
