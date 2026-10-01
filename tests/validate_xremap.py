"""Check the locked xremap parser without access to real input devices.

This binary has no --validate-config. It loads the config before selecting
input devices, so only its specific no-device error is accepted after parsing.
An invalid-key negative control must fail before reaching that point.
"""
from pathlib import Path
import json
import subprocess
import sys
import tempfile

NO_DEVICE = "Failed to prepare input devices: No device was selected!"


def parse(path: Path) -> str:
    result = subprocess.run(
        ["xremap", "--no-window-logging", "--device", "/dev/input/dotfiles-ci-no-device", str(path)],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=10,
    )
    print(f"{path.name}: exit={result.returncode}\n{result.stdout}", flush=True)
    if result.returncode != 1:
        raise RuntimeError("Unexpected xremap exit status; this is not a parser check")
    return result.stdout


help_text = subprocess.run(["xremap", "--help"], check=True, capture_output=True, text=True).stdout
assert "--watch" in help_text and "--no-window-logging" in help_text
profiles = Path(sys.argv[1])
for name in ("qwerty", "dvorak"):
    output = parse(profiles / f"{name}.yml")
    if NO_DEVICE not in output:
        raise RuntimeError(f"{name}: did not reach device selection after config parsing")

with tempfile.TemporaryDirectory() as directory:
    invalid = Path(directory) / "invalid.yml"
    invalid.write_text(json.dumps({"modmap": [{"remap": {"NOT_A_REAL_KEY_DOTFILES": "A"}}]}))
    if NO_DEVICE in parse(invalid):
        raise RuntimeError("Negative control reached device selection: parser validation is ineffective")
print("xremap: both profiles parsed; invalid-key negative control rejected")
