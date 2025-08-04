{
  inputs = {
    # Use stable branches for the base system
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    home-manager.url = "github:nix-community/home-manager/release-24.05";

    # Use unstable branch just for specific packages via overlay
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, home-manager, nixpkgs-unstable, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # 1. Define an overlay to inject packages from unstable into stable.
        unstable-overlay = final: prev: {
          xremap = nixpkgs-unstable.legacyPackages.${system}.xremap;
        };

        # 2. Apply the overlay to the stable nixpkgs.
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ unstable-overlay ];
        };

        username = "hotaru";

        hmConfig = home-manager.lib.homeManagerConfiguration {
          # 3. Pass the overlaid pkgs to home-manager.
          inherit pkgs;
          modules = [ ./home.nix ];
          extraSpecialArgs = { inherit username; };
        };
      in
      {
        packages = {
          "home-manager" = hmConfig.activationPackage;
        };
        homeConfigurations."${username}" = hmConfig;
      }
    );
}
