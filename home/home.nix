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
    ./desktop
  ];

  home =
    let
      gef = pkgs.callPackage ./app/gef.nix { };
      gemini-cli = pkgs.callPackage ./app/gemini.nix { };
      codex-desktop = pkgs.callPackage ./app/codex-desktop.nix { };
      temurin-jdk = pkgs.javaPackages.compiler.temurin-bin.jdk-25;
      javafx-sdk = pkgs.openjfx25;
      javafx-modules = "javafx.controls,javafx.fxml,javafx.swing";
      codexUsb = pkgs.writeShellApplication {
        name = "codex-usb";
        runtimeInputs = with pkgs; [
          coreutils
          gnugrep
          openssh
          pciutils
          sudo
          systemd
          usbutils
          util-linux
        ];
        text = ''
          set -euo pipefail

          root_helper=/run/current-system/sw/bin/codex-usb-root
          ssh_target=codex@vsock/3
          if [[ "$EUID" -eq 0 && -n "''${SUDO_USER:-}" ]]; then
            ssh_command=(sudo -u "$SUDO_USER" -H ssh)
          else
            ssh_command=(ssh)
          fi
          ssh_opts=(
            -o IdentitiesOnly=yes
            -o BatchMode=yes
            -o StrictHostKeyChecking=no
            -o UserKnownHostsFile=/dev/null
            -o ConnectTimeout=2
          )

          wait_for_guest() {
            local attempt=0
            while (( attempt < 90 )); do
              attempt=$((attempt + 1))
              if "''${ssh_command[@]}" "''${ssh_opts[@]}" "$ssh_target" true >/dev/null 2>&1; then
                return 0
              fi
              sleep 1
            done
            echo "codex-usb: guest SSH/VSOCK did not become ready within 90 seconds" >&2
            sudo "$root_helper" status || true
            return 1
          }

          ensure_started() {
            if ! systemctl is-active --quiet microvm@codex-usb.service; then
              sudo "$root_helper" start
            fi
            wait_for_guest
          }

          check_rebound() {
            local controller driver
            for controller in $(< /etc/codex-usb/pci-devices); do
              driver=$(basename "$(readlink "/sys/bus/pci/devices/$controller/driver" 2>/dev/null || echo unbound)")
              if [[ "$driver" == "vfio-pci" || "$driver" == "unbound" ]]; then
                echo "codex-usb: $controller did not rebind to a host driver; reboot may be required" >&2
                return 1
              fi
              printf '%s: %s\n' "$controller" "$driver"
            done
          }

          run_agent() {
            local remote_args="" arg
            for arg in "$@"; do
              printf -v remote_args '%s %q' "$remote_args" "$arg"
            done
            exec "''${ssh_command[@]}" -tt "''${ssh_opts[@]}" "$ssh_target" \
              "cd /workspace && exec codex-usb-agent$remote_args"
          }

          command_name=$(basename "$0")
          case "$command_name" in
            codex-usb-start)
              sudo "$root_helper" start
              wait_for_guest
              sudo "$root_helper" status
              ;;
            codex-usb-stop)
              sudo "$root_helper" stop
              sleep 1
              check_rebound
              ;;
            codex-usb-shell)
              wait_for_guest
              exec "''${ssh_command[@]}" -tt "''${ssh_opts[@]}" "$ssh_target" 'cd /workspace && exec bash -l'
              ;;
            codex-usb-status)
              sudo "$root_helper" status
              if "''${ssh_command[@]}" "''${ssh_opts[@]}" "$ssh_target" true >/dev/null 2>&1; then
                echo "guest: reachable over VSOCK"
              else
                echo "guest: not reachable over VSOCK"
              fi
              ;;
            codex-usb-diagnose)
              sudo "$root_helper" diagnose
              ;;
            codex-usb)
              ensure_started
              run_agent "$@"
              ;;
            *)
              echo "unknown command: $command_name" >&2
              exit 2
              ;;
          esac
        '';
      };
    in
    rec {
      username = "hotaru";
      homeDirectory = "/home/${username}";
      stateVersion = "25.11";
      # Install pkgs
      packages = [
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
        codex-desktop
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

        # PDF viewer
        pkgs.kdePackages.okular

        pkgs.kicad
        pkgs.ghidra
        pkgs.cmake
        pkgs.unzip

        # llvm-objdump
        pkgs.llvmPackages.bintools-unwrapped

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

        pkgs.obsidian

        pkgs.libretranslate

        pkgs.bashInteractive

        pkgs.pwntools

        pkgs.openocd
        pkgs.gtkterm

        pkgs.remmina
        unstable.anki

        pkgs.tmux
        codexUsb
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
      # Enable unfree software on command line
      file.".config/nixpkgs/config.nix" = {
        source = ../nixpkgs/config.nix;
      };
      file.".local/bin/codex-usb-start".source = "${codexUsb}/bin/codex-usb";
      file.".local/bin/codex-usb-stop".source = "${codexUsb}/bin/codex-usb";
      file.".local/bin/codex-usb-shell".source = "${codexUsb}/bin/codex-usb";
      file.".local/bin/codex-usb-status".source = "${codexUsb}/bin/codex-usb";
      file.".local/bin/codex-usb-diagnose".source = "${codexUsb}/bin/codex-usb";
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
