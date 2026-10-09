# UEFI dual boot after installing Windows 11 first.
# Windows' original ESP is mounted at /efi, while the NixOS kernels and
# initrds go on a separate FAT32 XBOOTLDR partition mounted at /boot.
{ ... }: {
  boot.loader.efi.efiSysMountPoint = "/efi";
  boot.loader.systemd-boot.xbootldrMountPoint = "/boot";

  # Used by update.sh to select the right flake configuration on this host.
  environment.etc."dotfiles-nixos-flake-profile".text = "nixos-windows\n";
}
