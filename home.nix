{ config, pkgs, username, ... }:

{
  # Set user and home directory from flake arguments
  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "24.05";

  # Install packages
  home.packages = [
    pkgs.xremap # Install xremap package
  ];

  # Manage dotfiles
  home.file.".config/xremap/config.yml" = {
    source = ./config.yml; # Link the config file
  };

  # Manually define the systemd service file to avoid internal home-manager errors
  home.file.".config/systemd/user/xremap.service" = {
    text = ''
      [Unit]
      Description=xremap input remapper
      After=graphical-session.target

      [Service]
      ExecStart=${pkgs.xremap}/bin/xremap --config %h/.config/xremap/config.yml
      Restart=on-failure
      RestartSec=1

      [Install]
      WantedBy=graphical-session.target
    '';
  };

  # Let Home Manager manage itself.
  programs.home-manager.enable = true;
}
