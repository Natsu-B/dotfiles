{
  description = "Hotaru's NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-unstable, ... }@inputs: {
    nixosConfigurations = {
      # Change "nixos" to your actual hostname.
      # You can find it by running the `hostname` command in your terminal.
      nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          # Pass unstable packages to the configuration
          unstable = nixpkgs-unstable.legacyPackages."x86_64-linux";
          inherit inputs;
        };
        modules = [
          ./nixos/configuration.nix
        ];
      };
    };
  };
}