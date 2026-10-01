{ config, pkgs, unstable, lib, ... }:
let
  target = "wayland-session@Hyprland.target";
  wallpaper = pkgs.nixos-artwork.wallpapers.nineish-catppuccin-mocha-alt.gnomeFilePath;
  # No application filters: build one compositor-independent evdev/uinput binary.
  xremap = unstable.xremap.overrideAttrs (_: { buildFeatures = []; });
  profiles = pkgs.runCommand "dotfiles-keyboard-profiles" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    python3 ${./generate_xremap.py} "$out"
  '';
  keyboard = pkgs.writeShellApplication {
    name = "keyboard-profile";
    runtimeInputs = [ xremap pkgs.coreutils pkgs.util-linux pkgs.systemd pkgs.libnotify ];
    text = ''
      export DOTFILES_XREMAP_PROFILES=${profiles}
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
    text = ''
      systemctl --user --no-block restart dotfiles-clipboard-menu.service
    '';
  };
  locker = pkgs.writeShellApplication {
    name = "desktop-lock";
    runtimeInputs = [ clipboard pkgs.hyprlock pkgs.systemd pkgs.util-linux pkgs.coreutils pkgs.libnotify ];
    text = builtins.readFile ./lock.sh;
  };
  cheatsheet = pkgs.writeShellApplication {
    name = "hypr-cheatsheet";
    runtimeInputs = [ pkgs.python3 pkgs.hyprland pkgs.rofi ];
    text = ''exec python3 ${./cheatsheet.py}'';
  };
  launcher = pkgs.writeShellApplication {
    name = "desktop-launcher";
    runtimeInputs = [ pkgs.uwsm pkgs.rofi ];
    text = ''
      exec uwsm app -- rofi -show drun -show-icons -run-command "uwsm app -- {cmd}"
    '';
  };
  sessionUnit = description: {
    Description = description;
    After = [ "graphical-session.target" ];
    PartOf = [ target ];
  };
  daemon = description: command: {
    Unit = sessionUnit description;
    Service = { ExecStart = command; Restart = "on-failure"; RestartSec = 2; };
    Install.WantedBy = [ target ];
  };
  clipboardHardening = {
    UMask = "0077";
    LimitCORE = 0;
    MemorySwapMax = 0;
    NoNewPrivileges = true;
    RestrictSUIDSGID = true;
    RestrictAddressFamilies = [ "AF_UNIX" ];
    # Do not log clipboard contents, Rofi previews, or subprocess output.
    StandardOutput = "null";
    StandardError = "journal";
  };
  entry = name: exec: icon: {
    inherit name exec icon;
    terminal = false;
    categories = [ "Utility" ];
  };
