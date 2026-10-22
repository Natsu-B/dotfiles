#!/usr/bin/env bash
set -euo pipefail
root=$(mktemp -d)
export HOME="$root/home"
mkdir -p "$HOME"
cleanup() {
  for n in ci-linux-new-directory ci-linux-new-file; do
    mutagen sync terminate "$n" >/dev/null 2>&1 || true
  done
  mutagen daemon stop >/dev/null 2>&1 || true
  rm -rf -- "$root"
}
trap cleanup EXIT

mkdir -p "$root/linux/work/new-project/deep" "$root/mac/data"
echo 'Linux-owned contents' > "$root/linux/work/new-project/deep/README"
# Mac project path does not exist on purpose.
mutagen sync create --name=ci-linux-new-directory --sync-mode=two-way-safe \
  --no-global-configuration --no-ignore-vcs \
  "$root/mac/data/new-project" "$root/linux/work/new-project"
timeout 120s mutagen sync flush ci-linux-new-directory
cmp "$root/linux/work/new-project/deep/README" "$root/mac/data/new-project/deep/README"

mkdir -p "$root/linux/work/docs" "$root/mac/data/docs"
echo 'Linux document' > "$root/linux/work/docs/new.txt"
# Mac file path does not exist on purpose.
mutagen sync create --name=ci-linux-new-file --sync-mode=two-way-safe \
  --no-global-configuration --no-ignore-vcs \
  "$root/mac/data/docs/new.txt" "$root/linux/work/docs/new.txt"
timeout 120s mutagen sync flush ci-linux-new-file
cmp "$root/linux/work/docs/new.txt" "$root/mac/data/docs/new.txt"
echo 'Mutagen Linux-first archive creation tests PASS'
