#!/bin/sh

set -eu

TARGET_HOST=${1:-${TARGET_HOST:-$(hostname)}}

echo "Updating NixOS configuration for host: $TARGET_HOST"

git pull --ff-only

CONFIGURED_HOST=$(nix eval --raw ".#nixosConfigurations.${TARGET_HOST}.config.networking.hostName")
if [ "$CONFIGURED_HOST" != "$TARGET_HOST" ]; then
  echo "ERROR: flake key '$TARGET_HOST' configures networking.hostName='$CONFIGURED_HOST'" >&2
  exit 2
fi

sudo nixos-rebuild switch --flake ".#${TARGET_HOST}"

echo "System update complete."
