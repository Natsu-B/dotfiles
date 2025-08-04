{ config, pkgs, username, ... }:

{
  # Set user and home directory from flake arguments
  home.username = username;
  home.homeDirectory = "/home/${username}";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  home.stateVersion = "24.05";

  # The home.packages option allows you to install packages into your
  # environment.
  home.packages = [
    # pkgs.vscode
  ];

  # Let Home Manager manage itself.
  programs.home-manager.enable = true;

  # Enable xremap
  programs.xremap = {
    enable = true;
    # Load configuration from config.yaml
    configFile = ./config.yaml;
  };
}
