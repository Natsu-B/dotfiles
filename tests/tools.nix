{ pkgs, unstable }:
let
  tools = import ../home/desktop/packages.nix { inherit pkgs unstable; };
in
pkgs.runCommand "dotfiles-desktop-tools-check" {
  nativeBuildInputs = [ tools.xremap pkgs.python3 pkgs.nodejs ];
} ''
  export HOME="$TMPDIR/home-test"
  export XDG_STATE_HOME="$HOME/.local/state"
  export XDG_RUNTIME_DIR="$TMPDIR/runtime"
  mkdir -p "$HOME"
  mkdir -m 700 "$XDG_RUNTIME_DIR"
  python3 ${./validate_xremap.py} ${tools.profiles}
  node ${./test_dms_app_index.js} ${../home/desktop/dms-app-shortcuts/AppIndex.js}
  test "$(${tools.keyboard}/bin/keyboard-profile status)" = dvorak
  # Building these derivations also runs writeShellApplication's ShellCheck.
  for executable in \
    ${tools.clipboard}/bin/desktop-clipboard \
    ${tools.clipboardMenu}/bin/desktop-clipboard-menu \
    ${tools.locker}/bin/desktop-lock \
    ${tools.cheatsheet}/bin/hypr-cheatsheet \
    ${tools.launcher}/bin/desktop-launcher \
    ${tools.windowSwitcher}/bin/desktop-window-switcher; do
    test -x "$executable"
  done
  ${tools.trackpoint}/bin/desktop-trackpoint --help > /dev/null
  ${tools.dms}/bin/dms --help > /dev/null
  touch "$out"
''
