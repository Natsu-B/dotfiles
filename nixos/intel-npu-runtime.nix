{ lib, stdenv, fetchurl, dpkg, autoPatchelfHook, onetbb, zlib, zstd }:
stdenv.mkDerivation {
  pname = "intel-npu-runtime";
  version = "1.38.0";
  src = fetchurl {
    url = "https://github.com/intel/linux-npu-driver/releases/download/v1.38.0/linux-npu-driver-v1.38.0.20260910-34487311128-ubuntu2404.tar.gz";
    hash = "sha256-HvzUtgwiq+51HY8nBZYsvMKlad5Fx+DmcM8Ir7/NwdI=";
  };
  nativeBuildInputs = [ dpkg autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib onetbb zlib zstd ];
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    dpkg-deb -x intel-driver-compiler-npu_*.deb extracted
    dpkg-deb -x intel-level-zero-npu_*.deb extracted
    mkdir -p "$out/lib"
    cp -P extracted/usr/lib/x86_64-linux-gnu/*.so* "$out/lib/"
    ln -s libopenvino_intel_npu_compiler_loader.so "$out/lib/libnpu_driver_compiler.so"
  '';
  meta = {
    description = "Intel NPU userspace driver and compiler";
    homepage = "https://github.com/intel/linux-npu-driver/releases/tag/v1.38.0";
    license = with lib.licenses; [ mit asl20 ];
    platforms = [ "x86_64-linux" ];
  };
}
