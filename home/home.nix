# home/home.nix

{
  config,
  pkgs,
  unstable,
  ...
}: {
  home.username = "hotaru";
  home.homeDirectory = "/home/hotaru";
  home.stateVersion = "24.05";

  # Install user-specific packages
  home.packages = with pkgs; [
    # Use the custom-built xremap packages
    xremap-gnome
    xremap-hypr

    # Development tools
    gcc
    gnumake
    bison
    bc
    flex
    openssl
    qemu
    curl

    # Rust toolchain
    cargo
    rustc
  ];

  # Place the xremap configuration file
  home.file.".config/xremap/config.yml" = {
    source = ../config.yml;
  };

  # Define and enable systemd services for xremap
  systemd.user.services.xremap-gnome = {
    Unit = { Description = "xremap input remapper (GNOME)"; };
    Service = {
      ExecStart = "${pkgs.xremap-gnome}/bin/xremap-gnome --config %h/.config/xremap/config.yml";
      Restart = "on-failure";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

  systemd.user.services.xremap-hypr = {
    Unit = { Description = "xremap input remapper (Hyprland)"; };
    Service = {
      ExecStart = "${pkgs.xremap-hypr}/bin/xremap-hypr --config %h/.config/xremap/config.yml";
      Restart = "on-failure";
    };
    Install = { WantedBy = [ "hyprland-session.target" ]; };
  };

  # Link Hyprland configuration
  home.file.".config/hypr/hyprland.conf" = {
    source = ../hyprland.conf;
  };

  # Configure Zsh and Oh My Zsh
  programs.zsh = {
    enable = true;
  };
  programs.oh-my-zsh = {
    enable = true;
    theme = "robbyrussell";
    plugins = [
      "git"
      "zsh-autosuggestions"
      "zsh-syntax-highlighting"
    ];
  };

  programs.home-manager.enable = true;
}
