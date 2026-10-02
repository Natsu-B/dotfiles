{
  lib,
  rustPlatform,
  cmake,
  fcitx5,
  kdePackages,
  libxkbcommon,
  ocl-icd,
  opencl-headers,
  openssl,
  openvino,
  patchelf,
  pkg-config,
  python3,
}:

let
  rev = "fbe9927548b75435bd43410aaaad742e39f579c8";
  src = builtins.fetchGit {
    url = "https://github.com/togatoga/karukan.git";
    inherit rev;
  };
in
rustPlatform.buildRustPackage {
  pname = "fcitx5-karukan";
  version = "0-unstable-2026-09-29";
  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";

  nativeBuildInputs = [
    cmake
    kdePackages.extra-cmake-modules
    patchelf
    pkg-config
    python3
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    fcitx5
    libxkbcommon
    ocl-icd
    opencl-headers
    openssl
    openvino
  ];

  env = {
    CARGO_NET_OFFLINE = "true";
    GGML_OPENVINO = "ON";
    LLAMA_BUILD_SHARED_LIBS = "1";
  };

  postPatch = ''
    python3 ${./patch-karukan.py} "$PWD"
  '';

  dontUseCmakeConfigure = true;
  doCheck = false;

  buildPhase = ''
    runHook preBuild
    export CARGO_TARGET_DIR="$PWD/target"

    openvino_config="$(find ${openvino} -type f -name OpenVINOConfig.cmake -print -quit)"
    if [ -z "$openvino_config" ]; then
      echo "OpenVINOConfig.cmake not found under ${openvino}" >&2
      exit 1
    fi
    openvino_cmake_dir="$(dirname "$openvino_config")"
    export OpenVINO_DIR="$openvino_cmake_dir"
    export OpenVINO_ROOT="${openvino}"
    export CMAKE_PREFIX_PATH="$openvino_cmake_dir''${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
    echo "Using OpenVINO CMake package: $openvino_config"

    cmake -S karukan-im/fcitx5/fcitx5-addon -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$out" \
      -DECM_DIR=${kdePackages.extra-cmake-modules}/share/ECM/cmake \
      -DKARUKAN_NATIVE=OFF
    cmake --build build --parallel "$NIX_BUILD_CORES"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cmake --install build

    # llama-cpp-sys copies its shared llama/ggml backends into target/release.
    # Keep them beside the Fcitx addon so the plugin remains self-contained.
    mkdir -p "$out/lib/fcitx5"
    for library in target/release/lib*.so*; do
      case "$(basename "$library")" in
        libkarukan_fcitx5.so) continue ;;
      esac
      install -m755 "$library" "$out/lib/fcitx5/"
    done
    runHook postInstall
  '';

  postFixup = ''
    for library in "$out"/lib/fcitx5/*.so*; do
      patchelf --add-rpath '$ORIGIN' "$library"
    done
  '';

  meta = {
    description = "Karukan Fcitx5 Japanese IME with OpenVINO NPU acceleration and CPU fallback";
    homepage = "https://github.com/togatoga/karukan";
    license = with lib.licenses; [ mit asl20 ];
    platforms = lib.platforms.linux;
  };
}
