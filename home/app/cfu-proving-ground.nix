{ pkgs, vivado }:
let
  # Upstream builds for RV32IM/ILP32. The default riscv32-embedded Nix
  # toolchain may instead have hard-float newlib/libgcc, so compile the
  # bare-metal runtime for the project's actual ABI.
  riscvPkgs = import pkgs.path {
    localSystem = pkgs.stdenv.buildPlatform.system;
    crossSystem = {
      config = "riscv32-none-elf";
      gcc = {
        arch = "rv32im";
        abi = "ilp32";
      };
    };
  };
  riscvCc = riscvPkgs.stdenv.cc;
  riscvBinutils = riscvCc.bintools;
  prefix = riscvCc.targetPrefix;

  # CFU-Proving-Ground's upstream Makefile hard-codes 'gcc' when compiling
  # the X11/Cairo display simulator, with no way to pass CPPFLAGS/LDFLAGS.
  # Scope the search paths to this native compiler rather than contaminating
  # the RISC-V toolchain with host-only flags.
  displayGcc = pkgs.writeShellScriptBin "gcc" ''
    exec ${pkgs.gcc}/bin/gcc \
      -I${pkgs.cairo.dev}/include \
      -I${pkgs.xorg.libX11.dev}/include \
      -L${pkgs.cairo.out}/lib \
      -L${pkgs.xorg.libX11.out}/lib \
      -Wl,-rpath,${pkgs.cairo.out}/lib \
      -Wl,-rpath,${pkgs.xorg.libX11.out}/lib \
      "$@"
  '';
in
pkgs.writeShellApplication {
  name = "cfu-make";
  runtimeInputs = with pkgs; [
    bc
    coreutils
    gnumake
    gnugrep
    perl
    util-linux
    verilator
  ];
  text = ''
    export PATH="${displayGcc}/bin:$PATH"
    export CFU_PG_MAKE="${pkgs.gnumake}/bin/make"
    export CFU_PG_GCC="${riscvCc}/bin/${prefix}gcc"
    export CFU_PG_GPP="${riscvCc}/bin/${prefix}g++"
    export CFU_PG_OBJCOPY="${riscvBinutils}/bin/${prefix}objcopy"
    export CFU_PG_OBJDUMP="${riscvBinutils}/bin/${prefix}objdump"
    export CFU_PG_VERILATOR="${pkgs.verilator}/bin/verilator"
    export CFU_PG_VIVADO="${vivado.launcher}/bin/vivado"
    exec ${pkgs.bash}/bin/bash ${../../scripts/cfu-make.sh} "$@"
  '';
}
