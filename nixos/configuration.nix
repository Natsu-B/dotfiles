# /etc/nixos/configuration.nix

{
  config,
  pkgs,
  unstable,
  inputs,
  ...
}: {
  imports = [
    <nixos-hardware/lenovo/thinkpad/p14s/intel/gen5>
    ./hardware-configuration.nix
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Use the unstable package set for specific packages
  nixpkgs.overlays = [
    (final: prev: {
      unstable = import unstable {
        system = prev.system;
        config.allowUnfree = true;
      };

      # Custom xremap builds to avoid conflicts
      xremap-gnome = prev.xremap.overrideAttrs (oldAttrs: {
        pname = "xremap-gnome";
        features = [ "gnome" ];
        postInstall = ''
          mv $out/bin/xremap $out/bin/xremap-gnome
        '';
      });

      xremap-hypr = prev.xremap.overrideAttrs (oldAttrs: {
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

  # Networking
  networking.hostName = "nixos"; # Define your hostname

  # Set your time zone
  time.timeZone = "Asia/Tokyo";

  # Configure console keymap
  console.keyMap = "jp106";

  # Define a user account
  users.users.hotaru = {
    isNormalUser = true;
    extraGroups = [ "wheel" "input" ]; # Add user to wheel and input groups
    shell = pkgs.zsh;
  };

  # Enable Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Enable sound
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # Enable udev rules for xremap
  services.udev.extraRules = ''
    KERNEL=="event*", GROUP="input", MODE="0660"
    KERNEL=="uinput", GROUP="input", MODE="0660"
  '';

  # Home Manager configuration
  home-manager = {
    extraSpecialArgs = { inherit unstable; };
    users.hotaru = import ../home/home.nix;
  };

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
  ];

  # System state version
  system.stateVersion = "25.05";

  # Language settings
  i18n.inputMethod = {
    enabled = "fcitx5";
    fcitx5.addons = [pkgs.fcitx5-mozc];
  };

  fonts = {
    fonts = with pkgs; [
      noto-fonts-cjk-serift
      noto-fonts-cjk-sans
      noto-fonts-emoji
      nerdfonts
    ];
    fontDir.enable = true;
    fontconfig = {
      defaultFonts = {
        serif = ["Noto Serif CJK JP" "Noto Color Emoji"];
        sansSerif = ["Noto Sans CJK JP" "Noto Color Emoji"];
        monospace = ["JetBrainsMono Nerd Font" "Noto Color Emoji"];
        emoji = ["Noto Color Emoji"];
      };
    };
  };
}
