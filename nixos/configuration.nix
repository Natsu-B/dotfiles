# /etc/nixos/configuration.nix

{
  config,
  pkgs,
  unstable,
  inputs,
  self,
  lib,
  ...
}: {
  imports = [
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p14s-intel-gen5
    ./hardware-configuration.nix
  ];

  # disable nvidia driver
  hardware.nvidia.modesetting.enable = lib.mkForce false;
  services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];

  # Optimize nix store
  nix = {
    settings = {
      # auto-optimize-store = true;
      experimental-features = ["nix-command" "flakes"];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Use the unstable package set for specific packages
  nixpkgs.overlays = [
    (final: prev:
      let
        unstablePkgs = import inputs.nixpkgs-unstable {
          system = prev.system;
          config.allowUnfree = true;
        };
      in {
        unstable = unstablePkgs;

        # Custom xremap builds to avoid conflicts
        xremap-gnome = unstablePkgs.xremap.overrideAttrs (oldAttrs: {
          pname = "xremap-gnome";
          features = [ "gnome" ];
          postInstall = ''
            mv $out/bin/xremap $out/bin/xremap-gnome
          '';
        });

        xremap-hypr = unstablePkgs.xremap.overrideAttrs (oldAttrs: {
          pname = "xremap-hypr";
          features = [ "hypr" ];
          postInstall = ''
            mv $out/bin/xremap $out/bin/xremap-hypr
          '';
        });
      })
  ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use stable kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Networking
  networking.hostName = "nixos"; # Define your hostname

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone
  time.timeZone = "Asia/Tokyo";

  # Configure console keymap
  console.keyMap = "jp106";

  # Define a user account
  users.users.hotaru = {
    isNormalUser = true;
    extraGroups = [ "wheel" "input" "networkmanager" ]; # Add user to wheel and input groups
    shell = pkgs.zsh;
  };

  # Enable Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Enable GNOME
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Register the custom XKB layout
  services.xserver.xkb.extraLayouts = {
    custom = {
      description = "Custom Programmer Dvorak";
      languages = [ "eng" ];
      symbolsFile = ./custom_dvorak.xkb;
    };
  };

  # Enable sound
  hardware.pulseaudio.enable = false; # Use pipwire as a sound module
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;
    pulse.enable = true;
  };

  # Enable zsh
  programs.zsh.enable = true;

  # Enable Docker with rootless
  virtualisation = {
    docker = {
      enable = true;
      rootless = {
        enable = true;
        setSocketVariable = true; # sets $DOCKER_HOST
      };
    };
  };

  # Enable udev rules for xremap
  services.udev.extraRules = ''
    KERNEL=="event*", GROUP="input", MODE="0660"
    KERNEL=="uinput", GROUP="input", MODE="0660"
  '';

  # Home Manager configuration
  home-manager = {
    extraSpecialArgs = { inherit unstable pkgs; };
    users.hotaru = import ../home/home.nix;
  };

  # Enable Flatpak
  services.flatpak.enable = true;
  xdg.portal.enable = true;

  # Enable finger print
  services.fprintd.enable = true;
  services.fprintd.tod.enable = true;
  services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    vscode
    dconf
  ];

  programs.git = {
    enable = true;
    config = {
      user = {
        name = "Natsu-B";
        email = "natsu.minatomirai@gmail.com";
      };
      init.defaultBranch = "main";
    };
  };

  # System state version
  system.stateVersion = "24.05";

  # Language settings
  i18n.defaultLocale = "ja_JP.UTF-8";
  i18n.inputMethod = {
    enabled = "fcitx5";
    fcitx5.addons = [
      pkgs.fcitx5-mozc
      pkgs.fcitx5-gtk
    ];
  };

  # Set environment variables for input methods
  environment.variables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
  };

  # Enable Steam
  programs.steam = {
    enable = true;
  };

  fonts = {
    packages = with pkgs; [
      noto-fonts-cjk-serif
      noto-fonts-cjk-sans
      noto-fonts-emoji
      nerd-fonts.noto
      nerd-fonts.jetbrains-mono
      nerd-fonts.fira-code
      nerd-fonts.fantasque-sans-mono
      migu
    ];
    fontDir.enable = true;
    fontconfig = {
      defaultFonts = {
        serif = ["Noto Serif CJK JP" "Noto Color Emoji"];
        sansSerif = ["Noto Sans CJK JP" "Noto Color Emoji"];
        monospace = ["JetBrainsMono Nerd Font" "Noto Color Emoji"];
        emoji = ["Noto Color Emoji"];
      };
           localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          <description>Change default fonts for Steam client</description>
          <match>
            <test name="prgname">
              <string>steamwebhelper</string>
            </test>
            <test name="family" qual="any">
              <string>sans-serif</string>
            </test>
            <edit mode="prepend" name="family">
              <string>Migu 1P</string>
            </edit>
          </match>
        </fontconfig>
      '';
    };
  };
}
