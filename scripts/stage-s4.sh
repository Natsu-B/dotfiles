#!/usr/bin/env bash
# Stage the already-built S4 generation without changing the running session.
set -euo pipefail

mode=${1:---check}
case "$mode" in
  --check|--apply) ;;
  *) echo 'Usage: stage-s4.sh [--check|--apply]' >&2; exit 2 ;;
esac
generation=$(readlink -e /home/hotaru/.local/state/dotfiles/s4-system)
case "$generation" in
  /nix/store/*-nixos-system-nixos-*) ;;
  *) echo 'Build the S4 system generation first.' >&2; exit 1 ;;
esac
test -x "$generation/bin/switch-to-configuration"
grep -qF '/var/lib/hibernate.swap none swap' "$generation/etc/fstab"
grep -qF 'HibernateMode=platform' "$generation/etc/systemd/sleep.conf"
grep -qF 'systemd-sleep hibernate' "$generation/etc/systemd/system/systemd-suspend.service.d/overrides.conf"
grep -qw disk /sys/power/state
grep -qw platform /sys/power/disk
test -d /sys/firmware/efi/efivars

# Reserve room for the 40 GiB swap file and ongoing normal disk use.
available_kib=$(df -Pk /home/hotaru | awk 'NR == 2 {print $4}')
if (( available_kib < 48 * 1024 * 1024 )); then
  echo 'At least 48 GiB free space is required before staging the 40 GiB swap.' >&2
  exit 1
fi
printf 'Verified S4 generation: %s\n' "$generation"
if [[ "$mode" == --check ]]; then exit 0; fi
if (( EUID != 0 )); then
  echo 'Run --apply with sudo from a normal host terminal.' >&2
  exit 1
fi
/run/current-system/sw/bin/nix-env -p /nix/var/nix/profiles/system --set "$generation"
"$generation/bin/switch-to-configuration" boot
echo 'Staged for the next normal boot. Save your work and reboot before using sleep.'
