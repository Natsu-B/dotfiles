{ config, pkgs, username, ... }:

{
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "24.05";

  home.packages = [ pkgs.xremap ];

  # Let home-manager manage the service and config file placement
  programs.xremap = {
    enable = true;
    configFile = ./config.yml;
  };

  programs.home-manager.enable = true;
}