# UEFI dual boot after installing Windows 11 first.
# Windows' original ESP is mounted at /efi, while the NixOS kernels and
# initrds go on a separate FAT32 XBOOTLDR partition mounted at /boot.
{ config, ... }: {
  boot.loader.efi.efiSysMountPoint = "/efi";
  boot.loader.systemd-boot.xbootldrMountPoint = "/boot";

  assertions = [ {
    assertion = builtins.hasAttr "/efi" config.fileSystems
      && config.fileSystems."/efi".fsType == "vfat"
      && config.fileSystems."/boot".fsType == "vfat";
    message = "Windows dual boot requires FAT filesystems at /efi (ESP) and /boot (XBOOTLDR).";
  } {
    assertion = builtins.hasAttr "/efi" config.fileSystems
      && config.fileSystems."/efi".device != config.fileSystems."/boot".device
      && config.fileSystems."/".device != config.fileSystems."/boot".device
      && config.fileSystems."/".device != config.fileSystems."/efi".device;
    message = "Root, Windows ESP and XBOOTLDR must use distinct filesystem devices.";
  } ];

  # Used by update.sh to select the right flake configuration on this host.
  environment.etc."dotfiles-nixos-flake-profile".text = "nixos\n";
}
