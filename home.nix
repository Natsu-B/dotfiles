{ config, pkgs, username, ... }:

{
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "24.05";

  # 1. Install the package
  home.packages = [ pkgs.xremap ];

  # 2. Place the configuration file
  home.file.".config/xremap/config.yml" = {
    source = ./config.yml;
  };

  # 3. Define and enable the systemd service
  systemd.user.services.xremap = {
    Unit = {
      Description = "xremap input remapper";
      After = [ "graphical-session.target" ];
    };
    Service = {
      # Use an absolute path to the binary from the nix store
      ExecStart = "${pkgs.xremap}/bin/xremap --config %h/.config/xremap/config.yml";
      Restart = "on-failure";
      RestartSec = 1;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  programs.home-manager.enable = true;
}
