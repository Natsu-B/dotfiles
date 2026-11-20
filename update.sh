#!/bin/sh

set -eu

usage() {
  printf 'Usage: %s [--switch] [PROFILE]\n' "$0"
  printf 'Default: prepare the next boot. --switch: activate immediately from a text console.\n'
}

ACTION=boot
case "${1:-}" in
  --switch) ACTION=switch; shift ;;
  -h|--help) usage; exit 0 ;;
esac
case "${1:-}" in
  -*) usage >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  usage >&2
  exit 2
fi

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

echo "Updating NixOS configuration: $PROFILE (host: $TARGET_HOST)"

git pull --ff-only

CONFIGURED_HOST=$(nix eval --raw ".#nixosConfigurations.${PROFILE}.config.networking.hostName")
if [ "$CONFIGURED_HOST" != "$TARGET_HOST" ]; then
  echo "ERROR: flake key '$PROFILE' configures networking.hostName='$CONFIGURED_HOST', expected '$TARGET_HOST'" >&2
  exit 2
fi

sh "$(dirname "$0")/scripts/check-boot-filesystems.sh" "$PROFILE"

if [ "$ACTION" = switch ]; then
  echo "Activating now. System service restarts can end the graphical session." >&2
  sudo nixos-rebuild switch --flake ".#${PROFILE}"
  echo "System update complete."
else
  sudo nixos-rebuild boot --flake ".#${PROFILE}"
  echo "Update ready. Reboot when convenient to apply it."
fi
