from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DesktopRecoveryTests(unittest.TestCase):
    def test_cursor_theme_is_explicit_and_shared(self):
        text = (ROOT / "home/desktop/cursor.nix").read_text(encoding="utf-8")
        self.assertIn('package = pkgs.adwaita-icon-theme;', text)
        self.assertIn('name = "Adwaita";', text)
        self.assertIn('gtk.enable = true;', text)
        self.assertIn('x11.enable = true;', text)
        self.assertIn('cursor-theme = "Adwaita";', text)

    def test_hyprland_does_not_force_scale_one(self):
        text = (ROOT / "home/desktop/hypr/hyprland.lua").read_text(encoding="utf-8")
        self.assertIn('scale = "auto"', text)
        self.assertNotIn('scale = 1 })', text)

    def test_emergency_terminal_does_not_depend_on_super(self):
        text = (ROOT / "home/desktop/hypr/binds.lua").read_text(encoding="utf-8")
        self.assertIn('CTRL + ALT + T', text)
        self.assertIn('Emergency terminal', text)


if __name__ == "__main__":
    unittest.main()
