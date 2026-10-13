#!/usr/bin/env bash
set -euo pipefail

# Installed in WSL at /usr/local/bin/mac-data-sync-wsl.
# PowerShell invokes this path directly via wsl.exe --exec, avoiding Windows
# quoting/interpolation of complex bash -lc scripts and file path arguments.
export PATH="$HOME/.local/bin:$PATH"

case "${1:-}" in
  --windows-path)
    [[ $# == 1 ]] || exit 2
    mkdir -p -- "$HOME/work"
    command -v wslpath >/dev/null || { echo 'wslpath is not available' >&2; exit 1; }
    wslpath -w "$HOME/work"
    ;;
  --daemon)
    [[ $# == 1 ]] || exit 2
    exec "$HOME/.local/bin/mac-data-sync-keepalive"
    ;;
  *)
    exec "$HOME/.local/bin/mac-data-sync" "$@"
    ;;
esac
