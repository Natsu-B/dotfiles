#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin" "$root/home/work/local-project/src" "$root/home/work/docs"
export HOME="$root/home" XDG_STATE_HOME="$root/state" MAC_DATA_REMOTE=mac
export PATH="$root/bin:$PATH" TEST_LOG="$root/calls" MAC_DATA_SYNC_BIN="$repo/scripts/mac-data-sync"
export FZF_COUNT="$root/count"
echo 0 > "$FZF_COUNT"
echo content > "$HOME/work/local-project/src/code.c"
echo local-file > "$HOME/work/docs/new.txt"
: > "$TEST_LOG"

cat > "$root/bin/ssh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
arg=${*: -1}
script=$(cat)
encoded=${arg#MAC_REL_B64=}
encoded=${encoded%% *}
relative=$(printf '%s' "$encoded" | base64 -d)
if [[ "$script" == *'find . -mindepth 1 -maxdepth 1 -print0'* ]]; then
  printf 'BROWSE:%s\n' "$relative" >> "$TEST_LOG"
  case "$relative" in
    '') printf 'D\tproject-a\0D\tproject-b\0D\tdocuments\0D\tnotes\0' ;;
    documents) printf 'F\treport.pdf\0' ;;
    project-a) printf 'D\tsrc\0F\tREADME.md\0' ;;
    *) : ;;
  esac
elif [[ "$script" == *'mkdir -- "$root"'* ]]; then
  printf 'PREPARE:%s\n' "$relative" >> "$TEST_LOG"
else
  printf 'PROBE:%s\n' "$relative" >> "$TEST_LOG"
  case "$relative" in
    project-a|project-a/src|project-b|documents|notes) printf directory ;;
    documents/report.pdf|notes/'日本語 file.txt') printf file ;;
    local-project|docs/new.txt) printf missing ;;
    *) exit 2 ;;
  esac
fi
SH
cat > "$root/bin/mutagen" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'mutagen' >> "$TEST_LOG"
for arg in "$@"; do printf ' [%s]' "$arg" >> "$TEST_LOG"; done
printf '\n' >> "$TEST_LOG"
if [[ "${1:-}" == sync && "${2:-}" == list && "${3:-}" == --template ]]; then
  id=${5:-}
  jq -cn --arg id "$id" --arg status "${TEST_SYNC_STATE:-watching}" '
    [{name:$id, paused:($status=="paused"), status:(if $status=="paused" then "watching" else $status end), successfulCycles:1,
      alpha:{connected:($status!="offline"),scanned:true},
      beta:{connected:true,scanned:true,scanProblems:(if $status=="problem" then
        [{path:".nix-python",error:"invalid symbolic link: target is absolute"}] else [] end)}}]'
fi
SH
cat > "$root/bin/fzf" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
file=$(mktemp)
cat > "$file"
n=$(cat "$FZF_COUNT")
n=$((n+1))
echo "$n" > "$FZF_COUNT"
IFS=',' read -r -a steps <<< "${FZF_STEPS:-STOP}"
step=${steps[n-1]:-STOP}
case "$step" in
  STOP) rm -f "$file"; exit 1 ;;
  OPEN-DOCS) target=$'OPEN\tdocuments/' ;;
  SYNC-REPORT) target=$'SYNC\treport.pdf' ;;
  SYNC-PROJECT) target=$'SYNC\tproject-a/ (sync recursively)' ;;
  SYNC-LOCAL) target=$'SYNC\tlocal-project/ (sync recursively)' ;;
  SYNC-LOCALFILE) target=$'SYNC\tnew.txt' ;;
  OPEN-LOCALDOCS) target=$'OPEN\tdocs/' ;;
  *) exit 5 ;;
esac
while IFS= read -r -d '' row; do
  if [[ "$row" == "$target" ]]; then
    printf '%s\0' "$row"
    rm -f "$file"
    exit 0
  fi
done < "$file"
printf 'fzf mock could not find %s\n' "$target" >&2
exit 5
SH
chmod +x "$root/bin/"*
install -m 755 "$repo/scripts/mac-data-sync-browse" "$root/bin/mac-data-sync-browse"

bash -n "$repo/scripts/mac-data-sync"
bash -n "$repo/scripts/mac-data-sync-browse"

# Listing is strictly one level, not recursive. Navigating into the folder is
# a second SSH request and returns only that folder's entries.
"$repo/scripts/mac-data-sync" ls > "$root/list"
grep -qFx 'documents/' "$root/list"
! grep -q 'report.pdf' "$root/list"
"$repo/scripts/mac-data-sync" ls documents > "$root/nested"
grep -qFx report.pdf "$root/nested"
grep -qFx 'BROWSE:' "$TEST_LOG"
grep -qFx 'BROWSE:documents' "$TEST_LOG"

# Navigate into Mac documents and choose one file.
echo 0 > "$FZF_COUNT"
printf 'y\n' | FZF_STEPS=OPEN-DOCS,SYNC-REPORT,STOP \
  "$repo/scripts/mac-data-sync" pick > "$root/pick-output" 2>&1
