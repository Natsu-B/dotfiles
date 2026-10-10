{
  config,
  pkgs,
  unstable,
  lib,
  ...
}:
let
  target = "wayland-session@hyprland.desktop.target";
  tools = import ./packages.nix { inherit pkgs unstable; };
  inherit (tools)
    dms
    launcher
    windowSwitcher
    wallpaper
    keyboard
    clipboard
    clipboardMenu
    locker
    cheatsheet
    ;

  defaults = pkgs.writeText "dotfiles-dms-defaults.json" (builtins.toJSON {
    settings = {
      fontFamily = "Noto Sans CJK JP";
      monoFontFamily = "JetBrainsMono Nerd Font";
      cornerRadius = 14;
      hyprlandResizeOnBorder = true;
      showWeather = false;
      showClipboard = false;
      clipboardClickToPaste = false;
      clipboardEnterToPaste = false;
      # No shell-side fade tail after closing blurred modals. Keep bar/popout motion.
      syncComponentAnimationSpeeds = false;
      modalAnimationSpeed = 0;
      runningAppsCurrentWorkspace = false;
      runningAppsCurrentMonitor = false;
      runningAppsGroupByApp = true;
      runningAppsCompactMode = true;
      barConfigs = [ {
        id = "default";
        name = "Main Bar";
        enabled = true;
        position = 0;
        screenPreferences = [ "all" ];
        showOnLastDisplay = true;
        leftWidgets = [ "launcherButton" "workspaceSwitcher" "runningApps" ];
        centerWidgets = [ "music" "clock" "weather" ];
        rightWidgets = [ "systemTray" "clipboard" "cpuUsage" "memUsage" "notificationButton" "battery" "controlCenterButton" ];
      } ];

      # DMS's idle timers are adjustable in Settings > Power & Sleep.
      acLockTimeout = 300;
      batteryLockTimeout = 300;
      acMonitorTimeout = 600;
      batteryMonitorTimeout = 600;
      acSuspendTimeout = 0;
      batterySuspendTimeout = 0;
      # The idle action explicitly saves RAM to disk; idle timeouts stay opt-in.
      acSuspendBehavior = 1;
      batterySuspendBehavior = 1;
      fadeToLockEnabled = false;

      # Use DMS's existing UPower events; no additional polling daemon.
      # Quickshell profile strings: 0 = power-saver, 1 = balanced, 2 = performance.
      acProfileName = "1";
      batteryProfileName = "0";
      batteryAutoPowerSaver = true;
      lowerDisplayRefreshRateOnBattery = true;
      batteryPostLockMonitorTimeout = 30;

      # hypridle holds the suspend inhibitor until hyprlock is ready.
      lockBeforeSuspend = false;
      loginctlLockIntegration = true;

      # Do not let a shell theme overwrite managed Fcitx/GTK/app settings.
      runDmsMatugenTemplates = false;
    };
    policy = {
      customPowerActionLock = "${locker}/bin/desktop-lock";
      customPowerActionLogout = "${pkgs.uwsm}/bin/uwsm stop";
      launchPrefix = "${pkgs.uwsm}/bin/uwsm app --";
    };
    session = {
      wallpaperPath = "${config.home.homeDirectory}/.local/share/backgrounds/nix-nineish-mocha-alt.png";
      isLightMode = false;
      terminalOverride = "kitty";
    };
    plugins.dotfilesAppShortcuts.enabled = true;
  });

  configure = pkgs.writeShellApplication {
    name = "desktop-dms-config";
    runtimeInputs = [ pkgs.python3 ];
    text = ''exec python3 ${./seed_dms.py} ${defaults}'';
  };

  commands = {
    terminal = "${pkgs.uwsm}/bin/uwsm app -- ${pkgs.kitty}/bin/kitty";
    fileManager = "${pkgs.uwsm}/bin/uwsm app -- ${pkgs.nautilus}/bin/nautilus";
    launcher = "${launcher}/bin/desktop-launcher";
    windowSwitcher = "${windowSwitcher}/bin/desktop-window-switcher";
    dms = "${dms}/bin/dms";
    cheatsheet = "${dms}/bin/dms ipc call keybinds toggle hyprland";
    keyboard = "${keyboard}/bin/keyboard-profile toggle";
    clipboard = "${clipboardMenu}/bin/desktop-clipboard-menu";
    clipboardPrivacy = "${clipboard}/bin/desktop-clipboard toggle";
    clipboardClear = "${clipboard}/bin/desktop-clipboard clear";
    lock = "${locker}/bin/desktop-lock";
    logout = "${pkgs.uwsm}/bin/uwsm stop";
    restartShell = "${pkgs.systemd}/bin/systemctl --user restart dms.service";
  };

  luaString = value: builtins.toJSON value;

  entry =
    name: exec: icon:
    {
      inherit name exec icon;
      terminal = false;
      # Keep a single registered main category. Multiple main categories make
      # desktop-file-utils warn that the entry may be duplicated in menus.
      categories = [ "Utility" ];

      # Keep these actions visible in DMS, but not in the GNOME fallback.
      # Do not use OnlyShowIn=Hyprland (unregistered) or X-Hyprland (no match).
      settings.NotShowIn = "GNOME;";
    };
in
{
  home.packages = [
    launcher
    windowSwitcher
    configure
    pkgs.brightnessctl
  ];

  home.file.".local/share/backgrounds/nix-nineish-mocha-alt.png".source = wallpaper;

  home.activation.seedDms = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${configure}/bin/desktop-dms-config
  '';

  xdg.configFile = {
    "DankMaterialShell/plugins/dotfilesAppShortcuts/plugin.json".source = ./dms-app-shortcuts/plugin.json;
    "DankMaterialShell/plugins/dotfilesAppShortcuts/AppShortcuts.qml".source = ./dms-app-shortcuts/AppShortcuts.qml;
    "DankMaterialShell/plugins/dotfilesAppShortcuts/AppIndex.js".source = ./dms-app-shortcuts/AppIndex.js;
    "hypr/hyprland.lua".source = ./hypr/hyprland.lua;
    "hypr/input.lua".source = ./hypr/input.lua;
    "hypr/appearance.lua".source = ./hypr/appearance.lua;
    "hypr/binds.lua".source = ./hypr/binds.lua;

    "hypr/commands.lua".text = ''
      -- Executable paths generated by Home Manager; no shell startup PATH needed.
      return {
        ${lib.concatStringsSep "\n  " (lib.mapAttrsToList (name: value: ''${name} = ${luaString value},'') commands)}
      }
    '';

    # Only this security policy is read-only. Normal settings remain writable.
    # DMS's built-in persistent history must not duplicate the private recorder.
    "DankMaterialShell/clsettings.json".text = builtins.toJSON {
      disabled = true;
      maxHistory = 100;
      maxEntrySize = 65536;
      maxPinned = 0;
    };
  };

  xdg.desktopEntries = {
    dotfiles-settings = entry "Settings: Desktop" "${dms}/bin/dms ipc call settings focusOrToggle" "preferences-system";
    dotfiles-displays = entry "Settings: Displays and mirroring" "${dms}/bin/dms ipc call settings focusOrToggleWith displays" "preferences-desktop-display";
    dotfiles-shortcuts = entry "Action: Hyprland shortcuts" "${dms}/bin/dms ipc call keybinds toggle hyprland" "input-keyboard";
    dotfiles-dms-restart = entry "Action: Restart desktop shell" commands.restartShell "view-refresh";
    dotfiles-zoom-web = entry "Zoom Web" "${pkgs.xdg-utils}/bin/xdg-open https://app.zoom.us/wc" "web-browser";
  };
}
