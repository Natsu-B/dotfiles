{ pkgs, unstable }:
let
  wallpaper = pkgs.nixos-artwork.wallpapers.nineish-catppuccin-mocha-alt.gnomeFilePath;
  # Keep the package's supported feature/install combination. Normalize the
  # variant executable without rebuilding xremap or changing its Cargo features.
  # The service selects --desktop=none; application filters are unused.
  xremap = pkgs.runCommand "dotfiles-xremap-${unstable.xremap.version}" {} ''
    mkdir -p "$out/bin"
    for binary in ${unstable.xremap}/bin/xremap ${unstable.xremap}/bin/xremap-wlroots; do
      if test -x "$binary"; then
        ln -s "$binary" "$out/bin/xremap"
        echo "Using xremap executable: $binary"
        break
      fi
    done
    if ! test -x "$out/bin/xremap"; then
      echo 'No supported xremap executable was installed' >&2
      ls -la ${unstable.xremap}/bin >&2
      exit 1
    fi
  '';
  profiles = pkgs.runCommand "dotfiles-keyboard-profiles" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    python3 ${./generate_xremap.py} "$out"
  '';
  keyboard = pkgs.writeShellApplication {
    name = "keyboard-profile";
    runtimeInputs = [ xremap pkgs.coreutils pkgs.util-linux pkgs.systemd pkgs.libnotify ];
    text = ''export DOTFILES_XREMAP_PROFILES=${profiles}
    '' + builtins.readFile ./keyboard-profile.sh;
  };
  clipboard = pkgs.writeShellApplication {
    name = "desktop-clipboard";
    runtimeInputs = [ pkgs.python3 pkgs.cliphist unstable.wl-clipboard pkgs.rofi pkgs.coreutils pkgs.systemd ];
    text = ''
      export DOTFILES_CLIPBOARD_SELF="$0"
      exec python3 ${./clipboard.py} "$@"
    '';
  };
  clipboardMenu = pkgs.writeShellApplication {
    name = "desktop-clipboard-menu";
    runtimeInputs = [ pkgs.systemd ];
    text = ''systemctl --user --no-block restart dotfiles-clipboard-menu.service'';
  };
  locker = pkgs.writeShellApplication {
    name = "desktop-lock";
    runtimeInputs = [ clipboard pkgs.hyprlock pkgs.systemd pkgs.util-linux pkgs.coreutils pkgs.libnotify ];
    text = builtins.readFile ./lock.sh;
  };
  # Retain a shell-independent recovery view of the actual compositor bindings.
  cheatsheet = pkgs.writeShellApplication {
    name = "hypr-cheatsheet";
    runtimeInputs = [ pkgs.python3 pkgs.hyprland pkgs.rofi ];
    text = ''exec python3 ${./cheatsheet.py}'';
  };
  dms = unstable.dms-shell;
  launcher = pkgs.writeShellApplication {
    name = "desktop-launcher";
    runtimeInputs = [ dms ];
    text = ''exec dms ipc call spotlight toggle'';
  };
in {
  inherit wallpaper xremap profiles keyboard clipboard clipboardMenu locker cheatsheet dms launcher;
}
