# /etc/nixos/configuration.nix

{
  config,
  pkgs,
  unstable,
  master,
  inputs,
  self,
  lib,
  ...
}: {
  imports = [
    ./codex-usb.nix
    ./desktop.nix
  ];

  # disable nvidia driver
  hardware.nvidia.modesetting.enable = lib.mkForce false;
  services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];

  # Optimize nix store
  nix = {
    settings = {
      # auto-optimize-store = true;
      experimental-features = ["nix-command" "flakes"];
      # extra-sandbox-paths = [ "/mnt/data" ];
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
          system = prev.stdenv.hostPlatform.system;
          config.allowUnfree = true;
        };
        masterPkgs = import inputs.nixpkgs-master {
          system = prev.stdenv.hostPlatform.system;
          config.allowUnfree = true;
        };
      in {
        unstable = unstablePkgs;
        master = masterPkgs;
        vscode = masterPkgs.vscode;

        jdk25 = unstablePkgs.jdk25;
      })
  ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use Linux 7.1+ for the new in-kernel NTFS driver.
  # nixpkgs 25.11 latest is currently 7.0.x, so use nixpkgs-master here.
  boot.kernelPackages = master.linuxPackages_latest;
  boot.supportedFilesystems = [ "ntfs" ];
  boot.kernelModules = [ "e1000e" ];

  boot.binfmt.emulatedSystems = [ "aarch64-linux" "riscv64-linux" ];

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone
  time.timeZone = "Asia/Tokyo";

  # Configure console keymap
  console.keyMap = "jp106";

  # Define a user account
  users.users.hotaru = {
    uid = 1000;
    isNormalUser = true;
    extraGroups = [ "wheel" "input" "networkmanager" "libvirtd" "serial" "dialout" "plugdev" ]; # Add user to wheel and input groups
    shell = pkgs.zsh;
  };

  users.groups.plugdev = {
    members = [ "hotaru" ];
  };

  # fileSystems."/mnt/data" = {
  #   device = "/dev/disk/by-label/data";
  #   fsType = "ntfs";
  #   options = [
  #     "rw"
  #     "nofail"
  #     "noauto"
  #     "x-systemd.automount"
  #     "x-systemd.idle-timeout=60"
  #     "uid=1000"
  #     "gid=100"
  #     "fmask=113"
  #     "dmask=002"
  #     "exec"
  #     "windows_names"
  #     "sys_immutable"
  #   ];
  # };

  # Enable sound
  services.pulseaudio.enable = false; # Use pipwire as a sound module
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;
    pulse.enable = true;
  };

  security.pam.services.login.fprintAuth = false;
  security.pam.services.gdm-fingerprint = lib.mkIf (config.services.fprintd.enable) {
    text = ''
      auth       required                    pam_shells.so
      auth       requisite                   pam_nologin.so
      auth       requisite                   pam_faillock.so      preauth
      auth       required                    ${pkgs.fprintd}/lib/security/pam_fprintd.so
      auth       optional                    pam_permit.so
      auth       required                    pam_env.so
      auth       [success=ok default=1]      ${pkgs.gdm}/lib/security/pam_gdm.so
      auth       optional                    ${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so

      account    include                     login

      password   required                    pam_deny.so

      session    include                     login
      session    optional                    ${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so auto_start
    '';
  };

  # Enable zsh
  programs.zsh.enable = true;

  # Enable Docker with rootless
  virtualisation = {
    docker = {
      enable = false;
      rootless = {
        enable = true;
        setSocketVariable = true; # sets $DOCKER_HOST
        package = pkgs.unstable.docker;
      };
    };
  };

  # Enable udev rules for xremap
  services.udev.extraRules = ''
    KERNEL=="event*", GROUP="input", MODE="0660"
    KERNEL=="uinput", GROUP="input", MODE="0660"
    # Allow probe-rs compatible debug probes for users in plugdev
    SUBSYSTEM=="usb", ATTR{idVendor}=="2e8a", ATTR{idProduct}=="000c", MODE="0660", GROUP="plugdev", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0d28", MODE="0660", GROUP="plugdev", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTR{idVendor}=="1fc9", MODE="0660", GROUP="plugdev", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTR{idVendor}=="1366", MODE="0660", GROUP="plugdev", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0483", MODE="0660", GROUP="plugdev", TAG+="uaccess"
    # Allow ESP32-S3 built-in USB-JTAG/serial for probe-rs / espflash
    SUBSYSTEM=="usb", ATTR{idVendor}=="303a", ATTR{idProduct}=="1001", MODE="0660", GROUP="plugdev", TAG+="uaccess"
  '';

  # Home Manager configuration
  home-manager = {
    extraSpecialArgs = { inherit unstable pkgs master; };
    users.hotaru = import ../home/home.nix;
  };

  # Enable Flatpak
  services.flatpak.enable = true;
  xdg.portal.enable = true;

  # Enable finger print
  services.fprintd.enable = true;
  services.fwupd.enable = true;
  services.fprintd.tod.enable = false;

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    vscode
    dconf
    gnome-extension-manager
    gnome-tweaks
    gnomeExtensions.runcat
    gnomeExtensions.kimpanel
    libfprint
    qemu
    tcsh
    tailscale
    man-pages
    man-pages-posix
  ];

  services.tailscale.enable = true;

  programs.git = {
    enable = true;
    config = {
      user = {
        name = "Natsu-B";
        email = "natsu.minatomirai@gmail.com";
      };
      init.defaultBranch = "main";
      core.fileMode = false;
    };
  };

  programs.appimage = {
    enable = true;
    binfmt = true;

    package = pkgs.appimage-run.override {
      extraPkgs = pkgs: with pkgs; [
        webkitgtk_4_1
        glib
        glib-networking
        gst_all_1.gst-plugins-base
        gst_all_1.gst-plugins-good
        gst_all_1.gst-plugins-bad
        cacert
        curl
      ];
    };
  };

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    zlib
    openssl
  ];

  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = ["hotaru"];
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  # System state version
  system.stateVersion = "24.05";

  # Language settings
  # i18n.defaultLocale = "ja_JP.UTF-8";
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
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
      noto-fonts-color-emoji
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
