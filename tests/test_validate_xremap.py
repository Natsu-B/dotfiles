"""Regression tests for the CI parser check; these do not access input devices."""
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from validate_xremap import (
    CONFIG_ERROR, DEVICE_ERRORS, parse, reached_device_selection,
    require_parser_rejection, validate,
)


class XremapParserCheckTests(unittest.TestCase):
    def test_empty_and_missing_input_directory_are_post_parse(self):
        for message in DEVICE_ERRORS:
            with self.subTest(message=message):
                self.assertTrue(reached_device_selection(message + "\n"))

    def test_unrelated_failures_are_not_accepted(self):
        for message in (
            "Error: Failed to read /dev/input: Permission denied (os error 13)",
            "error: unexpected argument '--no-window-logging' found",
            "thread 'main' panicked", "", "Error: Failed to create output device",
        ):
            with self.subTest(message=message):
                self.assertFalse(reached_device_selection(message))

    def test_error_substrings_are_not_accepted(self):
        for message in DEVICE_ERRORS:
            self.assertFalse(reached_device_selection("unexpected: " + message))

    def test_config_error_cannot_be_misread_as_success(self):
        message = next(iter(DEVICE_ERRORS))
        self.assertFalse(reached_device_selection(CONFIG_ERROR + "'invalid.yml'\n" + message))

    def test_negative_control_must_fail_in_config_parser(self):
        require_parser_rejection(CONFIG_ERROR + "'invalid.yml': unknown key\n")
        for message in [*DEVICE_ERRORS, "error: unexpected argument", ""]:
            with self.subTest(message=message):
                with self.assertRaises(RuntimeError):
                    require_parser_rejection(message)

    def test_negative_control_rejects_mixed_errors(self):
        with self.assertRaises(RuntimeError):
            require_parser_rejection(CONFIG_ERROR + "'invalid.yml'\n" + next(iter(DEVICE_ERRORS)))

    @patch("validate_xremap.subprocess.run")
    def test_parse_requires_expected_exit_status(self, run):
        for status in (0, 2, -9):
            run.return_value = subprocess.CompletedProcess([], status, next(iter(DEVICE_ERRORS)))
            with self.subTest(status=status), redirect_stdout(StringIO()):
                with self.assertRaises(RuntimeError):
                    parse(Path("profile.yml"))

    @patch("validate_xremap.subprocess.run")
    def test_device_probe_is_explicit_and_bounded(self, run):
        run.return_value = subprocess.CompletedProcess([], 1, next(iter(DEVICE_ERRORS)))
        with redirect_stdout(StringIO()):
            parse(Path("profile.yml"))
        args, kwargs = run.call_args
        command = args[0]
        self.assertIn("--output-device-name", command)
        self.assertIn("/dev/input/dotfiles-ci-no-device", command)
        self.assertFalse(any(arg.startswith("--watch") for arg in command))
        self.assertEqual(kwargs["timeout"], 10)

    @patch("validate_xremap.subprocess.run")
    def test_timeout_is_not_a_success(self, run):
        run.side_effect = subprocess.TimeoutExpired("xremap", 10)
        with self.assertRaises(subprocess.TimeoutExpired):
            parse(Path("profile.yml"))

    @patch("validate_xremap.parse")
    @patch("validate_xremap.subprocess.run")
    def test_controls_run_before_both_profiles(self, run, probe):
        run.return_value.stdout = "--watch --no-window-logging --output-device-name"
        probe.side_effect = [
            CONFIG_ERROR + "'invalid-key.yml': bad key",
            CONFIG_ERROR + "'malformed-yaml.yml': bad YAML",
            *sorted(DEVICE_ERRORS),
        ]
        with redirect_stdout(StringIO()):
            validate(Path("/profiles"))
        self.assertEqual(
            [call.args[0].name for call in probe.call_args_list],
            ["invalid-key.yml", "malformed-yaml.yml", "qwerty.yml", "dvorak.yml"],
        )

    @patch("validate_xremap.parse")
    @patch("validate_xremap.subprocess.run")
    def test_validation_aborts_when_parser_is_not_reached(self, run, probe):
        run.return_value.stdout = "--watch --no-window-logging --output-device-name"
        probe.return_value = next(iter(DEVICE_ERRORS))
        with self.assertRaises(RuntimeError):
            validate(Path("/profiles"))
        self.assertEqual(probe.call_count, 1)


if __name__ == "__main__":
    unittest.main()
