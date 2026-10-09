#!/usr/bin/env bash
# Run from a NixOS UEFI live environment, after installing Windows to a
# deliberately limited partition and leaving the rest of the disk unallocated.
set -euo pipefail

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0 /dev/disk/by-id/..."
[[ $# -eq 1 ]] || die "Usage: sudo $0 /dev/disk/by-id/<target-disk>"
[[ -t 0 ]] || die "An interactive terminal is required."
[[ -d /sys/firmware/efi/efivars ]] || die "Boot the installer in UEFI mode."
for tool in readlink lsblk blkid awk mount umount mountpoint findmnt \
  mktemp rmdir systemd-repart udevadm; do
  command -v "$tool" >/dev/null || die "Missing command: $tool"
done

disk=$(readlink -f -- "$1")
[[ -b $disk ]] || die "Not a block device: $1"
[[ $(lsblk -nr -o TYPE "$disk" | head -n 1) == disk ]] || die "Specify a whole disk, not a partition."
[[ $(blkid -p -s PTTYPE -o value "$disk") == gpt ]] || die "Expected an existing GPT partition table, created by Windows Setup."
if findmnt -rn /mnt >/dev/null; then
  die "/mnt is already mounted. Unmount any prior installation first."
fi

# Reject an already-installed NixOS; this is specifically for a fresh
# Windows-first install, not a migration or reinstallation of Linux.
if lsblk -nrpo PARTTYPE "$disk" | grep -Eiq \
  '4f68bce3-e8cd-4db1-96e7-fbcaf984b709|bc13c2ff-59e6-4262-a352-b275fd6f7172'; then
  die "Existing NixOS root/XBOOTLDR partition detected. Refusing to modify."
fi

mapfile -t esps < <(
  lsblk -nrpo NAME,PARTTYPE "$disk" |
    awk 'tolower($2) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print $1}'
)
[[ \${#esps[@]} -eq 1 ]] || die "Expected exactly one Windows EFI System Partition on this disk."
esp=\${esps[0]}

lsblk -nrpo NAME,FSTYPE "$disk" |
  awk 'tolower($2) == "ntfs" {found=1} END {exit !found}' ||
  die "No NTFS Windows partition detected on this disk."

tmp_esp=$(mktemp -d)
cleanup() {
  if mountpoint -q "$tmp_esp"; then umount "$tmp_esp" || true; fi
  rmdir "$tmp_esp" || true
}
trap cleanup EXIT
mount -o ro "$esp" "$tmp_esp"
[[ -f $tmp_esp/EFI/Microsoft/Boot/bootmgfw.efi ]] ||
  die "Windows Boot Manager is missing from the disk's ESP."
umount "$tmp_esp"

repo_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
defs="$repo_root/installer/repart.d"

printf '\nTarget disk and its existing partitions:\n'
lsblk -o NAME,SIZE,FSTYPE,PARTTYPE,PARTLABEL,MOUNTPOINTS "$disk"
printf '\nPreview: NixOS boot (4 GiB) and ext4 root (remaining free space).\n'
systemd-repart --definitions="$defs" --empty=refuse --factory-reset=no \
  --dry-run=yes "$disk"

printf '\nThis will write partitions and filesystems to UNALLOCATED space on %s.\n' "$disk"
printf 'Existing Windows partitions must not be formatted or moved.\n'
read -r -p "Type CREATE-NIXOS to proceed: " answer
[[ $answer == "CREATE-NIXOS" ]] || die "Cancelled without changes."

systemd-repart --definitions="$defs" --empty=refuse --factory-reset=no \
  --dry-run=no "$disk"
udevadm settle

mapfile -t roots < <(
  lsblk -nrpo NAME,PARTLABEL "$disk" | awk '$2 == "NIXOS_ROOT" {print $1}'
)
mapfile -t boots < <(
  lsblk -nrpo NAME,PARTLABEL "$disk" | awk '$2 == "NIXOS_BOOT" {print $1}'
)
[[ \${#roots[@]} -eq 1 && \${#boots[@]} -eq 1 ]] ||
  die "Partitions were changed, but expected partition labels could not be found. Inspect lsblk before continuing."

mkdir -p /mnt
mount "\${roots[0]}" /mnt
mkdir -p /mnt/boot /mnt/efi
mount -o umask=0077 "\${boots[0]}" /mnt/boot
mount -o umask=0077 "$esp" /mnt/efi

printf '\nMounted NixOS root at /mnt, XBOOTLDR at /mnt/boot, and Windows ESP at /mnt/efi.\n'
printf 'Next: regenerate hardware-configuration.nix and run nixos-install --flake ...#nixos-windows.\n'
