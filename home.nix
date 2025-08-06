{ config, pkgs, username, ... }:

{
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "24.05";

  # 1. Install packages
  home.packages = with pkgs; [
    xremap

    # Development tools (equivalent to build-essential)
    gcc
    gnumake

    bison
    bc
    flex
    openssl
    qemu
    curl
    git

    # Rust toolchain
    cargo
    rustc

    # Custom xremap builds
    xremap-gnome
    xremap-hypr
  ];

  # 2. Place the xremap configuration file
  home.file.".config/xremap/config.yml" = {
    source = ./config.yml;
  };

  # 3. Define systemd services (without enabling them globally)
  systemd.user.services.xremap-gnome = {
    Unit = { Description = "xremap input remapper (GNOME)"; };
    Service = {
      ExecStart = "${pkgs.xremap-gnome}/bin/xremap-gnome --config %h/.config/xremap/config.yml";
      Restart = "on-failure";
    };
  };

  systemd.user.services.xremap-hypr = {
    Unit = { Description = "xremap input remapper (Hyprland)"; };
    Service = {
      ExecStart = "${pkgs.xremap-hypr}/bin/xremap-hypr --config %h/.config/xremap/config.yml";
      Restart = "on-failure";
    };
  };

  # 4. Configure DE/WM-specific autostart

  # For GNOME (and other XDG-compliant DEs), manually create a .desktop file.
  home.file.".config/autostart/xremap-gnome.desktop" = {
    text = ''
      [Desktop Entry]
      Name=xremap-gnome
      Comment=Start xremap for GNOME session
      Exec=systemctl --user start xremap-gnome.service
      Type=Application
      Terminal=false
    '';
    executable = false; # This is a config file, not a script
  };

  # For Hyprland, link the configuration file from the repo
  home.file.".config/hyprland/hyprland.conf" = {
    source = ./hyprland.conf;
  };

  programs.home-manager.enable = true;
}