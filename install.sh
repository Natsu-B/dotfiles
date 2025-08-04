#!/bin/sh

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
USERNAME=$(whoami 2>/dev/null || echo hotaru)

# --- Function Definitions ---

# This function runs as the target user to enable the systemd service
enable_xremap_service() {
  echo "Enabling and starting xremap systemd service for user $USERNAME..."
  # Ensure the user's systemd instance is running and accessible
  export XDG_RUNTIME_DIR="/run/user/$(id -u $USERNAME)"
  if [ -z "$XDG_RUNTIME_DIR" ] || [ ! -d "$XDG_RUNTIME_DIR" ]; then
    echo "Error: XDG_RUNTIME_DIR is not set or not a directory." >&2
    echo "Cannot communicate with user's systemd instance." >&2
    return 1
  fi
  systemctl --user daemon-reload
  systemctl --user enable --now xremap.service
  echo "✅ xremap service enabled and started."
}

# This function runs as root to set up udev rules
setup_udev_rules() {
  echo "Configuring udev rules for xremap..."
  if ! groups "$USERNAME" | grep -q '\binput\b'; then
    echo "Adding user '$USERNAME' to the 'input' group..."
    usermod -aG input "$USERNAME"
    echo "NOTE: You may need to log out and log back in for the group change to take effect."
  fi

  cat > /etc/udev/rules.d/99-input.rules <<EOF
KERNEL=="event*", GROUP="input", MODE="0660"
KERNEL=="uinput", GROUP="input", MODE="0660"
EOF

  echo "Reloading udev rules..."
  udevadm control --reload-rules
  udevadm trigger
  echo "✅ udev rules configured."
}

# --- Main Script ---

# Root-level operations
if [ "$(id -u)" -eq 0 ]; then
  # This block is executed when the script is re-run with sudo
  TARGET_USERNAME=${SUDO_USER:-$USERNAME}
  setup_udev_rules
  # Execute the service enablement as the original user
  sudo -u "$TARGET_USERNAME" bash -c "$(declare -f enable_xremap_service); enable_xremap_service"
  exit 0
fi

# User-level operations
echo "🚀 Starting dotfiles installation for user: $USERNAME..."

# 1. Build and activate Home Manager configuration
echo "Building and activating Home Manager configuration..."
nix build .#home-manager --print-build-logs
./result/activate
echo "✅ Home Manager configuration activated."

# 2. Re-run script with sudo to handle root-level tasks
echo "Requesting sudo privileges to set up udev rules and systemd service..."
sudo "$0"

echo "✅ Dotfiles installation complete!"