{ pkgs, unstable }:
let
  tools = import ../home/desktop/packages.nix { inherit pkgs unstable; };
in
pkgs.runCommand "dotfiles-desktop-tools-check" {
  nativeBuildInputs = [ tools.xremap ];
} ''
  export HOME="$TMPDIR/home-test"
  export XDG_STATE_HOME="$HOME/.local/state"
  export XDG_RUNTIME_DIR="$TMPDIR/runtime"
  mkdir -p "$HOME"
  mkdir -m 700 "$XDG_RUNTIME_DIR"
  xremap --help
  for profile in ${tools.profiles}/*.yml; do
    xremap --desktop=none --watch=device --no-window-logging --allow-launch=false \
      --validate-config "$profile"
  done
  test "$(${tools.keyboard}/bin/keyboard-profile status)" = dvorak
  # Building these derivations also runs writeShellApplication's ShellCheck.
  for executable in \
    ${tools.clipboard}/bin/desktop-clipboard \
    ${tools.clipboardMenu}/bin/desktop-clipboard-menu \
    ${tools.locker}/bin/desktop-lock \
    ${tools.cheatsheet}/bin/hypr-cheatsheet \
    ${tools.launcher}/bin/desktop-launcher; do
    test -x "$executable"
  done
  ${tools.dms}/bin/dms --help > /dev/null
  touch "$out"
''
