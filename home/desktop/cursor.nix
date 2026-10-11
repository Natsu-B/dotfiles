{ pkgs, ... }:
{
  # Keep the cursor independent of DMS/Hyprland state. GNOME, GTK apps,
  # XWayland and native Wayland apps should all resolve the same installed
  # theme instead of falling back to an empty/invalid cursor surface.
  home.pointerCursor = {
    enable = true;
    package = pkgs.adwaita-icon-theme;
    name = "Adwaita";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  gtk.enable = true;

  dconf.settings."org/gnome/desktop/interface" = {
    cursor-theme = "Adwaita";
    cursor-size = 24;
  };
}
