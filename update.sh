#!/bin/sh

set -e

# --- Configuration ---
# Get the hostname of the current machine.
HOSTNAME=$(hostname)

# --- Main Script ---
echo "🚀 Updating NixOS system configuration for host: $HOSTNAME..."

# 1. Pull the latest changes from the git repository.
echo "Pulling latest changes from git..."
git pull

# 2. Rebuild the system with the updated configuration.
echo "Rebuilding the system..."
sudo nixos-rebuild switch --flake .#"$HOSTNAME"

echo "✅ System update complete!"
