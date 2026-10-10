# Install Kitty's terminfo on interactive SSH destinations via its own helper.
ssh() {
  if [[ $TERM == xterm-kitty ]]; then
    if [[ -t 0 && -t 1 && -n ${KITTY_WINDOW_ID-} ]] && (( $+commands[kitten] )); then
      command kitten ssh "$@"
    else
      TERM=xterm-256color command ssh "$@"
    fi
  else
    command ssh "$@"
  fi
}
