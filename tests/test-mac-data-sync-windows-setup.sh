#!/usr/bin/env bash
set -euo pipefail

# Smoke-test Windows/WSL bootstrap without changing CI runner packages.
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export HOME="$root/home"
mkdir -p "$HOME/.local/bin" "$root/mocks"

cat > "$root/mocks/sudo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'sudo %s\n' "$*" >> "$SETUP_TEST_LOG"
# apt-get invocation is mocked, never executed.
SH
cat > "$HOME/.local/bin/mutagen" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  version) printf '0.18.1\n' ;;
  daemon) [[ "${2:-}" == start ]] ;;
  *) exit 1 ;;
esac
SH
chmod +x "$root/mocks/sudo" "$HOME/.local/bin/mutagen"
export SETUP_TEST_LOG="$root/setup-commands" PATH="$root/mocks:$HOME/.local/bin:$PATH"

bash -n "$repo_root/windows/setup-wsl.sh"
bash -n "$repo_root/windows/wsl-keepalive.sh"
bash -n "$repo_root/windows/wsl-entry.sh"

bash "$repo_root/windows/setup-wsl.sh" "$repo_root" 100.64.100.10 mac-user > "$root/setup.out"
grep -qF 'Host mac' "$HOME/.ssh/config"
grep -qF 'HostName 100.64.100.10' "$HOME/.ssh/config"
grep -qF 'User mac-user' "$HOME/.ssh/config"
grep -qF 'sudo apt-get install' "$SETUP_TEST_LOG"
grep -qF 'sudo install -m 755' "$SETUP_TEST_LOG"
grep -qF '/usr/local/bin/mac-data-sync-wsl' "$SETUP_TEST_LOG"

for helper in mac-data-sync mac-data-sync-ui mac-data-sync-browse mac-data-sync-release mac-data-sync-keepalive; do
  test -x "$HOME/.local/bin/$helper"
  bash -n "$HOME/.local/bin/$helper"
done

# Verify the WSL entrypoint forwards Unicode/space-bearing file names as one arg.
cat > "$HOME/.local/bin/mac-data-sync" <<'SH'
#!/usr/bin/env bash
printf 'ARG:%s\n' "$@" > "$CLI_ARGUMENT_LOG"
SH
chmod +x "$HOME/.local/bin/mac-data-sync"
export CLI_ARGUMENT_LOG="$root/cli-arguments"
bash "$repo_root/windows/wsl-entry.sh" start 'notes/日本語 file.txt'
grep -qFx 'ARG:start' "$CLI_ARGUMENT_LOG"
grep -qFx 'ARG:notes/日本語 file.txt' "$CLI_ARGUMENT_LOG"

# Restore original installed command for re-install idempotency test.
install -m 755 "$repo_root/scripts/mac-data-sync" "$HOME/.local/bin/mac-data-sync"

# Idempotent setup must not duplicate an existing SSH alias.
bash "$repo_root/windows/setup-wsl.sh" "$repo_root" 100.64.100.10 mac-user > "$root/setup2.out"
test "$(grep -c '^Host mac$' "$HOME/.ssh/config")" = 1
grep -qF 'leaving the configuration unchanged' "$root/setup2.out"

# Reject unsafe host strings instead of injecting arbitrary SSH configuration.
if bash "$repo_root/windows/setup-wsl.sh" "$repo_root" 'mac;bad' alice > "$root/error" 2>&1; then
  echo 'Invalid host accepted' >&2
  exit 1
fi

echo 'Windows WSL bootstrap mock tests PASS'
