{ pkgs, unstable, ... }: {
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  services.xserver.enable = true;
  services.displayManager = {
    gdm.enable = true;
    defaultSession = "hyprland-uwsm";
  };
  services.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = "jp";
    variant = "";
  };

  hardware.uinput.enable = true;
  hardware.cpu.intel.npu.enable = true;
  hardware.bluetooth.enable = true;
  home-manager.backupFileExtension = "before-hyprland";

  security.polkit.enable = true;
  security.pam.services.hyprlock = { };
  services.gnome.gnome-keyring.enable = true;

  # Use the DMS package's own upstream systemd unit. It uses Type=dbus,
  # waits for org.freedesktop.Notifications, and has DMS-specific restart
  # semantics for transient startup failures. UWSM provides this target only
  # for the Hyprland session, so DMS stays out of the GNOME fallback.
  programs.dms-shell = {
    enable = true;
    package = unstable.dms-shell;
    quickshell.package = unstable.quickshell;
    systemd = {
      enable = true;
      # DMS upstream unit is After/Requisite=graphical-session.target.
      # Targeting the earlier UWSM wayland-session target creates an ordering
      # cycle, so start it from graphical-session and gate it by desktop below.
      target = "graphical-session.target";
      restartIfChanged = true;
    };
    enableCalendarEvents = false;
    enableClipboardPaste = false;
  };

  # Keep DMS out of the GNOME fallback without fighting UWSM ordering.
  systemd.user.services.dms.unitConfig.ConditionEnvironment =
    "XDG_CURRENT_DESKTOP=Hyprland";

  # This module selects Zoom's portal dependencies for the enabled desktops.
  programs.zoom-us.enable = true;

  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.hyprland = {
    default = [ "hyprland" "gtk" ];
    "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
    "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
    "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
  };
}
