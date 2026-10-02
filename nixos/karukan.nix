{
  lib,
  rustPlatform,
  cmake,
  fcitx5,
  kdePackages,
  libxkbcommon,
  ocl-icd,
  opencl-headers,
  opencl-clhpp,
  openssl,
  openvino,
  onetbb,
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
    opencl-clhpp
    openssl
    openvino
    onetbb
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

    tbb_config="$(find ${onetbb.dev} -type f -name TBBConfig.cmake -print -quit)"
    if [ -z "$tbb_config" ]; then
      echo "TBBConfig.cmake not found under ${onetbb.dev}" >&2
      exit 1
    fi
    tbb_cmake_dir="$(dirname "$tbb_config")"
    export TBB_DIR="$tbb_cmake_dir"
    export TBB_ROOT="${onetbb}"
    echo "Using TBB CMake package: $tbb_config"
    echo "Using OpenVINO CMake package: $openvino_config"

    cmake -S karukan-im/fcitx5/fcitx5-addon -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$out" \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DECM_DIR=${kdePackages.extra-cmake-modules}/share/ECM/cmake \
      -DKARUKAN_NATIVE=OFF
    cmake --build build --parallel "$NIX_BUILD_CORES"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cmake --install build

    # llama-cpp-sys copies its shared llama/ggml libraries into target/release.
    # Keep them beside the Fcitx addon so every transitive dependency can be
    # resolved from $ORIGIN. The crate only copies the unversioned .so name,
    # while ELF DT_SONAME/DT_NEEDED use versioned names such as libllama.so.0.
    mkdir -p "$out/lib/fcitx5"
    for library in target/release/lib*.so*; do
      case "$(basename "$library")" in
        libkarukan_fcitx5.so) continue ;;
      esac
      install -m755 "$library" "$out/lib/fcitx5/"
    done

    # Recreate the SONAME aliases lost when Nix installs/dereferences the
    # llama-cpp-sys symlinks. Do this generically for llama and every ggml
    # backend instead of hard-coding today's ABI number.
    for library in "$out"/lib/fcitx5/lib*.so; do
      [ -e "$library" ] || continue
      soname="$(patchelf --print-soname "$library" 2>/dev/null || true)"
      base="$(basename "$library")"
      if [ -n "$soname" ] && [ "$soname" != "$base" ]; then
        ln -sfn "$base" "$out/lib/fcitx5/$soname"
      fi
    done
    runHook postInstall
  '';

  postFixup = ''
    for library in "$out"/lib/fcitx5/*.so*; do
      [ -e "$library" ] || continue
      patchelf --add-rpath '$ORIGIN' "$library"
    done

    # This is the failure that escaped the previous CI: the package built, but
    # dlopen(karukan.so) failed later because libllama.so.0 was absent. Make
    # unresolved runtime libraries a build failure instead.
    runtime_path="$out/lib/fcitx5:${lib.makeLibraryPath [ openvino onetbb ocl-icd ]}"
    for library in "$out/lib/fcitx5/karukan.so" "$out/lib/fcitx5/libkarukan_fcitx5.so"; do
      missing="$(LD_LIBRARY_PATH="$runtime_path" ldd "$library" | grep 'not found' || true)"
      if [ -n "$missing" ]; then
        echo "Unresolved Karukan runtime dependencies in $library:" >&2
        echo "$missing" >&2
        exit 1
      fi
    done
  '';

  passthru.extraLdLibraries = [
    openvino
    onetbb
    ocl-icd
  ];

  meta = {
    description = "Karukan Fcitx5 Japanese IME with OpenVINO NPU acceleration and CPU fallback";
    homepage = "https://github.com/togatoga/karukan";
    license = with lib.licenses; [ mit asl20 ];
    platforms = lib.platforms.linux;
  };
}
