# Codex USB firmware MicroVM

> **注意:** `codex-usb-start` は Group 9 の USB/Thunderbolt controller をホストから一時的に取り外します。接続中の USB keyboard、mouse、Bluetooth、camera、storage などは利用できなくなる可能性があります。

## Architecture

The host `nixos` keeps the only host-writable share at `/var/lib/codex-usb/workspace`, mounted in the guest as `/workspace` through virtiofs. The guest has its own read-only Nix store image plus a persistent writable overlay and a separate persistent `/home/codex` volume. No host home, `/nix/store`, `/dev`, sockets, or agent credentials are shared.

The guest is `codex-usb`, QEMU/KVM, 10 vCPUs, 12 GiB RAM, QEMU user networking, and VSOCK CID 3. `codex-usb-agent` runs Codex with `--dangerously-bypass-approvals-and-sandbox`; the VM boundary is the trust boundary.

## USB controller PCI addresses

Passthrough is the complete IOMMU Group 9:

| PCI BDF | Host device | IOMMU group |
| --- | --- | --- |
| `0000:00:0d.0` | Meteor Lake-P Thunderbolt 4 USB controller (xHCI) | 9 |
| `0000:00:0d.2` | Meteor Lake-P Thunderbolt 4 NHI #0 | 9 |
| `0000:00:0d.3` | Meteor Lake-P Thunderbolt 4 NHI #1 | 9 |

`0000:00:14.0` is not passed: Group 10 also contains host-required `0000:00:14.2` SRAM telemetry. ACS override is intentionally not enabled.

The host root, `/boot`, and `/nix/store` are on NVMe (`/dev/nvme0n1`), and host networking is PCI Ethernet/Wi-Fi rather than USB networking.

## Start

Ensure at least 45 GiB is free for the declared guest volumes (8 GiB home + 32 GiB Nix overlay) and build headroom, then:

```bash
codex-usb-start
```

The VM is deliberately not autostarted.
Run this as the normal host user; `sudo` is not required. If invoked through `sudo`, the wrapper still runs VSOCK SSH as the original user and never falls back to password authentication.

## Enter shell

```bash
codex-usb-shell
```

This uses the host user's existing `~/.ssh/id_ed25519` key's public half and VSOCK; no private key is copied into the guest.

## Run Codex

```bash
codex-usb
codex-usb "inspect the firmware project"
```

Inside the guest, use `nix develop` for project toolchains. `codex --version`, `nix build`, `dfu-util`, `openocd`, and `avrdude` are available.

## Stop and recover USB

```bash
codex-usb-stop
```

The helper stops the guest, unbinds each passthrough function, clears `driver_override`, and writes each BDF to `/sys/bus/pci/drivers_probe`. If a controller remains unbound, reboot to let NixOS reacquire it with its normal driver.

## Status and diagnosis

```bash
codex-usb-status
codex-usb-diagnose
```

Useful guest checks:

```bash
lsusb
sudo dmesg -w
dfu-util -l
openocd --version
avrdude -?
```

## Update VM and rebuild host

```bash
nixos-rebuild build --flake .#nixos
sudo nixos-rebuild boot --flake .#nixos
```

After a host rebuild, the fully declarative VM is regenerated with the host. Reboot is required for the new IOMMU kernel parameters and initrd VFIO modules:

```bash
cat /proc/cmdline
find /sys/kernel/iommu_groups -type l -printf '%p -> %l\n'
lspci -nnk
```

Start the VM only after confirming the target controllers initially use their normal host drivers. Then confirm `vfio-pci` on the host and `lspci -nnk`, `lsusb`, `sudo lsusb`, `nix --version`, `nix flake metadata`, and `codex --version` in the guest. Create and delete a test file in `/workspace`.

## Troubleshooting

- `codex-usb-start` refuses an IOMMU group containing an undeclared device, USB-backed host storage, or USB-backed host networking.
- A firmware reset/disconnect/re-enumeration stays inside the guest because the PCI controller, not an individual USB device, is passed through.
- The Nix writable overlay database is not a durable package registry across reboot. Keep each firmware project's `flake.nix` and `devShell` authoritative.
- The current host had only about 4.8 GiB free during setup; free disk space before creating the guest volumes.
