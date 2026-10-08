{
  hostName,
  inputs,
  ...
}: {
  imports = [
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p14s-intel-gen5
    ./hardware-configuration.nix
    ../../nixos/configuration.nix
  ];

  networking.hostName = hostName;
}
