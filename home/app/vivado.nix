{ pkgs }:
let
  # The AMD installer and Vivado binaries expect a conventional Linux FHS.
  # Keep the vendor installation outside of the Nix store and do not package it.
  fhs = pkgs.buildFHSEnv {
    name = "vivado-fhs";
    targetPkgs = pkgs: with pkgs; [
      bash
      coreutils
      findutils
      gawk
      gcc
      gnumake
      gnugrep
      gnused
      graphviz
      nettools
      unzip
      which
      stdenv.cc.cc
      zlib
      libuuid
      ncurses5
      ncurses
      libxcrypt-legacy
      libpng
      libusb1
      systemd
      pixman
      openssl
      fontconfig
      freetype
      glib
      gtk2
      gtk3
      libGL
      libx11
      libxext
      libxrender
      libxtst
      libxi
      libxft
      libxcb
      libxcursor
      libxrandr
    ];
    profile = ''
      export LD_LIBRARY_PATH="/usr/lib:/usr/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    '';
    runScript = "bash";
  };
in {
  inherit fhs;
  launcher = pkgs.writeShellApplication {
    name = "vivado";
    text = ''
      exec ${pkgs.bash}/bin/bash ${../../scripts/vivado.sh} ${fhs}/bin/vivado-fhs "$@"
    '';
  };
}
