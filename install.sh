#!/bin/sh

set -e

# --- Configuration ---
# Get the hostname of the current machine.
HOSTNAME=$(hostname)

# The source hardware configuration file on the target system.
SRC_HW_CONFIG="/etc/nixos/hardware-configuration.nix"

# The destination for the hardware config in this repository.
DEST_HW_CONFIG="./nixos/hardware-configuration.nix"

# --- Main Script ---
echo "🚀 Starting NixOS dotfiles installation for host: $HOSTNAME..."

# 1. Check for sudo and cache credentials
echo "This script needs sudo access to copy your hardware configuration."
sudo -v

# 2. Copy hardware configuration
echo "Attempting to copy hardware configuration from $SRC_HW_CONFIG..."
if [ -f "$SRC_HW_CONFIG" ]; then
  sudo cp "$SRC_HW_CONFIG" "$DEST_HW_CONFIG"
  echo "✅ Hardware configuration copied successfully."
else
  echo "❌ ERROR: Hardware configuration file not found at $SRC_HW_CONFIG." >&2
  echo "Please ensure you have run the NixOS installer and this file exists." >&2
  exit 1
fi

# 3. Update the hostname in flake.nix
# This replaces the placeholder 'nixos' with the actual hostname.
echo "Updating hostname in flake.nix to '$HOSTNAME'..."
sed -i "s/nixos = nixpkgs.lib.nixosSystem/${HOSTNAME} = nixpkgs.lib.nixosSystem/" flake.nix
echo "✅ flake.nix updated."

# 4. Run the initial build
echo "Building the system for the first time. This may take a while..."
nix-env -iA nixos.git
git add nixos/hardware-configuration.nix
sudo nixos-rebuild switch --flake .#"$HOSTNAME"

echo "
🎉 Installation complete!"
echo "Your system is now managed by these dotfiles."
echo "For future updates, please run ./update.sh"
