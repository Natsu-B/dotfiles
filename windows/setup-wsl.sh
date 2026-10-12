#!/usr/bin/env bash
set -euo pipefail

# Called by windows/Install-MacDataSync.ps1 inside WSL Ubuntu/Debian.
# Requires this repository to be accessible through a WSL path (e.g. /mnt/c).
repo_root=${1:?Usage: setup-wsl.sh <wsl-repo-root> [mac-host] [mac-user]}
mac_host=${2:-}
mac_user=${3:-}
bin_dir="$HOME/.local/bin"

fail() { printf 'Setup error: %s\n' "$*" >&2; exit 1; }

[[ -f "$repo_root/scripts/mac-data-sync" ]] || fail "Missing dotfiles checkout: $repo_root"
[[ -f "$repo_root/windows/wsl-keepalive.sh" ]] || fail 'Missing WSL helper'
command -v apt-get >/dev/null || fail 'The automatic WSL installer currently supports Ubuntu/Debian.'
command -v sudo >/dev/null || fail 'sudo is required for apt dependencies.'

if [[ -n "$mac_host" || -n "$mac_user" ]]; then
  [[ "$mac_host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || fail 'Invalid Mac DNS name or Tailscale IP.'
  [[ "$mac_user" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || fail 'Invalid macOS short user name.'
fi

printf 'Installing Ubuntu/WSL dependencies...\n'
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  bash openssh-client ca-certificates curl tar fzf jq lsof \
  coreutils findutils util-linux

mkdir -p "$bin_dir" "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# v0.18.1 is the same version exercised by the repository CI integration.
version=0.18.1
arch=$(uname -m)
case "$arch" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) fail "Unsupported WSL CPU architecture: $arch" ;;
esac

if [[ ! -x "$bin_dir/mutagen" || "$("$bin_dir/mutagen" version 2>/dev/null)" != "$version" ]]; then
  tmp_dir=$(mktemp -d)
  trap 'rm -rf -- "$tmp_dir"' EXIT
  archive="mutagen_linux_${arch}_v${version}.tar.gz"
  url="https://github.com/mutagen-io/mutagen/releases/download/v${version}"
  printf 'Downloading Mutagen v%s for Linux %s...\n' "$version" "$arch"
  curl --fail --location --retry 3 --silent --show-error \
    --output "$tmp_dir/$archive" "$url/$archive"
  curl --fail --location --retry 3 --silent --show-error \
    --output "$tmp_dir/SHA256SUMS" "$url/SHA256SUMS"
  checksum=$(grep -F "$archive" "$tmp_dir/SHA256SUMS" || true)
  [[ -n "$checksum" ]] || fail 'Release checksum entry was not found'
  (cd "$tmp_dir" && printf '%s\n' "$checksum" | sha256sum --check) \
    || fail 'Mutagen archive SHA-256 verification failed'
  mkdir -p "$tmp_dir/extracted"
  tar -xzf "$tmp_dir/$archive" -C "$tmp_dir/extracted"
  [[ -f "$tmp_dir/extracted/mutagen" ]] || fail 'Mutagen executable is missing in release'
  [[ -f "$tmp_dir/extracted/mutagen-agents.tar.gz" ]] || fail 'Mutagen agent bundle is missing in release'
  install -m 755 "$tmp_dir/extracted/mutagen" "$bin_dir/mutagen"
  install -m 644 "$tmp_dir/extracted/mutagen-agents.tar.gz" "$bin_dir/mutagen-agents.tar.gz"
fi

for name in mac-data-sync mac-data-sync-ui mac-data-sync-release; do
  install -m 755 "$repo_root/scripts/$name" "$bin_dir/$name"
  bash -n "$bin_dir/$name"
done
install -m 755 "$repo_root/windows/wsl-keepalive.sh" "$bin_dir/mac-data-sync-keepalive"
bash -n "$bin_dir/mac-data-sync-keepalive"

if [[ -n "$mac_host" ]]; then
  ssh_config="$HOME/.ssh/config"
  touch "$ssh_config"
  chmod 600 "$ssh_config"
  # Respect a manually configured host alias; don't replace it silently.
  if grep -Eq '^[[:space:]]*Host[[:space:]]+mac([[:space:]]|$)' "$ssh_config"; then
    printf 'SSH Host mac already exists; leaving the configuration unchanged.\n'
  else
    cat >> "$ssh_config" <<CONFIG

Host mac
    HostName $mac_host
    User $mac_user
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    BatchMode yes
CONFIG
    printf 'Created SSH Host mac for %s@%s.\n' "$mac_user" "$mac_host"
  fi
fi

"$bin_dir/mutagen" version
"$bin_dir/mutagen" daemon start
printf '\nInstalled Mac Data Sync into %s\n' "$bin_dir"
printf 'Windows working copies live at ~/work in WSL, accessible from Windows Explorer.\n'
printf 'Check Mac connectivity: ssh mac "ls ~/data"\n'
if [[ ! -f "$HOME/.ssh/id_ed25519.pub" ]]; then
  printf 'No WSL SSH key found. Generate one with: ssh-keygen -t ed25519\n'
fi
