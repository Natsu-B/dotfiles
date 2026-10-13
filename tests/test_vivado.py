"""Contract tests for the Vivado launcher without distributing proprietary files."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "vivado.sh"


class VivadoLauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root / "launched"
        self.fhs = self.root / "vivado-fhs"
        # Model buildFHSEnv's 'bash' runScript and its argv forwarding.
        self.fhs.write_text('#!/bin/sh\nexec bash "$@"\n')
        self.fhs.chmod(0o755)

    def install(self, path):
        path.mkdir(parents=True)
        (path / "bin").mkdir()
        (path / "settings64.sh").write_text('export VIVADO_TEST_SETTINGS=loaded\n')
        binary = path / "bin" / "vivado"
        binary.write_text(
            '#!/bin/bash\n'
            'printf "%s\\n" "$VIVADO_TEST_SETTINGS" "$@" > "$VIVADO_TEST_LOG"\n'
        )
        binary.chmod(0o755)
        return path

    def run_launcher(self, *args, **environment):
        env = os.environ.copy()
        env.pop("XILINX_VIVADO", None)
        env["VIVADO_INSTALL_ROOT"] = str(self.root / "install")
        env["VIVADO_TEST_LOG"] = str(self.log)
        env.update({name: str(value) for name, value in environment.items()})
        return subprocess.run(
            ["bash", str(SCRIPT), str(self.fhs), *args],
            env=env, capture_output=True, text=True,
        )

    def test_modern_layout_forwards_args_and_sources_settings(self):
        self.install(self.root / "install" / "2025.2" / "Vivado")
        result = self.run_launcher("-mode", "batch", "-source", "my project.tcl")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(),
                         ["loaded", "-mode", "batch", "-source", "my project.tcl"])

    def test_legacy_layout(self):
        self.install(self.root / "install" / "Vivado" / "2024.2")
        result = self.run_launcher("-version")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ["loaded", "-version"])

    def test_absent_installation_fails_before_running_fhs(self):
        result = self.run_launcher()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("installation not found", result.stderr)
        self.assertFalse(self.log.exists())

    def test_multiple_installs_require_explicit_selection(self):
        older = self.install(self.root / "install" / "Vivado" / "2024.2")
        self.install(self.root / "install" / "2025.2" / "Vivado")
        result = self.run_launcher()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("multiple installations", result.stderr)
        self.assertFalse(self.log.exists())
        result = self.run_launcher("-version", XILINX_VIVADO=older)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ["loaded", "-version"])

    def test_incomplete_explicit_installation_fails(self):
        result = self.run_launcher(XILINX_VIVADO=self.root / "missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected settings64.sh", result.stderr)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
