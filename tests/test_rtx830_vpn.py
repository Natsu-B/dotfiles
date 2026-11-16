"""Offline checks for the RTX830 routing guard (no network or root required)."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "rtx830-vpn"
MODULE = ROOT / "nixos" / "rtx830-vpn.nix"
DOC = ROOT / "RTX830-VPN.md"


class Rtx830VpnTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        fake_bin = self.base / "bin"
        fake_bin.mkdir()
        self.log = self.base / "commands.log"
        self.log.touch()
        self.state = self.base / "state"
        self.env = dict(os.environ, PATH=f"{fake_bin}:{os.environ['PATH']}",
                        VPN_TEST_LOG=str(self.log), RTX830_STATE_DIR=str(self.state))
        self.write_mock("nmcli", """#!/usr/bin/env bash
printf 'nmcli %s\\n' "$*" >> "$VPN_TEST_LOG"
case "$*" in
  '-g connection.type connection show rtx830-vpn') echo vpn ;;
  '-g vpn.service-type connection show rtx830-vpn') echo org.freedesktop.NetworkManager.l2tp ;;
  '-g vpn.data connection show rtx830-vpn') echo 'ipsec-enabled = yes, gateway = private.example.invalid, ipsec-forceencaps = yes' ;;
  '--ask --wait 60 connection up id rtx830-vpn') [[ ${VPN_TEST_CONNECT_FAIL:-0} == 0 ]] ;;
  'connection down id rtx830-vpn') : ;;
  *) exit 12 ;;
esac
""")
        self.write_mock("getent", """#!/usr/bin/env bash
printf 'getent %s\\n' "$*" >> "$VPN_TEST_LOG"
echo '198.51.100.20 STREAM private.example.invalid'
""")
        self.write_mock("ip", """#!/usr/bin/env bash
printf 'ip %s\\n' "$*" >> "$VPN_TEST_LOG"
case "$*" in
  '-4 route get 198.51.100.20')
    if [[ ${VPN_TEST_OVERLAY:-0} == 1 ]]; then
      echo '198.51.100.20 dev tailscale0 src 100.64.0.1'
    else
      echo '198.51.100.20 via 192.0.2.1 dev enp0s1 src 192.0.2.3'
    fi ;;
  '-4 route show table 193')
    if [[ ${VPN_TEST_COLLISION:-0} == 1 ]]; then
      echo 'unrelated route'
    fi ;;
  '-4 rule show')
    if [[ -e "$RTX830_STATE_DIR/endpoint" ]]; then
      echo '110: from all to 198.51.100.20 lookup 193'
    fi ;;
  '-4 route replace '*|'-4 route del '*|'-4 rule add '*|'-4 rule del '*) : ;;
  *) exit 11 ;;
esac
""")

    def write_mock(self, name, content):
        path = self.base / "bin" / name
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    def run_script(self, command, overrides=None):
        env = self.env | (overrides or {})
        # Tests bypass the user check *inside the sourced script*, but the
        # production executable still requires EUID 0 for changing routes.
        code = 'source "$1"; need_root() { :; }; main "$2"'
        return subprocess.run(["bash", "-c", code, "bash", str(SCRIPT), command],
                              env=env, text=True, capture_output=True)

    def lines(self):
        return self.log.read_text(encoding="utf-8").splitlines()

    def test_check_does_not_modify_routes(self):
        result = self.run_script("check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any("route replace" in x or "rule add" in x for x in self.lines()))

    def test_up_pins_underlay_before_nmcli_connects(self):
        result = self.run_script("up")
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.lines()
        pin = log.index("ip -4 route replace 198.51.100.20/32 via 192.0.2.1 dev enp0s1 table 193")
        add = log.index("ip -4 rule add to 198.51.100.20/32 lookup 193 priority 110")
        connect = log.index("nmcli --ask --wait 60 connection up id rtx830-vpn")
        self.assertLess(pin, add)
        self.assertLess(add, connect)
        self.assertEqual((self.state / "endpoint").read_text(), "198.51.100.20\n")

    def test_failed_connection_cleans_policy(self):
        result = self.run_script("up", {"VPN_TEST_CONNECT_FAIL": "1"})
        self.assertNotEqual(result.returncode, 0)
        log = self.lines()
        self.assertIn("ip -4 rule del to 198.51.100.20/32 lookup 193 priority 110", log)
        self.assertIn("ip -4 route del 198.51.100.20/32 table 193", log)
        self.assertFalse((self.state / "endpoint").exists())

    def test_other_vpn_route_refused(self):
        result = self.run_script("up", {"VPN_TEST_OVERLAY": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("rule add" in x or "connection up id" in x for x in self.lines()))

    def test_collision_refused(self):
        result = self.run_script("up", {"VPN_TEST_COLLISION": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("route replace" in x or "connection up id" in x for x in self.lines()))

    def test_no_private_information_in_tracked_files(self):
        content = "\n".join(p.read_text(encoding="utf-8") for p in (SCRIPT, MODULE, DOC))
        self.assertNotRegex(content, r"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b")
        self.assertNotIn("pre-sharedkey:", content)
        self.assertNotIn("ipsec-psk=", content)
        self.assertIn("--enable-ikev1", content)
        self.assertIn("1.52.6", content)

    def test_ipsec_runtime_secrets_directory_is_root_only(self):
        module = MODULE.read_text(encoding="utf-8")
        self.assertIn('d /etc/ipsec.d 0700 root root -', module)


if __name__ == "__main__":
    unittest.main()
