{ config, lib, pkgs, ... }:

let
  # Group 9 is isolated from host-critical devices.  Keep all functions in
  # the group together so VFIO never partially owns an IOMMU group.
  passthroughPciDevices = [
    "0000:00:0d.0" # Meteor Lake-P Thunderbolt 4 USB controller (xHCI)
    "0000:00:0d.2" # Meteor Lake-P Thunderbolt 4 NHI #0
    "0000:00:0d.3" # Meteor Lake-P Thunderbolt 4 NHI #1
  ];

  unsupportedUsbControllers = [
    "0000:00:14.0" # Group 10 also contains host SRAM telemetry 00:14.2
  ];

  hostUid = config.users.users.hotaru.uid;
  guestSshPublicKey = builtins.readFile ./codex-usb-authorized-key.pub;
  rootHelper = pkgs.writeShellApplication {
    name = "codex-usb-root";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gawk
      gnugrep
      pciutils
      systemd
      util-linux
      usbutils
    ];
    text = ''
      set -euo pipefail

      controllers=(${lib.escapeShellArgs passthroughPciDevices})
      vm_service="microvm@codex-usb.service"

      is_controller() {
        local candidate=$1
        local controller
        for controller in "''${controllers[@]}"; do
          [[ "$candidate" == "$controller" ]] && return 0
        done
        return 1
      }

      check_iommu_isolation() {
        local controller group member
        for controller in "''${controllers[@]}"; do
          group=$(basename "$(readlink "/sys/bus/pci/devices/$controller/iommu_group")")
          [[ -n "$group" && -d "/sys/kernel/iommu_groups/$group/devices" ]] || {
            echo "codex-usb: $controller has no IOMMU group" >&2
            return 1
          }
          for member in /sys/kernel/iommu_groups/"$group"/devices/*; do
            member=$(basename "$member")
            is_controller "$member" || {
              echo "codex-usb: refusing passthrough; IOMMU Group $group also contains $member" >&2
              lspci -Dnnk -s "$member" >&2 || true
              return 1
            }
          done
        done
      }

      check_host_storage() {
        local mount source block device_path
        for mount in / /boot /nix/store; do
          source=$(findmnt -no SOURCE "$mount" 2>/dev/null | sed 's/\[.*//')
          case "$source" in
            /dev/*)
              block=$(basename "$source")
              device_path=$(readlink -f "/sys/class/block/$block/device" 2>/dev/null || true)
              if [[ "$device_path" == *"/usb"* ]]; then
                echo "codex-usb: refusing passthrough; $mount is on USB storage ($source)" >&2
                return 1
              fi
              ;;
          esac
        done
      }

      check_network() {
        local interface device_path
        for interface in /sys/class/net/*; do
          device_path=$(readlink -f "$interface/device" 2>/dev/null || true)
          if [[ "$device_path" == *"/usb"* ]]; then
            echo "codex-usb: refusing passthrough; network interface $(basename "$interface") is USB-backed" >&2
            return 1
          fi
        done
      }

      check_disk_space() {
        local available_kib
        available_kib=$(df --output=avail -k /var/lib | tail -n 1 | tr -d ' ')
        if (( available_kib < 47185920 )); then
          echo "codex-usb: refusing start; at least 45 GiB is needed for guest volumes and build headroom" >&2
          return 1
        fi
      }

      preflight() {
        check_iommu_isolation
        check_host_storage
        check_network
        check_disk_space
        echo "codex-usb: preflight passed"
      }

      release_controllers() {
        local controller
        for controller in "''${controllers[@]}"; do
          if [[ -e "/sys/bus/pci/devices/$controller/driver/unbind" ]]; then
            printf '%s' "$controller" > "/sys/bus/pci/devices/$controller/driver/unbind" || true
          fi
          printf '%s' "" > "/sys/bus/pci/devices/$controller/driver_override"
          printf '%s' "$controller" > /sys/bus/pci/drivers_probe
        done
      }

      status() {
        systemctl --no-pager --full status "$vm_service" || true
        for controller in "''${controllers[@]}"; do
          printf '\n%s: ' "$controller"
          printf 'driver=%s iommu-group=%s\n' \
            "$(basename "$(readlink "/sys/bus/pci/devices/$controller/driver" 2>/dev/null || echo unbound)")" \
            "$(basename "$(readlink "/sys/bus/pci/devices/$controller/iommu_group" 2>/dev/null || echo none)")"
          lspci -Dnnk -s "$controller" || true
        done
      }

      diagnose() {
        uname -a
        cat /proc/cmdline
        find /sys/kernel/iommu_groups -type l -printf '%p -> %l\n' 2>/dev/null || true
        lspci -Dnnk || true
        lsusb || true
        status
        journalctl --no-pager -u "$vm_service" -u "microvm-pci-devices@codex-usb.service" -n 100 || true
      }

      case ''${1:-} in
        preflight) preflight ;;
        start) preflight; systemctl start "$vm_service" ;;
        stop) systemctl stop "$vm_service" || true; release_controllers ;;
        status) status ;;
        diagnose) diagnose ;;
        *) echo "usage: codex-usb-root {preflight|start|stop|status|diagnose}" >&2; exit 2 ;;
      esac
    '';
  };
in
{
  imports = [ ];

  boot.kernelParams = [ "intel_iommu=on" "iommu=pt" ];
  boot.initrd.kernelModules = [ "vfio" "vfio_pci" "vfio_iommu_type1" ];

  environment.systemPackages = with pkgs; [
    pciutils
    usbutils
    rootHelper
  ];

  environment.etc."codex-usb/pci-devices".text = lib.concatStringsSep "\n" passthroughPciDevices + "\n";
  environment.etc."codex-usb/unsupported-controllers".text = lib.concatStringsSep "\n" unsupportedUsbControllers + "\n";

  systemd.tmpfiles.settings."20-codex-usb" = {
    "/var/lib/codex-usb".d = {
      user = "root";
      group = "codex-usb";
      mode = "0750";
    };
    "/var/lib/codex-usb/workspace".d = {
      user = "hotaru";
      group = "codex-usb";
      mode = "0770";
    };
  };
  systemd.tmpfiles.rules = [
    "z /var/lib/codex-usb/workspace 0770 hotaru codex-usb -"
  ];

  users.groups.codex-usb.members = [ "hotaru" ];

  security.sudo.extraRules = [
    {
      users = [ "hotaru" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/codex-usb-root";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  microvm.autostart = [ ];
  microvm.vms.codex-usb = {
    autostart = false;
    specialArgs = { inherit hostUid guestSshPublicKey; };
    config = { hostUid, guestSshPublicKey, pkgs, lib, ... }: {
      system.stateVersion = "25.11";
      networking.hostName = "codex-usb";
      networking.useDHCP = true;

      services.openssh.enable = true;
      services.openssh.settings.PermitRootLogin = "no";
      users.users.codex = {
        uid = hostUid;
        isNormalUser = true;
        home = "/home/codex";
        shell = pkgs.bashInteractive;
        extraGroups = [ "wheel" "dialout" ];
        openssh.authorizedKeys.keys = [ guestSshPublicKey ];
      };
      security.sudo.wheelNeedsPassword = false;
      systemd.tmpfiles.rules = [
        "z /home/codex 0700 codex users -"
      ];
      systemd.services.codex-usb-permissions = {
        description = "Fix Codex USB guest volume ownership";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        unitConfig.RequiresMountsFor = "/home/codex /workspace";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.coreutils}/bin/chown codex:users /home/codex /workspace
          ${pkgs.coreutils}/bin/chmod 0700 /home/codex
          ${pkgs.coreutils}/bin/chmod 0770 /workspace
        '';
      };

      nix.settings = {
        experimental-features = [ "nix-command" "flakes" ];
        max-jobs = "auto";
      };

      environment.systemPackages = with pkgs; [
        git curl wget jq ripgrep fd
        gcc clang gnumake cmake ninja pkg-config
        python3 usbutils pciutils
        dfu-util openocd avrdude
        codex
        probe-rs-tools picotool esptool
        minicom screen
        (writeShellScriptBin "codex-usb-agent" ''
          exec ${lib.getExe pkgs.codex} --dangerously-bypass-approvals-and-sandbox "$@"
        '')
      ];

      microvm = {
        hypervisor = "qemu";
        qemu.machine = "q35";
        vcpu = 10;
        mem = 12288;
        interfaces = [
          {
            type = "user";
            id = "qemu";
            mac = "02:00:00:00:00:01";
          }
        ];
        devices = map (path: { bus = "pci"; inherit path; }) passthroughPciDevices;
        shares = [
          {
            proto = "virtiofs";
            tag = "workspace";
            source = "/var/lib/codex-usb/workspace";
            mountPoint = "/workspace";
            readOnly = false;
            securityModel = "none";
          }
        ];
        writableStoreOverlay = "/nix/.rw-store";
        registerClosure = false;
        volumes = [
          {
            image = "codex-home.img";
            mountPoint = "/home/codex";
            size = 8192;
          }
          {
            image = "nix-store-overlay.img";
            mountPoint = "/nix/.rw-store";
            size = 32768;
          }
        ];
        vsock = {
          cid = 3;
          ssh.enable = true;
        };
      };
    };
  };
}
