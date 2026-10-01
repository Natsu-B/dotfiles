{ pkgs, ... }: {
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

  # Both desktop environments use the same base. Dvorak lives only in xremap.
  services.xserver.xkb = { layout = "jp"; variant = ""; };
  hardware.uinput.enable = true;
  home-manager.backupFileExtension = "before-hyprland";
  security.polkit.enable = true;
  security.pam.services.hyprlock = {};
  services.gnome.gnome-keyring.enable = true;

  # Hyprland's module adds its portal; GNOME's module keeps its own portal.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.Hyprland = {
    default = [ "hyprland" "gtk" ];
    "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
  };
}
