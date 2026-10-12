#!/usr/bin/env bash
set -euo pipefail

script=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/mac-data-sync}
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin" "$root/home"
export HOME="$root/home" XDG_STATE_HOME="$root/state" MAC_DATA_REMOTE=mac
export PATH="$root/bin:$PATH" TEST_LOG="$root/commands"

# Mocks test orchestration; actual Mac SSH and Mutagen need real-machine checks.
cat > "$root/bin/ssh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
arg=${*: -1}
if [[ "$arg" == MAC_DEPTH=* ]]; then
  printf './project-a\0./project-a/src\0./documents/report.pdf\0./project-b\0./notes/日本語 file.txt\0'
elif [[ "$arg" == MAC_REL_B64=* ]]; then
  encoded=${arg#MAC_REL_B64=}
  encoded=${encoded%% *}
  path=$(printf '%s' "$encoded" | base64 -d)
  case "$path" in
    project-a|project-a/src|project-b) printf directory ;;
    documents/report.pdf|notes/'日本語 file.txt') printf file ;;
    *) exit 2 ;;
  esac
else
  exit 10
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
  printf '[{"name":"%s","paused":false,"status":"watching","successfulCycles":1,"alpha":{"connected":true,"scanned":true},"beta":{"connected":true,"scanned":true}}]\n' "$id"
fi
SH
cat > "$root/bin/fzf" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
case "${FZF_SELECTION:-one}" in
  one)   printf '%s\0' './project-a' ;;
  multi) printf '%s\0' './project-b' './documents/report.pdf' ;;
  clash) printf '%s\0' './project-a' './project-a/src' ;;
  *) exit 1 ;;
esac
SH
chmod +x "$root/bin/ssh" "$root/bin/mutagen" "$root/bin/fzf"

bash -n "$script"
"$script" ls > "$root/list"
grep -q '^project-a$' "$root/list"
grep -q '^documents/report.pdf$' "$root/list"
grep -q '^notes/日本語 file.txt$' "$root/list"

printf 'y\n' | FZF_SELECTION=multi "$script" pick > "$root/picker-log" 2>&1
[[ -d "$HOME/work/project-b" ]]
[[ -d "$HOME/work/documents" ]]
[[ ! -e "$HOME/work/documents/report.pdf" ]]
grep -qF '[mac:~/data/project-b]' "$TEST_LOG"
grep -qF '[mac:~/data/documents/report.pdf]' "$TEST_LOG"

if "$script" start project-b > "$root/error" 2>&1; then exit 1; fi
grep -q 'Overlapping' "$root/error"
"$script" status project-b
"$script" pause project-b
"$script" resume project-b
"$script" flush project-b
"$script" terminate project-b
[[ -d "$HOME/work/project-b" ]]

# Selecting a parent plus a child creates one recursive session for the parent.
count_before=$(grep -c 'mutagen \[sync\] \[create\]' "$TEST_LOG")
printf 'y\n' | FZF_SELECTION=clash "$script" pick > "$root/recursive" 2>&1
count_after=$(grep -c 'mutagen \[sync\] \[create\]' "$TEST_LOG")
[[ "$count_after" -eq $((count_before + 1)) ]]
grep -qF '[mac:~/data/project-a]' "$TEST_LOG"
! grep -qF '[mac:~/data/project-a/src]' "$TEST_LOG"
grep -qF '[--no-global-configuration]' "$TEST_LOG"
grep -qF '[--no-ignore-vcs]' "$TEST_LOG"
! grep -qF '[--ignore-vcs]' "$TEST_LOG"
grep -qF '[--template] [{{json .}}]' "$TEST_LOG"
grep -q 'Ready: Mac ~/data/project-a' "$root/recursive"

if "$script" start ../secrets > "$root/error" 2>&1; then exit 1; fi
if "$script" start project-a/../../secrets > "$root/error" 2>&1; then exit 1; fi
rmdir "$HOME/work/project-b"
ln -s "$root" "$HOME/work/project-b"
if "$script" start project-b > "$root/error" 2>&1; then exit 1; fi

"$script" start 'notes/日本語 file.txt'
grep -qF '[mac:~/data/notes/日本語 file.txt]' "$TEST_LOG"
"$script" terminate 'notes/日本語 file.txt'
[[ -L "$HOME/work/project-b" ]]
[[ -d "$HOME/work/documents" ]]

echo 'mac-data-sync: mock CLI tests PASS'
