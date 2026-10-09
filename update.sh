#!/bin/sh

set -e

# --- Configuration ---
# Get the hostname of the current machine.
HOSTNAME=$(hostname)

# An explicitly selected flake profile takes priority over the hostname.
# Existing NixOS installations keep the original hostname-based behavior.
PROFILE_FILE="/etc/dotfiles-nixos-flake-profile"
if [ -n "${NIXOS_FLAKE_PROFILE:-}" ]; then
  PROFILE="$NIXOS_FLAKE_PROFILE"
elif [ -r "$PROFILE_FILE" ]; then
  PROFILE=$(cat "$PROFILE_FILE")
else
  PROFILE="$HOSTNAME"
fi

# --- Main Script ---
echo "🚀 Updating NixOS system configuration for host: $HOSTNAME..."

# 1. Pull the latest changes from the git repository.
echo "Pulling latest changes from git..."
git pull

# 2. Rebuild the system with the updated configuration.
echo "Rebuilding the system..."
sudo nixos-rebuild switch --flake .#"$PROFILE"

echo "✅ System update complete!"
