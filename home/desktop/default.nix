{ config, pkgs, unstable, lib, ... }:
let
  target = "wayland-session@hyprland.desktop.target";
  tools = import ./packages.nix { inherit pkgs unstable; };
  inherit (tools) wallpaper keyboard clipboard clipboardMenu locker cheatsheet profiles;
  clipboardHardening = {
    UMask = "0077";
    LimitCORE = 0;
    MemorySwapMax = 0;
    NoNewPrivileges = true;
    RestrictSUIDSGID = true;
    RestrictAddressFamilies = [ "AF_UNIX" ];
    StandardOutput = "null";
    StandardError = "journal";
  };
  entry = name: exec: icon: {
    inherit name exec icon;
    terminal = false;
    categories = [ "Utility" ];
    # These dotfiles provide Hyprland and GNOME sessions. Hide Hyprland actions
    # in the GNOME fallback using a registered desktop ID. OnlyShowIn=Hyprland
    # fails desktop-file-validate; X-Hyprland would not match the real session.
    settings.NotShowIn = "GNOME;";
  };
in {
  imports = [ ./dms.nix ./cursor.nix ];
  home.packages = [ keyboard clipboard clipboardMenu locker cheatsheet pkgs.kitty pkgs.nautilus pkgs.rofi pkgs.wev ];

  xdg.configFile = {
    # Rofi is only a private clipboard picker and an emergency shortcut viewer.
    "rofi/config.rasi".source = ./rofi.rasi;
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
    # DMS controls the idle timers. hypridle only bridges logind/suspend and
    # holds the sleep inhibitor until an ext-session-lock surface is ready.
    "hypr/hypridle.conf".text = ''
      general {
        lock_cmd = ${locker}/bin/desktop-lock
        before_sleep_cmd = ${pkgs.systemd}/bin/loginctl lock-session
        after_sleep_cmd = ${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
        inhibit_sleep = 3
      }
    '';
    "fcitx5/profile".text = ''
      [Groups/0]
      Name=Default
      Default Layout=jp
      DefaultIM=karukan

      [Groups/0/Items/0]
      Name=keyboard-jp
      Layout=

      [Groups/0/Items/1]
      Name=karukan
      Layout=

      [GroupOrder]
      0=Default
    '';
    "karukan-im/config.toml".text = ''
      [conversion]
      strategy = "adaptive"
      num_candidates = 9
      use_context = true
      context_chars = 10
      beam_width = 3
      # The first NPU graph compilation is intentionally slower than steady state.
      # Do not let that one-time cost permanently switch the adaptive strategy.
      max_latency_ms = 0
      model = "jinen-v2-small-q4"
      light_model = "jinen-v2-xsmall-q4"
      n_threads = 4
      live_conversion = true

      [models]
      jinen-v2-small-q4 = { repo = "togatogah/jinen-v2-small.gguf@94ca7129a677d9f0fc671dd92af1ed4904b50ef6", filename = "jinen-v2-small-Q4_K_M.gguf" }
      jinen-v2-xsmall-q4 = { repo = "togatogah/jinen-v2-xsmall.gguf@b91eac974998a37423ca8a1198fd7c5631b06e57", filename = "jinen-v2-xsmall-Q4_K_M.gguf" }
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
      Unit = {
        Description = "Text clipboard history in private tmpfs";
        After = [ "graphical-session.target" ];
        PartOf = [ target ];
      };
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
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "infinity";
        ExecStart = "${clipboard}/bin/desktop-clipboard menu";
      };
    };
    dotfiles-hypridle = {
      Unit = {
        Description = "Secure lock/suspend bridge (idle timers belong to DMS)";
        After = [ "graphical-session.target" ];
        PartOf = [ target ];
      };
      Service = { ExecStart = "${pkgs.hypridle}/bin/hypridle"; Restart = "on-failure"; RestartSec = 2; };
      Install.WantedBy = [ target ];
    };
  };

  xdg.desktopEntries = {
    dotfiles-keyboard = (entry "Action: QWERTY / custom Dvorak" "${keyboard}/bin/keyboard-profile toggle" "input-keyboard") // { settings = {}; };
    dotfiles-shortcuts-recovery = entry "Action: Shortcut recovery viewer" "${cheatsheet}/bin/hypr-cheatsheet" "input-keyboard";
    dotfiles-clipboard = entry "Action: Private clipboard history" "${clipboardMenu}/bin/desktop-clipboard-menu" "edit-paste";
    dotfiles-clipboard-privacy = entry "Action: Pause / resume clipboard history" "${clipboard}/bin/desktop-clipboard toggle" "changes-prevent";
    dotfiles-clipboard-clear = entry "Action: Clear clipboard history" "${clipboard}/bin/desktop-clipboard clear" "edit-clear";
    dotfiles-lock = entry "Action: Lock screen" "${locker}/bin/desktop-lock" "system-lock-screen";
  };
}
