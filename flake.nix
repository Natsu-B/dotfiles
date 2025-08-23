{
  description = "Hotaru's NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-unstable, nixpkgs-master, rust-overlay, ... }@inputs: {
    nixosConfigurations = {
      nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          # Pass unstable packages to the configuration
          unstable = nixpkgs-unstable.legacyPackages."x86_64-linux";
          master = nixpkgs-master.legacyPackages."x86_64-linux";
          inherit inputs self;
        };
        modules = [
          ({
            nixpkgs.overlays = [
              rust-overlay.overlays.default
              (final: prev: {
                rustToolchain = final.rust-bin.stable.latest.default.override {
                  targets = ["aarch64-unknown-none" "aarch64-unknown-uefi"];
                  extensions = ["rust-src"];
                };
              })
            ];
          })
          ./nixos/configuration.nix
          home-manager.nixosModules.home-manager
        ];
      };
    };
  };
}