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

count_before=$(grep -c 'mutagen \[sync\] \[create\]' "$TEST_LOG")
if printf 'y\n' | FZF_SELECTION=clash "$script" pick > "$root/error" 2>&1; then exit 1; fi
grep -q 'nested paths' "$root/error"
count_after=$(grep -c 'mutagen \[sync\] \[create\]' "$TEST_LOG")
[[ "$count_before" == "$count_after" ]]

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
