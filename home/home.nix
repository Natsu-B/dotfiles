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
      temurin-jdk = pkgs.javaPackages.compiler.temurin-bin.jdk-25;
      javafx-sdk = pkgs.openjfx25;
      javafx-modules = "javafx.controls,javafx.fxml,javafx.swing";
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

        # Java / JavaFX
        temurin-jdk
        javafx-sdk

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
      sessionVariables = {
        JAVA_HOME = "${temurin-jdk.home}";
        JAVAFX_SDK_HOME = "${javafx-sdk}";
        JAVAFX_HOME = "${javafx-sdk}";
        PATH_TO_FX = "${javafx-sdk}";
        JAVAFX_MODULE_PATH = "${javafx-sdk}";
        JAVAFX_MODULES = javafx-modules;
      };
      file.".local/bin/jfx-module-path" = {
        executable = true;
        text = ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          candidates=(
            "''${JAVAFX_MODULE_PATH:-}"
            "''${JAVAFX_HOME:-}"
            "''${PATH_TO_FX:-}"
            "''${JAVAFX_SDK_HOME:-}/lib"
            "''${JAVAFX_SDK_HOME:-}/modules"
            "''${JAVAFX_SDK_HOME:-}"
            "${javafx-sdk}/lib"
            "${javafx-sdk}/modules"
            "${javafx-sdk}"
          )

          for candidate in "''${candidates[@]}"; do
            [[ -n "$candidate" && -d "$candidate" ]] || continue

            if ${pkgs.findutils}/bin/find "$candidate" -maxdepth 1 \
              \( -name 'javafx.controls.jar' -o -name 'javafx.controls.jmod' -o -name 'javafx.controls' \) \
              -print -quit 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q .; then
              printf '%s\n' "$candidate"
              exit 0
            fi

            found="$(${pkgs.findutils}/bin/find "$candidate" -maxdepth 5 \
              \( -name 'javafx.controls.jar' -o -name 'javafx.controls.jmod' -o -name 'javafx.controls' \) \
              -print -quit 2>/dev/null || true)"

            if [[ -n "$found" ]]; then
              ${pkgs.coreutils}/bin/dirname "$found"
              exit 0
            fi
          done

          echo "jfx-module-path: javafx.controls was not found under JAVAFX_SDK_HOME=${javafx-sdk}" >&2
          exit 1
        '';
      };
      file.".local/bin/jfx-javac" = {
        executable = true;
        text = ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          java_home="''${JAVA_HOME:-${temurin-jdk.home}}"
          module_path="$($HOME/.local/bin/jfx-module-path)"
          modules="''${JAVAFX_MODULES:-${javafx-modules}}"

          exec "$java_home/bin/javac" \
            --module-path "$module_path" \
            --add-modules "$modules" \
            "$@"
        '';
      };
      file.".local/bin/jfx-java" = {
        executable = true;
        text = ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          java_home="''${JAVA_HOME:-${temurin-jdk.home}}"
          module_path="$($HOME/.local/bin/jfx-module-path)"
          modules="''${JAVAFX_MODULES:-${javafx-modules}}"

          exec "$java_home/bin/java" \
            --module-path "$module_path" \
            --add-modules "$modules" \
            "$@"
        '';
      };
      file.".local/bin/jfx-make" = {
        executable = true;
        text = ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          java_home="''${JAVA_HOME:-${temurin-jdk.home}}"
          module_path="$($HOME/.local/bin/jfx-module-path)"

          exec ${pkgs.gnumake}/bin/make \
            JAVABIN="$java_home/bin/" \
            JAVAFXMODULE="$module_path" \
            "$@"
        '';
      };
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
      # Load Home Manager session variables in interactive zsh.
      # Without this, variables such as JAVAFX_MODULE_PATH may not appear until a full login session.
      if [[ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]]; then
        source "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
      elif [[ -f "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh" ]]; then
        source "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
      fi

      typeset -U path PATH
      [[ -d "$HOME/.local/bin" ]] && path=("$HOME/.local/bin" $path)
      [[ -d "/usr/local/bin" ]] && path=("/usr/local/bin" $path)
      [[ -d "/usr/local/sbin" ]] && path=("/usr/local/sbin" $path)

      if [[ -x "$HOME/.local/bin/jfx-module-path" ]]; then
        export JAVAFX_MODULE_PATH="$("$HOME/.local/bin/jfx-module-path" 2>/dev/null || printf '%s' "$JAVAFX_MODULE_PATH")"
        export JAVAFX_HOME="$JAVAFX_MODULE_PATH"
        export PATH_TO_FX="$JAVAFX_MODULE_PATH"
      fi
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
