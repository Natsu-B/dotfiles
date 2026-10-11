#!/bin/sh

# Check the installed system before changing its boot configuration.
set -eu

PROFILE=${1:?Usage: check-boot-filesystems.sh FLAKE_PROFILE}
MOUNTS="/ /boot"
if ! esp_mount=$(nix eval --raw ".#nixosConfigurations.${PROFILE}.config.boot.loader.efi.efiSysMountPoint"); then
  echo "ERROR: cannot determine the configured EFI mount point." >&2
  exit 2
fi
if [ "$esp_mount" != /boot ]; then
  MOUNTS="$MOUNTS $esp_mount"
fi

for mountpoint in $MOUNTS; do
  if ! expected=$(nix eval --raw ".#nixosConfigurations.${PROFILE}.config.fileSystems.\"${mountpoint}\".device"); then
    echo "ERROR: no usable device configured for $mountpoint. Regenerate hosts/nixos/hardware-configuration.nix; see DUAL-BOOT.md." >&2
    exit 2
  fi
  if ! actual=$(findmnt --noheadings --raw --output SOURCE --mountpoint "$mountpoint"); then
    echo "ERROR: $mountpoint is not mounted. Mount the intended boot filesystems before rebuilding." >&2
    exit 2
  fi
  if ! expected_device=$(readlink -e -- "$expected"); then
    echo "ERROR: $mountpoint references missing device $expected. Regenerate hosts/nixos/hardware-configuration.nix; see DUAL-BOOT.md." >&2
    exit 2
  fi
  if ! actual_device=$(readlink -e -- "$actual"); then
    echo "ERROR: cannot resolve the mounted device $actual for $mountpoint." >&2
    exit 2
  fi
  if [ "$expected_device" != "$actual_device" ]; then
    echo "ERROR: $mountpoint is mounted from $actual, but the flake uses $expected. Refusing to change boot configuration." >&2
    exit 2
  fi
done

echo "Boot filesystem devices match the running system."
