set -euo pipefail
umask 077
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
state_file="$state_dir/keyboard-profile"
read_profile() {
  local value=dvorak
  [[ ! -f "$state_file" ]] || read -r value < "$state_file" || true
  case "$value" in dvorak|qwerty) printf '%s\n' "$value";; *) printf 'dvorak\n';; esac
}
write_profile() {
  local temporary
  temporary=$(mktemp "$state_dir/.keyboard-profile.XXXXXX")
  printf '%s\n' "$1" > "$temporary"
  mv -f -- "$temporary" "$state_file"
}
current=$(read_profile)
case "${1:-status}" in
  run)
    exec xremap --watch=device --no-window-logging --allow-launch=false \
      "$DOTFILES_XREMAP_PROFILES/$current.yml"
    ;;
  status) printf '%s\n' "$current" ;;
  json)
    if systemctl --user is-active --quiet xremap.service; then
      printf '{"text":"%s","tooltip":"Win+F2: QWERTY / Dvorak","class":"%s"}\n' "$current" "$current"
    else
      printf '{"text":"QWERTY !","tooltip":"xremap is not running","class":"error"}\n'
    fi
    ;;
  toggle|dvorak|qwerty)
    : "${XDG_RUNTIME_DIR:?A logged-in user session is required}"
    mkdir -p -- "$state_dir"
    exec 9> "$XDG_RUNTIME_DIR/dotfiles-keyboard.lock"
    flock -x 9
    current=$(read_profile)
    target=$1
    if [[ "$target" == toggle ]]; then
      if [[ "$current" == dvorak ]]; then target=qwerty; else target=dvorak; fi
    fi
    test -r "$DOTFILES_XREMAP_PROFILES/$target.yml"
    write_profile "$target"
    if systemctl --user restart xremap.service && sleep 0.5 && \
        systemctl --user is-active --quiet xremap.service; then
      notify-send -a 'Keyboard' 'Keyboard profile' "$target" || true
    else
      write_profile "$current"
      systemctl --user restart xremap.service || true
      notify-send -u critical 'Keyboard switch failed' 'The previous profile was restored.' || true
      exit 1
    fi
    ;;
  *) echo 'Usage: keyboard-profile {toggle|qwerty|dvorak|status|json|run}' >&2; exit 2 ;;
esac
