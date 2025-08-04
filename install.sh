#!/bin/sh

set -e

USERNAME=$(whoami 2>/dev/null || echo hotaru)

# --- Main Script ---
echo "🚀 Starting dotfiles installation for user: $USERNAME..."

# Prompt for sudo password at the beginning and cache the credential.
echo "This script requires sudo access to configure udev rules for xremap."
sudo -v

# 1. Build and activate Home Manager.
echo "Building and activating Home Manager configuration..."
nix build .#home-manager --print-build-logs
./result/activate
echo "✅ Home Manager configuration activated."

# 2. Set up udev rules. Sudo credentials should now be cached.
echo "Configuring udev rules for xremap..."

# Add user to the 'input' group if not already a member.
if ! groups "$USERNAME" | grep -q '\binput\b'; then
  echo "Adding user '$USERNAME' to the 'input' group..."
  sudo usermod -aG input "$USERNAME"
  echo "NOTE: You may need to log out and log back in for this change to take effect."
fi

# Create udev rules file safely using tee.
UDEV_RULES_CONTENT='KERNEL=="event*", GROUP="input", MODE="0660"\nKERNEL=="uinput", GROUP="input", MODE="0660"'
echo -e "$UDEV_RULES_CONTENT" | sudo tee /etc/udev/rules.d/99-input.rules > /dev/null

echo "Reloading udev rules..."
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "✅ udev rules configured."

# The home-manager activation script should have already enabled the systemd service.
# You can check its status with: systemctl --user status xremap.service

echo "✅ Dotfiles installation complete!"
