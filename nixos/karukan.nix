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
assert lib.versionAtLeast openvino.version "2026.4.0";
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
    # Keep llama.cpp/ggml private to the Karukan Rust cdylib. Forcing shared
    # libraries makes fcitx depend on transient libllama.so.N SONAME files
    # produced inside Cargo's target tree, which are not a stable Nix runtime
    # interface. OpenVINO/TBB/OpenCL remain ordinary shared dependencies.
    LLAMA_BUILD_SHARED_LIBS = "0";
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
      -DOpenVINO_DIR="$openvino_cmake_dir" \
      -DTBB_DIR="$tbb_cmake_dir" \
      -DOpenCL_INCLUDE_DIR=${opencl-headers}/include \
      -DOpenCL_LIBRARY=${lib.getLib ocl-icd}/lib/libOpenCL.so \
      -DKARUKAN_NATIVE=OFF
    cmake --build build --parallel "$NIX_BUILD_CORES"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cmake --install build

    runHook postInstall
  '';

  postFixup = ''
    # karukan.so loads libkarukan_fcitx5.so from the same addon directory.
    # llama.cpp and ggml must be statically linked into that Rust cdylib.
    for library in "$out"/lib/fcitx5/*.so*; do
      [ -e "$library" ] || continue
      patchelf --add-rpath '$ORIGIN' "$library"
    done

    rustlib="$out/lib/fcitx5/libkarukan_fcitx5.so"
    unexpected="$(patchelf --print-needed "$rustlib" | grep -E '^lib(llama|ggml)' || true)"
    if [ -n "$unexpected" ]; then
      echo "Karukan unexpectedly has dynamic llama/ggml dependencies:" >&2
      echo "$unexpected" >&2
      exit 1
    fi

    # Catch the exact class of failure that previously survived package build
    # and only appeared when Fcitx dlopen()ed the addon. Plain ldd only checks
    # that DT_NEEDED files exist; -r also resolves relocations and therefore
    # catches undefined OpenVINO C++ symbols such as ov::Any::Base RTTI.
    runtime_path="$out/lib/fcitx5:${lib.makeLibraryPath [ openvino onetbb ocl-icd ]}"
    addon="$out/lib/fcitx5/karukan.so"

    if ! patchelf --print-needed "$addon" | grep -Eq '^libopenvino\.so'; then
      echo "karukan.so does not retain a direct OpenVINO runtime dependency" >&2
      patchelf --print-needed "$addon" >&2
      exit 1
    fi

    missing="$(LD_LIBRARY_PATH="$runtime_path" ldd "$rustlib" | grep 'not found' || true)"
    if [ -n "$missing" ]; then
      echo "Unresolved Karukan runtime dependencies in $rustlib:" >&2
      echo "$missing" >&2
      exit 1
    fi

    relocations="$(LD_LIBRARY_PATH="$runtime_path" ldd -r "$addon" 2>&1 || true)"
    if printf '%s\n' "$relocations" | grep -Eq 'not found|undefined symbol'; then
      echo "Karukan addon has unresolved runtime relocations:" >&2
      printf '%s\n' "$relocations" >&2
      exit 1
    fi
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
