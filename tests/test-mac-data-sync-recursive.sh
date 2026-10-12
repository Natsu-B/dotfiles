#!/usr/bin/env bash
set -euo pipefail

# Local-to-local Mutagen integration verifies that our production flags copy
# entire subtrees, including hidden/VCS files, beyond the picker depth limit.
root=$(mktemp -d)
session=ci-recursive-subtree
cleanup() {
  mutagen sync terminate "$session" >/dev/null 2>&1 || true
  mutagen daemon stop >/dev/null 2>&1 || true
  rm -rf -- "$root"
}
trap cleanup EXIT
export HOME="$root/home"
mkdir -p "$HOME"
source_dir="$root/mac-data/project-a"
destination_dir="$root/nixos-work/project-a"
mkdir -p "$source_dir/src/deep/level5" "$source_dir/.git/refs/heads" "$source_dir/.hidden"
mkdir -p "$destination_dir"
printf 'nested-source\n' > "$source_dir/src/deep/level5/nested.txt"
printf 'hidden-source\n' > "$source_dir/.hidden/config"
printf '0123456789abcdef\n' > "$source_dir/.git/refs/heads/main"
printf 'root-source\n' > "$source_dir/README.md"

mutagen sync create --name="$session" --sync-mode=two-way-safe \
  --no-global-configuration --no-ignore-vcs \
  "$source_dir" "$destination_dir"
timeout 120s mutagen sync flush "$session"

cmp "$source_dir/README.md" "$destination_dir/README.md"
cmp "$source_dir/src/deep/level5/nested.txt" "$destination_dir/src/deep/level5/nested.txt"
cmp "$source_dir/.hidden/config" "$destination_dir/.hidden/config"
cmp "$source_dir/.git/refs/heads/main" "$destination_dir/.git/refs/heads/main"

# Deep descendants created after initial checkout must sync automatically, too.
mkdir -p "$source_dir/src/deep/level5/added/later"
printf 'new-file\n' > "$source_dir/src/deep/level5/added/later/new.txt"
timeout 120s mutagen sync flush "$session"
cmp "$source_dir/src/deep/level5/added/later/new.txt" \
  "$destination_dir/src/deep/level5/added/later/new.txt"

# Edits made in the NixOS work tree must propagate back to the Mac archive.
printf 'linux-change\n' > "$destination_dir/src/deep/level5/nested.txt"
timeout 120s mutagen sync flush "$session"
cmp "$destination_dir/src/deep/level5/nested.txt" \
  "$source_dir/src/deep/level5/nested.txt"

echo 'Mutagen recursive directory integration PASS'
