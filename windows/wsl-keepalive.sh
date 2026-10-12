#!/usr/bin/env bash
set -euo pipefail

# Long-running WSL process started by the Windows user's Startup shortcut.
# It keeps WSL active after the terminal closes so Mutagen can retry SSH.
export PATH="$HOME/.local/bin:$PATH"

if ! command -v mutagen >/dev/null; then
  echo 'Mutagen is not installed. Run Windows Install-MacDataSync.ps1 first.' >&2
  exit 1
fi
if ! command -v flock >/dev/null; then
  echo 'flock is missing (install util-linux).' >&2
  exit 1
fi

mkdir -p "$HOME/.cache/mac-data-sync"
exec 9>"$HOME/.cache/mac-data-sync/keepalive.lock"
if ! flock -n 9; then
  # An earlier Windows Startup keeper is still running.
  exit 0
fi

printf 'Mac Data Sync: Windows WSL daemon keeper started.\n'
# Do not stop the Mutagen daemon on exit: an interactive session might use it.
# This loop keeps WSL alive and recovers from a crashed Mutagen daemon.
while true; do
  if ! mutagen daemon start >/dev/null 2>&1; then
    printf 'Mac Data Sync: daemon start failed; retrying.\n' >&2
  fi
  sleep 60
done
