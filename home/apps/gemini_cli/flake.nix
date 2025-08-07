{
  description = "A flake for packaging Google's Gemini CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    gemini-cli-src = {
      url = "github:google/generative-ai-go";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, gemini-cli-src }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.gemini = pkgs.buildGoModule {
          pname = "gemini-cli";
          version = "main";

          src = gemini-cli-src;

          vendorHash = "sha256-Opp972ELUcr4fD0SryQUV3kot+kmK0mgsWjsn4hrLSU=";

          doCheck = false;
        };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.gemini}/bin/gemini";
        };
      });
}