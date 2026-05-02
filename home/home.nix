# home/home.nix

{
  config,
  pkgs,
  unstable,
  master,
  lib,
  ...
}: {
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./dconf.nix
  ];

  home =
    let
      gef = pkgs.callPackage ./app/gef.nix { };
      gemini-cli = pkgs.callPackage ./app/gemini.nix { };
    in
    rec {
      username = "hotaru";
      homeDirectory = "/home/${username}";
      stateVersion = "25.11";
      # Install pkgs
      packages = [
        # Use the custom-built xremap packages
        pkgs.xremap-gnome
        pkgs.xremap-hypr

        # Development tools
        pkgs.gh
        pkgs.gcc
        pkgs.gnumake
        pkgs.bison
        pkgs.bc
        pkgs.flex
        pkgs.openssl
        pkgs.qemu
        pkgs.curl
        pkgs.bat
        pkgs.nil
        pkgs.gdb
        master.file
        gef

        # Rust toolchain
        pkgs.rustup

        # Chat
        pkgs.discord
        pkgs.slack
        pkgs.mattermost

        # Browser
        pkgs.google-chrome
        pkgs.brave

        pkgs.python3

        pkgs.nodejs
        # Gemini cli
        gemini-cli
        # Codex
        master.codex

        # PDF viewer
        pkgs.kdePackages.okular

        pkgs.kicad
        pkgs.ghidra
        pkgs.cmake
        pkgs.unzip

        # llvm-objdump
        pkgs.llvmPackages.bintools-unwrapped

        pkgs.inkscape-with-extensions
        pkgs.zoom-us
        pkgs.libreoffice
        pkgs.typst
        pkgs.tinymist

        pkgs.jdk25
        # verilog
        pkgs.gtkwave
        pkgs.iverilog

        pkgs.racket
        pkgs.davinci-resolve

        pkgs.iverilog

        pkgs.obsidian

        pkgs.libretranslate

        pkgs.bashInteractive

        pkgs.pwntools

        pkgs.openocd
        pkgs.gtkterm

        pkgs.remmina
      ];
      # Place the xremap configuration file
      file.".config/xremap/config.yml" = {
        source = ../config.yml;
      };
      # Link Hyprland configuration
      file.".config/hypr/hyprland.conf" = {
        source = ../hyprland.conf;
      };
      # Enable unfree software on command line
      file.".config/nixpkgs/config.nix" = {
        source = ../nixpkgs/config.nix;
      };
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

  # Configure Zsh and Oh My Zsh
  programs.zsh = {
    enable = true;
    initContent = lib.mkOrder 1000 ''
      typeset -U path PATH
      [[ -d "$HOME/.local/bin" ]] && path=("$HOME/.local/bin" $path)
      [[ -d "/usr/local/bin" ]] && path=("/usr/local/bin" $path)
      [[ -d "/usr/local/sbin" ]] && path=("/usr/local/sbin" $path)
    '';
  };
  #  programs.zsh.ohMyZsh = {
  #    enable = true;
  #    theme = "robbyrussell";
  #    plugins = [
  #      "git"
  #      "zsh-autosuggestions"
  #      "zsh-syntax-highlighting"
  #    ];
  #  };

  programs.home-manager.enable = true;
}
