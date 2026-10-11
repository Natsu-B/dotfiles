from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ReproducibilityTests(unittest.TestCase):
    def test_gef_fetch_uses_immutable_commit(self):
        text = (ROOT / "home/app/gef.nix").read_text(encoding="utf-8")
        match = re.search(r'\brev\s*=\s*"([^"]+)";', text)
        self.assertIsNotNone(match, "GEF fetchFromGitHub rev is missing")
        self.assertRegex(
            match.group(1),
            r"^[0-9a-f]{40}$",
            "GEF must be pinned to an immutable Git commit, not a moving branch/tag",
        )
        self.assertNotIn('rev = version;', text)
        self.assertRegex(text, r'\bhash\s*=\s*"sha256-[^"]+";')


if __name__ == "__main__":
    unittest.main()
