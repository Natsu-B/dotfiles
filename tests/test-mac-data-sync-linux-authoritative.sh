#!/usr/bin/env bash
set -euo pipefail

# Verify a stopped, divergent session can be reseeded from Linux without
# permitting Mutagen to modify Linux during the seeding pass.
root=$(mktemp -d)
export HOME="$root/home"
mkdir -p -- "$HOME"
linux="$root/linux/work/project-a"
mac="$root/mac/data/project-a"
mkdir -p -- "$linux/src" "$mac"

cleanup() {
  mutagen sync terminate ci-linux-authoritative-seed ci-linux-authoritative-restart >/dev/null 2>&1 || true
  mutagen daemon stop >/dev/null 2>&1 || true
  rm -rf -- "$root"
}
trap cleanup EXIT

printf 'Linux is authoritative\n' > "$linux/src/notes.txt"
printf 'keep Linux only\n' > "$linux/linux-only.txt"
ln -s '/nix/store/linux-specific-target' "$linux/absolute-link"
printf 'stale Mac data\n' > "$mac/src" # Mac has an incompatible file where Linux has a directory.
printf 'discard Mac only\n' > "$mac/mac-only.txt"

# A Linux backup outside both synchronization roots is the last-resort copy.
mkdir -p -- "$root/backup"
cp -a -- "$linux" "$root/backup/data"

mutagen sync create --name=ci-linux-authoritative-seed --sync-mode=one-way-replica \
  --no-global-configuration --no-ignore-vcs --symlink-mode=posix-raw \
  "$linux" "$mac"
timeout 120s mutagen sync flush ci-linux-authoritative-seed

seed_snapshot=$(mutagen sync list --template '{{json .}}' ci-linux-authoritative-seed)
jq -e '
  type == "array" and length == 1 and
  .[0].name == "ci-linux-authoritative-seed" and
  .[0].paused == false and
  (.[0].status == "watching" or .[0].status == 6) and
  (.[0].successfulCycles // 0) > 0 and
  .[0].alpha.connected == true and .[0].beta.connected == true and
  .[0].alpha.scanned == true and .[0].beta.scanned == true and
  (.[0].lastError // "") == "" and
  ((.[0].conflicts // []) | length) == 0 and
  ((.[0].alpha.scanProblems // []) | length) == 0 and
  ((.[0].beta.scanProblems // []) | length) == 0 and
  ((.[0].alpha.transitionProblems // []) | length) == 0 and
  ((.[0].beta.transitionProblems // []) | length) == 0
' <<< "$seed_snapshot" >/dev/null

# The Mac is rebuilt from Linux; Mac-only and incompatible entries are gone.
cmp "$linux/src/notes.txt" "$mac/src/notes.txt"
cmp "$linux/linux-only.txt" "$mac/linux-only.txt"
test ! -e "$mac/mac-only.txt"
[[ -L "$mac/absolute-link" ]]
[[ "$(readlink "$mac/absolute-link")" == '/nix/store/linux-specific-target' ]]
# Linux remains byte-for-byte equivalent to its independent backup.
diff -r --no-dereference "$root/backup/data" "$linux"
mutagen sync terminate ci-linux-authoritative-seed

# Now that both trees match, a new two-way session starts without rewriting Linux.
mutagen sync create --name=ci-linux-authoritative-restart --sync-mode=two-way-safe \
  --no-global-configuration --no-ignore-vcs --symlink-mode=posix-raw \
  "$mac" "$linux"
timeout 120s mutagen sync flush ci-linux-authoritative-restart
diff -r --no-dereference "$root/backup/data" "$linux"
echo 'Linux-authoritative recovery integration PASS'
