{
  description = "Hotaru's NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-unstable, nixpkgs-master, rust-overlay, ... }@inputs:
    let
      system = "x86_64-linux";
      hostName = "nixos";
    in {
    checks.${system} = {
      hibernate-policy = import ./tests/hibernate.nix {
        pkgs = nixpkgs.legacyPackages.${system};
        config = self.nixosConfigurations.nixos.config;
      };
      desktop-config = import ./tests/checks.nix {
        pkgs = nixpkgs.legacyPackages.${system};
      };
      desktop-tools = import ./tests/tools.nix {
        pkgs = nixpkgs.legacyPackages.${system};
        unstable = nixpkgs-unstable.legacyPackages.${system};
      };
      desktop-entries = import ./tests/desktop-entries.nix {
        pkgs = nixpkgs.legacyPackages.${system};
        homeConfig = self.nixosConfigurations.nixos.config.home-manager.users.hotaru;
      };
    };
    nixosConfigurations = {
      "${hostName}" = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          # Pass host identity and package sets to the configuration.
          unstable = nixpkgs-unstable.legacyPackages.${system};
          master = nixpkgs-master.legacyPackages.${system};
          inherit hostName inputs self;
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
          inputs.microvm.nixosModules.host
          ./hosts/${hostName}
          home-manager.nixosModules.home-manager
        ];
      };
    };
  };
}
