"""Exercise CFU-Proving-Ground's make argument adapter without FPGA tools."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "cfu-make.sh"


class CFUMakeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.log = self.root / "make-args"
        make = self.root / "fake-make"
        make.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$CFU_TEST_LOG"\n')
        make.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update({
            "CFU_PG_MAKE": str(make),
            "CFU_PG_GCC": "/opt/riscv tool/bin/riscv32-none-elf-gcc",
            "CFU_PG_GPP": "/opt/riscv tool/bin/riscv32-none-elf-g++",
            "CFU_PG_OBJCOPY": "/opt/riscv tool/bin/riscv32-none-elf-objcopy",
            "CFU_PG_OBJDUMP": "/opt/riscv tool/bin/riscv32-none-elf-objdump",
            "CFU_PG_VERILATOR": "/opt/verilator/bin/verilator",
            "CFU_PG_VIVADO": "/nix/store/vivado/bin/vivado",
            "CFU_TEST_LOG": str(self.log),
        })
        self.env.pop("CFU_PG_VPP", None)

    def run_make(self, *args, env=None):
        return subprocess.run(
            ["bash", str(SCRIPT), *args], env=env or self.env,
            capture_output=True, text=True,
        )

    def test_makefile_paths_are_overridden(self):
        result = self.run_make("-C", "checkout path", "prog", "TARGET=nexys_a7")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.log.read_text().splitlines()
        self.assertEqual(args[:7], [
            "GCC=/opt/riscv tool/bin/riscv32-none-elf-gcc",
            "GPP=/opt/riscv tool/bin/riscv32-none-elf-g++",
            "OBJCOPY=/opt/riscv tool/bin/riscv32-none-elf-objcopy",
            "OBJDUMP=/opt/riscv tool/bin/riscv32-none-elf-objdump",
            "RTLSIM=/opt/verilator/bin/verilator",
            "VIVADO=/nix/store/vivado/bin/vivado",
            "VPP=v++",
        ])
        self.assertEqual(args[7:], ["-C", "checkout path", "prog", "TARGET=nexys_a7"])

    def test_vitis_can_be_explicitly_selected(self):
        env = dict(self.env, CFU_PG_VPP="/opt/Vitis/2024.2/bin/v++")
        result = self.run_make("vpp", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("VPP=/opt/Vitis/2024.2/bin/v++", self.log.read_text())

    def test_missing_compiler_does_not_invoke_make(self):
        env = self.env.copy()
        del env["CFU_PG_GCC"]
        result = self.run_make("prog", env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("RISC-V GCC is not configured", result.stderr)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
