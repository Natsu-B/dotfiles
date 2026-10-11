set -euo pipefail
: "${XDG_RUNTIME_DIR:?A graphical session is required}"
umask 077
exec 9> "$XDG_RUNTIME_DIR/dotfiles-screen-lock.mutex"
flock -n 9 || exit 0
marker="$XDG_RUNTIME_DIR/dotfiles-screen-locked"
was_active=false
if systemctl --user is-active --quiet dotfiles-clipboard.service; then was_active=true; fi
touch "$marker"
# Clipboard cleanup failing must never prevent the screen from locking.
desktop-clipboard pause || true
if hyprlock "$@"; then
  # Notify DMS/logind only after the external locker authenticated successfully.
  loginctl unlock-session || true
  rm -f -- "$marker"
  if "$was_active" && systemctl --user is-active --quiet wayland-session@hyprland.desktop.target; then
    desktop-clipboard resume || true
  fi
else
  # Leave recording disabled on locker failure. Retry desktop-lock after fixing it.
  notify-send -u critical 'Screen lock failed' 'The screen may be unlocked. Clipboard recording remains paused.' || true
  exit 1
fi
