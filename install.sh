#!/bin/sh

set -e

USERNAME=$(whoami 2>/dev/null || echo hotaru)

# Function to set up udev rules, to be run with sudo
setup_udev_rules() {
  echo "Configuring udev rules for xremap..."
  if ! groups "$USERNAME" | grep -q '\binput\b'; then
    echo "Adding user '$USERNAME' to the 'input' group..."
    usermod -aG input "$USERNAME"
    echo "NOTE: You may need to log out and log back in for this to take effect."
  fi

  cat > /etc/udev/rules.d/99-input.rules <<EOF
KERNEL=="event*", GROUP="input", MODE="0660"
KERNEL=="uinput", GROUP="input", MODE="0660"
EOF

  udevadm control --reload-rules && udevadm trigger
  echo "✅ udev rules configured."
}

# --- Main Script ---

# If called with --setup-udev, run the function and exit.
# This is for the sudo recursive call.
if [ "$1" = "--setup-udev" ]; then
  setup_udev_rules
  exit 0
fi

echo "🚀 Starting dotfiles installation for user: $USERNAME..."

# 1. Build and activate Home Manager.
# This will also enable and start the xremap service.
echo "Building and activating Home Manager configuration..."
nix build .#home-manager --print-build-logs
./result/activate
echo "✅ Home Manager configuration activated."

# 2. Set up udev rules using a recursive call with sudo.
if [ "$(id -u)" -ne 0 ]; then
  echo "Requesting sudo privileges to set up udev rules..."
  sudo -E "$0" --setup-udev
else
  setup_udev_rules
fi

echo "✅ Dotfiles installation complete!"
