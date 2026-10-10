"""Check the locked xremap parser without opening real input devices.

The pinned binary has no --validate-config. In v0.15.13, load_configs runs
before select_input_devices (src/main_impl.rs). Accept only the two specific
post-parse failures for an empty or missing /dev/input. Never accept arbitrary
exit=1 results: malformed-YAML and invalid-key controls must fail in the parser.
"""
from pathlib import Path
import json
import subprocess
import sys
import tempfile

# Nix sandboxes may omit /dev/input entirely, not just provide an empty one.
DEVICE_ERRORS = frozenset({
    "Error: Failed to prepare input devices: No device was selected!",
    "Error: Failed to read /dev/input: No such file or directory (os error 2)",
})
CONFIG_ERROR = "Error: Failed to load config "


def reached_device_selection(output: str) -> bool:
    lines = output.splitlines()
    # A config failure is never a successful parser check, even if its message
    # happens to quote a device-error string.
    return (
        not any(line.startswith(CONFIG_ERROR) for line in lines)
        and bool(DEVICE_ERRORS.intersection(lines))
    )


def parse(path: Path) -> str:
    result = subprocess.run(
        [
            "xremap", "--no-window-logging",
            # Skip automatic device-name discovery before config parsing.
            "--output-device-name", "dotfiles-ci-parser-check",
            "--device", "/dev/input/dotfiles-ci-no-device", str(path),
        ],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=10,
    )
    print(f"{path.name}: exit={result.returncode}\n{result.stdout}", flush=True)
    if result.returncode != 1:
        raise RuntimeError("Unexpected xremap exit status; this is not a parser check")
    return result.stdout


def require_parser_rejection(output: str) -> None:
    lines = output.splitlines()
    if not any(line.startswith(CONFIG_ERROR) for line in lines):
        raise RuntimeError("Negative control did not fail while loading its config")
    if DEVICE_ERRORS.intersection(lines):
        raise RuntimeError("Negative control reached device selection; validation is ineffective")


def validate(profiles: Path) -> None:
    help_text = subprocess.run(
        ["xremap", "--help"], check=True, capture_output=True, text=True,
    ).stdout
    for option in ("--watch", "--no-window-logging", "--output-device-name"):
        if option not in help_text:
            raise RuntimeError(f"Pinned xremap is missing the expected option: {option}")

    # Check the premise first: a binary that fails before parsing must not make
    # the valid-profile checks pass merely because the CI runner has no devices.
    with tempfile.TemporaryDirectory() as directory:
        controls = {
            "invalid-key": json.dumps({
                "modmap": [{"remap": {"NOT_A_REAL_KEY_DOTFILES": "A"}}],
            }),
            "malformed-yaml": "modmap: [\n",
        }
        for name, contents in controls.items():
            invalid = Path(directory) / f"{name}.yml"
            invalid.write_text(contents, encoding="utf-8")
            require_parser_rejection(parse(invalid))

    for name in ("qwerty", "dvorak"):
        if not reached_device_selection(parse(profiles / f"{name}.yml")):
            raise RuntimeError(f"{name}: did not reach device selection after config parsing")
    print("xremap: both profiles parsed; invalid-key and malformed-YAML controls rejected")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate_xremap.py PROFILE_DIRECTORY")
    validate(Path(sys.argv[1]))
