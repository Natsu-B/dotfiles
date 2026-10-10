#!/bin/sh

set -eu

# This applies a configuration to an already installed NixOS system.
# Fresh Windows dual-boot installations use nixos-install; see DUAL-BOOT.md.
TARGET_HOST=${TARGET_HOST:-$(hostname)}
PROFILE_FILE="/etc/dotfiles-nixos-flake-profile"
if [ "$#" -gt 0 ]; then
  PROFILE=$1
elif [ -n "${NIXOS_FLAKE_PROFILE:-}" ]; then
  PROFILE=$NIXOS_FLAKE_PROFILE
elif [ -r "$PROFILE_FILE" ]; then
  PROFILE=$(cat "$PROFILE_FILE")
else
  PROFILE=$TARGET_HOST
fi

echo "Applying NixOS configuration: $PROFILE (host: $TARGET_HOST)"

CONFIGURED_HOST=$(nix eval --raw ".#nixosConfigurations.${PROFILE}.config.networking.hostName")
if [ "$CONFIGURED_HOST" != "$TARGET_HOST" ]; then
  echo "ERROR: flake key '$PROFILE' configures networking.hostName='$CONFIGURED_HOST', expected '$TARGET_HOST'" >&2
  exit 2
fi

sudo nixos-rebuild switch --flake ".#${PROFILE}"

echo "Configuration applied."