in {
  imports = [ ./waybar.nix ];

  home.packages = [
    keyboard clipboard clipboardMenu locker cheatsheet launcher
    pkgs.kitty pkgs.nautilus pkgs.rofi pkgs.wev
    pkgs.brightnessctl pkgs.pavucontrol
  ];

  xdg.configFile = {
    "hypr/hyprland.conf".source = ../../hyprland.conf;
    "hypr/commands.conf".text = ''
      $terminal = ${pkgs.uwsm}/bin/uwsm app -- ${pkgs.kitty}/bin/kitty
      $fileManager = ${pkgs.uwsm}/bin/uwsm app -- ${pkgs.nautilus}/bin/nautilus
      $launcher = ${launcher}/bin/desktop-launcher
      $cheatsheet = ${pkgs.uwsm}/bin/uwsm app -- ${cheatsheet}/bin/hypr-cheatsheet
      $keyboard = ${keyboard}/bin/keyboard-profile toggle
      $clipboard = ${clipboardMenu}/bin/desktop-clipboard-menu
      $clipboardPrivacy = ${clipboard}/bin/desktop-clipboard toggle
      $clipboardClear = ${clipboard}/bin/desktop-clipboard clear
      $lock = ${pkgs.systemd}/bin/loginctl lock-session
      $logout = ${pkgs.uwsm}/bin/uwsm stop
      $volume = ${pkgs.wireplumber}/bin/wpctl
      $brightness = ${pkgs.brightnessctl}/bin/brightnessctl
    '';
    "rofi/config.rasi".source = ./rofi.rasi;
    "hypr/hyprpaper.conf".text = ''
      preload = ${wallpaper}
      wallpaper = ,${wallpaper}
      splash = false
    '';
    "hypr/hyprlock.conf".text = ''
      general {
        hide_cursor = true
      }
      background {
        monitor =
        path = ${wallpaper}
        blur_passes = 2
      }
      input-field {
        monitor =
        size = 320, 60
        position = 0, -80
        halign = center
        valign = center
        outline_thickness = 2
        outer_color = rgb(cba6f7)
        inner_color = rgb(1e1e2e)
        font_color = rgb(cdd6f4)
        placeholder_text = Password
      }
    '';
    "hypr/hypridle.conf".text = ''
      general {
        lock_cmd = ${locker}/bin/desktop-lock
        before_sleep_cmd = ${pkgs.systemd}/bin/loginctl lock-session
        after_sleep_cmd = ${pkgs.hyprland}/bin/hyprctl dispatch dpms on
        inhibit_sleep = 3
      }
      listener {
        timeout = 300
        on-timeout = ${pkgs.systemd}/bin/loginctl lock-session
      }
      listener {
        timeout = 600
        on-timeout = ${pkgs.hyprland}/bin/hyprctl dispatch dpms off
        on-resume = ${pkgs.hyprland}/bin/hyprctl dispatch dpms on
      }
    '';
    "mako/config".text = ''
      font=Sans 11
      background-color=#1e1e2eee
      text-color=#cdd6f4ff
      border-color=#cba6f7ff
      border-size=2
      border-radius=12
      default-timeout=6000
      max-history=0
    '';
    # Fcitx must not replace the shared jp base with us(dvp).
    "fcitx5/profile".text = ''
      [Groups/0]
      Name=Default
      Default Layout=jp
      DefaultIM=mozc

      [Groups/0/Items/0]
      Name=keyboard-jp
      Layout=

      [Groups/0/Items/1]
      Name=mozc
      Layout=

      [GroupOrder]
      0=Default
    '';
    "xremap/profiles".source = profiles;
  };

  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      sources = [ (lib.hm.gvariant.mkTuple [ "xkb" "jp" ]) ];
      xkb-options = [];
    };
    "org/gnome/desktop/wm/keybindings" = {
      switch-input-source = [];
      switch-input-source-backward = [];
    };
    "org/gnome/shell".disabled-extensions = [ pkgs.gnomeExtensions.clipboard-history.extensionUuid ];
    "org/gnome/desktop/background" = {
      picture-uri = "file://${wallpaper}";
      picture-uri-dark = "file://${wallpaper}";
      picture-options = "zoom";
    };
    "org/gnome/settings-daemon/plugins/media-keys".custom-keybindings = [
      "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/dotfiles-keyboard/"
    ];
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/dotfiles-keyboard" = {
      name = "QWERTY / custom Dvorak";
      command = "${keyboard}/bin/keyboard-profile toggle";
      binding = "<Super>F2";
    };
  };

  systemd.user.services = {
    xremap = {
      Unit = {
        Description = "Shared JIS/QWERTY and custom Dvorak remapper";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${keyboard}/bin/keyboard-profile run";
        Restart = "on-failure";
        RestartSec = 2;
        UMask = "0077";
        LimitCORE = 0;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
    dotfiles-clipboard = {
      Unit = sessionUnit "Text clipboard history in private tmpfs";
      Service = clipboardHardening // {
        Type = "exec";
        ExecStart = "${clipboard}/bin/desktop-clipboard watch";
        ExecStopPost = "${clipboard}/bin/desktop-clipboard purge";
        RuntimeDirectory = "dotfiles-clipboard";
        RuntimeDirectoryMode = "0700";
        Restart = "on-failure";
        RestartSec = 2;
        TimeoutStopSec = 5;
      };
      Install.WantedBy = [ target ];
    };
    dotfiles-clipboard-menu = {
      Unit = {
        Description = "Private clipboard selector";
        Requisite = [ "dotfiles-clipboard.service" ];
        After = [ "dotfiles-clipboard.service" ];
        PartOf = [ "dotfiles-clipboard.service" target ];
      };
      Service = clipboardHardening // {
        # Keep wl-copy's child alive after selection, until the next menu/purge.
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "infinity";
        ExecStart = "${clipboard}/bin/desktop-clipboard menu";
      };
    };
    dotfiles-hyprpaper = daemon "Hyprland wallpaper" "${pkgs.hyprpaper}/bin/hyprpaper";
    dotfiles-hypridle = daemon "Lock and idle management" "${pkgs.hypridle}/bin/hypridle";
    dotfiles-notifications = daemon "Hyprland notifications" "${pkgs.mako}/bin/mako";
    dotfiles-polkit = daemon "Hyprland authentication agent" "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
  };

  xdg.desktopEntries = {
    dotfiles-keyboard = entry "Action: QWERTY / custom Dvorak" "${keyboard}/bin/keyboard-profile toggle" "input-keyboard";
    dotfiles-shortcuts = (entry "Action: Hyprland shortcuts" "${cheatsheet}/bin/hypr-cheatsheet" "input-keyboard") // { onlyShowIn = [ "Hyprland" ]; };
    dotfiles-clipboard = (entry "Action: Clipboard history" "${clipboardMenu}/bin/desktop-clipboard-menu" "edit-paste") // { onlyShowIn = [ "Hyprland" ]; };
    dotfiles-clipboard-privacy = (entry "Action: Pause / resume clipboard history" "${clipboard}/bin/desktop-clipboard toggle" "changes-prevent") // { onlyShowIn = [ "Hyprland" ]; };
    dotfiles-clipboard-clear = (entry "Action: Clear clipboard history" "${clipboard}/bin/desktop-clipboard clear" "edit-clear") // { onlyShowIn = [ "Hyprland" ]; };
    dotfiles-lock = (entry "Action: Lock screen" "${pkgs.systemd}/bin/loginctl lock-session" "system-lock-screen") // { onlyShowIn = [ "Hyprland" ]; };
    dotfiles-waybar = (entry "Action: Restart Waybar" "${pkgs.systemd}/bin/systemctl --user restart waybar.service" "view-refresh") // { onlyShowIn = [ "Hyprland" ]; };
  };
}
