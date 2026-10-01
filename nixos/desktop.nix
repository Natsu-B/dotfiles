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
  services.xserver.xkb = { layout = "jp"; variant = ""; };
  hardware.uinput.enable = true;
  hardware.bluetooth.enable = true;
  home-manager.backupFileExtension = "before-hyprland";
  security.polkit.enable = true;
  security.pam.services.hyprlock = {};
  services.gnome.gnome-keyring.enable = true;

  # Use the already locked DMS 1.6.2 and matching Qt/Quickshell package set.
  # Home Manager starts it only inside the UWSM Hyprland session.
  programs.dms-shell = {
    enable = true;
    package = unstable.dms-shell;
    quickshell.package = unstable.quickshell;
    systemd.enable = false;
    enableCalendarEvents = false;
    enableClipboardPaste = false;
  };

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
