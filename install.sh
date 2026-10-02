#!/bin/sh

set -eu

TARGET_HOST=${1:-${TARGET_HOST:-nixos}}

echo "Installing NixOS configuration for host: $TARGET_HOST"

if ! nix eval --raw ".#nixosConfigurations.${TARGET_HOST}.config.networking.hostName" >/tmp/dotfiles-hostname.$$ 2>/dev/null; then
  rm -f /tmp/dotfiles-hostname.$$
  echo "ERROR: no nixosConfigurations.${TARGET_HOST} exists in flake.nix" >&2
  exit 2
fi
CONFIGURED_HOST=$(cat /tmp/dotfiles-hostname.$$)
rm -f /tmp/dotfiles-hostname.$$

if [ "$CONFIGURED_HOST" != "$TARGET_HOST" ]; then
  echo "ERROR: flake key '$TARGET_HOST' configures networking.hostName='$CONFIGURED_HOST'" >&2
  exit 2
fi

sudo -v
sudo nixos-rebuild switch --flake ".#${TARGET_HOST}"

echo "Installation complete for $TARGET_HOST."
echo "Disk partitioning for a fresh machine is declared in hosts/${TARGET_HOST}/disko.nix."