grep -qF '[mac:~/data/documents/report.pdf]' "$TEST_LOG"
grep -q 'Ready: Mac ~/data/documents/report.pdf' "$root/pick-output"

# Selecting a folder copies the entire subtree, not just its visible entries.
echo 0 > "$FZF_COUNT"
printf 'y\n' | FZF_STEPS=SYNC-PROJECT,STOP \
  "$repo/scripts/mac-data-sync" pick > "$root/folder-output" 2>&1
grep -qF '[mac:~/data/project-a]' "$TEST_LOG"
grep -q 'Ready: Mac ~/data/project-a' "$root/folder-output"
grep -qF '[--no-ignore-vcs]' "$TEST_LOG"

# Publishing an existing Linux directory works when Mac path is absent.
echo 0 > "$FZF_COUNT"
printf 'y\n' | FZF_STEPS=SYNC-LOCAL,STOP \
  "$repo/scripts/mac-data-sync" browse-local > "$root/linux-output" 2>&1
grep -qFx 'PREPARE:local-project' "$TEST_LOG"
grep -qF '[mac:~/data/local-project]' "$TEST_LOG"
grep -q 'Ready: Mac ~/data/local-project' "$root/linux-output"
grep -q 'Uploading Linux .*local-project to Mac ~/data/local-project' "$root/linux-output"
! grep -q 'Copying Mac local-project' "$root/linux-output"

# The same works for a Linux-only file in a nested folder.
echo 0 > "$FZF_COUNT"
printf 'y\n' | FZF_STEPS=OPEN-LOCALDOCS,SYNC-LOCALFILE,STOP \
  "$repo/scripts/mac-data-sync" browse-local > "$root/new-file-output" 2>&1
grep -qFx 'PREPARE:docs/new.txt' "$TEST_LOG"
grep -qF '[mac:~/data/docs/new.txt]' "$TEST_LOG"

# Existing setup is an informational no-op, with its actual health shown.
before=$(grep -c 'mutagen \[sync\] \[create\]' "$TEST_LOG")
"$repo/scripts/mac-data-sync" start project-a > "$root/existing" 2>&1
grep -q 'Already configured: project-a' "$root/existing"
grep -q 'Status: Active' "$root/existing"
TEST_SYNC_STATE=problem "$repo/scripts/mac-data-sync" start project-a > "$root/problem" 2>&1
grep -q 'Needs attention' "$root/problem"
grep -q 'Linux: .nix-python' "$root/problem"
grep -q 'absolute symlink' "$root/problem"
for state in paused offline halted-on-root-deletion; do
  TEST_SYNC_STATE=$state "$repo/scripts/mac-data-sync" check project-a > "$root/$state" 2>&1
done
grep -q 'Status: Paused' "$root/paused"
grep -q 'Status: Offline' "$root/offline"
grep -q 'Status: Stopped' "$root/halted-on-root-deletion"
"$repo/scripts/mac-data-sync" start project-a/src > "$root/covered" 2>&1
grep -q 'Already included: project-a/src' "$root/covered"
! grep -q 'terminate it first' "$root/existing" "$root/problem" "$root/covered"
test "$(grep -c 'mutagen \[sync\] \[create\]' "$TEST_LOG")" = "$before"

# Reselecting a configured folder needs neither a new-start confirmation nor a new session.
echo 0 > "$FZF_COUNT"
FZF_STEPS=SYNC-PROJECT,STOP "$repo/scripts/mac-data-sync" pick < /dev/null > "$root/reselect" 2>&1
grep -q 'Already configured: project-a' "$root/reselect"
grep -q 'No new synchronization to start' "$root/reselect"
! grep -q 'Start? \[y/N\]' "$root/reselect"
test "$(grep -c 'mutagen \[sync\] \[create\]' "$TEST_LOG")" = "$before"

# A requested parent reports every separately synchronized child, without ending any.
for child in notes/one notes/two; do
  id="mac-data-$(printf %s "$child" | sha256sum | cut -c1-20)"
  printf '%s\n' "$child" > "$XDG_STATE_HOME/mac-data-sync/$id"
done
if "$repo/scripts/mac-data-sync" start notes > "$root/overlap" 2>&1; then exit 1; fi
grep -q 'Cannot add notes' "$root/overlap"
grep -q 'notes/one' "$root/overlap"
grep -q 'notes/two' "$root/overlap"
! grep -q 'terminate it first' "$root/overlap"
! grep -q 'mutagen \[sync\] \[terminate\]' "$TEST_LOG"

# A nonexistent path on both ends must not silently initialize empty archive.
if "$repo/scripts/mac-data-sync" start does-not-exist > "$root/fail" 2>&1; then
  echo 'Expected failure for two missing paths' >&2; exit 1
fi

# Traversal and symlink escapes are refused.
if "$repo/scripts/mac-data-sync" start ../secrets > "$root/fail" 2>&1; then exit 1; fi
ln -s "$root" "$HOME/work/link"
if "$repo/scripts/mac-data-sync" start link/src > "$root/fail" 2>&1; then exit 1; fi
echo 'Shallow folder browser and Linux-first CLI mock tests PASS'
