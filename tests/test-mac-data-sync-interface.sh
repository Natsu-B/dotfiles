#!/usr/bin/env bash
set -euo pipefail
scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin" "$root/home/work" "$root/home/.local/state/mac-data-sync" "$root/mac"
export HOME="$root/home" XDG_STATE_HOME="$root/home/.local/state" TEST_MAC="$root/mac" TEST_LOG="$root/log" TEST_STATE="$root/state.json"
export PATH="$root/bin:$PATH" MAC_DATA_REMOTE=mac

cat > "$root/bin/mutagen" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'mutagen %s\n' "$*" >> "$TEST_LOG"
if [[ "${1:-}" == sync && "${2:-}" == list && "${3:-}" == --template ]]; then
  cat "$TEST_STATE"
  exit
fi
if [[ "${1:-}" == sync && "${2:-}" == list ]]; then echo 'Mock details'; fi
SH
cat > "$root/bin/ssh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'ssh %s\n' "$*" >> "$TEST_LOG"
arg=${*: -1}
if [[ "$arg" == MAC_REL_B64=* ]]; then
  rel=${arg#MAC_REL_B64=}
  rel=${rel%% *}
  rel=$(printf %s "$rel" | base64 -d)
  root="$TEST_MAC/$rel"
  if [[ -f "$root" ]]; then
    sum=$(sha256sum < "$root")
    printf 'F\t.\t%s\0' "${sum%% *}"
  else
    (cd "$root" && find . -print0 | while IFS= read -r -d '' path; do
      if [[ -L "$path" ]]; then
        sum=$(readlink "$path" | sha256sum); printf 'L\t%s\t%s\0' "$path" "${sum%% *}"
      elif [[ -d "$path" ]]; then
        printf 'D\t%s\t-\0' "$path"
      else
        sum=$(sha256sum < "$path"); printf 'F\t%s\t%s\0' "$path" "${sum%% *}"
      fi
    done)
  fi
else
  exit 5
fi
SH
cat > "$root/bin/lsof" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat > "$root/bin/fzf" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
idx=$(cat "$FZF_COUNT")
idx=$((idx+1))
printf '%s' "$idx" > "$FZF_COUNT"
choice=$(sed -n "${idx}p" "$FZF_STEPS")
case "$choice" in
  SELECT) awk -F '\t' 'index($0,"project-a") { printf "%s%c", $0, 0 }' ;;
  BACK) exit 1 ;;
  *) cat >/dev/null; printf '%s\n' "$choice" ;;
esac
SH
cat > "$root/bin/mac-data-sync" <<'SH'
#!/usr/bin/env bash
printf 'cli %s\n' "$*" >> "$TEST_LOG"
SH
chmod +x "$root/bin/"*

path='project-a'
id="mac-data-$(printf %s "$path" | sha256sum | cut -c1-20)"
mkdir -p "$HOME/work/$path" "$TEST_MAC/$path"
printf 'same\n' > "$HOME/work/$path/file.txt"
printf 'same\n' > "$TEST_MAC/$path/file.txt"
printf '%s\n' "$path" > "$XDG_STATE_HOME/mac-data-sync/$id"

write_state() {
  local state=$1
  jq -cn --arg id "$id" --arg root "$HOME/work/project-a" --arg state "$state" '
    [{name: $id, alpha: {host:"mac",path:"~/data/project-a",connected: ($state!="offline"),scanned:true},
       beta: {path:$root,connected:true,scanned:true},status:"watching", successfulCycles:2,
       paused:false, conflicts: (if $state == "conflict" then [{x:1}] else [] end)}]' > "$TEST_STATE"
}
write_state healthy

# UI: main -> working copies -> select -> sync now -> return -> quit
export FZF_STEPS="$root/steps" FZF_COUNT="$root/counter"
printf 'Working copies\nSELECT\nSync now\nBACK\nQuit\n' > "$FZF_STEPS"
printf 0 > "$FZF_COUNT"
printf '\n' | MAC_DATA_SYNC_BIN="$root/bin/mac-data-sync" bash "$scripts/mac-data-sync-ui" >/dev/null
grep -q 'cli flush project-a' "$TEST_LOG"

# Block release if conflict: neither session nor Linux copy may be deleted.
write_state conflict
if printf 'RELEASE project-a\n' | bash "$scripts/mac-data-sync-release" project-a > "$root/fail" 2>&1; then
  echo 'FAIL: released conflicted copy' >&2; exit 1
fi
test -e "$HOME/work/project-a/file.txt"
! grep -q 'mutagen sync terminate ' "$TEST_LOG"

# Offline state blocks release before any pause or delete.
write_state offline
if printf 'RELEASE project-a\n' | bash "$scripts/mac-data-sync-release" project-a > "$root/fail" 2>&1; then
  echo 'FAIL: released offline copy' >&2; exit 1
fi
test -e "$HOME/work/project-a/file.txt"

# Block release on local-only .git content (VCS is intentionally ignored by Mutagen).
write_state healthy
mkdir -p "$HOME/work/project-a/.git"
printf 'unsaved commit\n' > "$HOME/work/project-a/.git/log"
if printf 'RELEASE project-a\n' | bash "$scripts/mac-data-sync-release" project-a > "$root/fail" 2>&1; then
  echo 'FAIL: released ignored .git data' >&2; exit 1
fi
test -e "$HOME/work/project-a/.git/log"
grep -q 'Mac/Linux differ' "$root/fail"
grep -q 'mutagen sync resume' "$TEST_LOG"

# A stale or modified working file also blocks release.
rm -r "$HOME/work/project-a/.git"
printf 'changed only on Linux\n' > "$HOME/work/project-a/file.txt"
if printf 'RELEASE project-a\n' | bash "$scripts/mac-data-sync-release" project-a > "$root/fail" 2>&1; then
  echo 'FAIL: released diverged work' >&2; exit 1
fi
grep -q 'Mac/Linux differ' "$root/fail"
printf 'same\n' > "$HOME/work/project-a/file.txt"

# A complete recursively matched subtree, including .git, can be released.
# Subdirectories deeper than the picker view must also be considered.
mkdir -p "$HOME/work/project-a/src/deep/level5" "$TEST_MAC/project-a/src/deep/level5"
printf 'nested data\n' > "$HOME/work/project-a/src/deep/level5/nested.txt"
printf 'nested data\n' > "$TEST_MAC/project-a/src/deep/level5/nested.txt"
mkdir -p "$HOME/work/project-a/.git" "$TEST_MAC/project-a/.git"
printf 'shared history\n' > "$HOME/work/project-a/.git/log"
printf 'shared history\n' > "$TEST_MAC/project-a/.git/log"
write_state healthy
printf 'RELEASE project-a\n' | bash "$scripts/mac-data-sync-release" project-a > "$root/pass" 2>&1
! test -e "$HOME/work/project-a"
test -f "$TEST_MAC/project-a/file.txt"
test -f "$TEST_MAC/project-a/.git/log"
test -f "$TEST_MAC/project-a/src/deep/level5/nested.txt"
! test -e "$XDG_STATE_HOME/mac-data-sync/$id"
grep -q 'Released Linux copy' "$root/pass"

echo 'Mock UI and release tests PASS'
