{
  lib,
  rustPlatform,
  cmake,
  fcitx5,
  kdePackages,
  libxkbcommon,
  level-zero,
  ocl-icd,
  opencl-headers,
  opencl-clhpp,
  openssl,
  openvino,
  onetbb,
  npuRuntime,
  patchelf,
  pkg-config,
  python3,
  shaderc,
  glslang,
  vulkan-loader,
  vulkan-headers,
  spirv-headers,
  openvinoSupport ? true,
  vulkanSupport ? false,
}:

let
  rev = "fbe9927548b75435bd43410aaaad742e39f579c8";
  src = builtins.fetchGit {
    url = "https://github.com/togatoga/karukan.git";
    inherit rev;
  };
in
assert lib.versionAtLeast openvino.version "2026.4.0";
assert !(openvinoSupport && vulkanSupport);
rustPlatform.buildRustPackage {
  pname = "fcitx5-karukan";
  version = "0-unstable-2026-09-29";
  inherit src;

  cargoLock.lockFile = "${src}/Cargo.lock";
  # Drop incompatible NPU cache mode; unavailable devices select GPU before load.
  cargoDeps = (rustPlatform.importCargoLock { lockFile = "${src}/Cargo.lock"; }).overrideAttrs (old: {
    buildCommand = old.buildCommand + ''
      # OpenVINO 2026.4 rejects this obsolete NPU compiler option before inference.
      crate="$out/llama-cpp-sys-2-0.1.157"
      original="$(readlink -f "$crate")"
      rm "$crate"
      cp -r --no-preserve=mode "$original" "$crate"
      substituteInPlace "$crate/llama.cpp/ggml/src/ggml-openvino/ggml-openvino-extra.cpp" \
        --replace-fail '{"NPU_COMPILER_DYNAMIC_QUANTIZATION", "YES"   },' "" \
        --replace-fail 'is not available, fallback to CPU' 'is not available, fallback to GPU' \
        --replace-fail 'device_name = "CPU";' 'device_name = "GPU";' \
        --replace-fail '            compile_config.insert(ov::cache_mode(ov::CacheMode::OPTIMIZE_SIZE));' ""
    '';
  });

  nativeBuildInputs = [
    cmake
    kdePackages.extra-cmake-modules
    patchelf
    pkg-config
    python3
    rustPlatform.bindgenHook
  ] ++ lib.optionals vulkanSupport [ shaderc glslang ];

  buildInputs = [
    fcitx5
    libxkbcommon
    ocl-icd
    opencl-headers
    opencl-clhpp
    openssl
    openvino.dev
    openvino.lib
    onetbb
  ] ++ lib.optionals vulkanSupport [ vulkan-loader vulkan-headers spirv-headers ];

  env = {
    CARGO_NET_OFFLINE = "true";
    GGML_OPENVINO = if openvinoSupport then "ON" else "OFF";
    # Keep llama.cpp/ggml private to the Karukan Rust cdylib. Forcing shared
    # libraries makes fcitx depend on transient libllama.so.N SONAME files
    # produced inside Cargo's target tree, which are not a stable Nix runtime
    # interface. OpenVINO/TBB/OpenCL remain ordinary shared dependencies.
    LLAMA_BUILD_SHARED_LIBS = "0";
  };

  postPatch = ''
    python3 ${./patch-karukan.py} "$PWD"
    python3 ${./patch-karukan-async.py} "$PWD" ${./karukan-async-live.rs}
  '' + lib.optionalString vulkanSupport ''
    substituteInPlace karukan-engine/Cargo.toml \
      --replace-fail 'llama-cpp-2 = "0.1"' 'llama-cpp-2 = { version = "0.1", features = ["vulkan"] }'
  '';

  dontUseCmakeConfigure = true;
  doCheck = false;

  buildPhase = ''
    runHook preBuild
    export CARGO_TARGET_DIR="$PWD/target"

    # OpenVINO 2026.4 is split into multiple outputs. The CMake metadata is in
    # the dev output, but nixpkgs' install-path patch currently uses a lowercase
    # lib/cmake/openvino directory. Discover the config inside the correct output
    # instead of depending on upstream/nixpkgs directory capitalization.
    openvino_config="$(find ${openvino.dev} -type f -name OpenVINOConfig.cmake -print -quit)"
    if [ -z "$openvino_config" ]; then
      echo "OpenVINOConfig.cmake not found under ${openvino.dev}" >&2
      find ${openvino.dev} -maxdepth 4 -type f -name '*.cmake' -print >&2 || true
      exit 1
    fi
    openvino_cmake_dir="$(dirname "$openvino_config")"
    export OpenVINO_DIR="$openvino_cmake_dir"
    export OpenVINO_ROOT="${openvino.dev}"

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
      -DKARUKAN_OPENVINO=${if openvinoSupport then "ON" else "OFF"} \
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
    runtime_path="$out/lib/fcitx5:${lib.makeLibraryPath ([ openvino.lib onetbb ocl-icd ] ++ lib.optionals vulkanSupport [ vulkan-loader ])}"
    addon="$out/lib/fcitx5/karukan.so"

    if ${lib.boolToString openvinoSupport} && ! patchelf --print-needed "$addon" | grep -Eq '^libopenvino\.so'; then
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
    openvino.lib
    onetbb
    ocl-icd
    level-zero
    npuRuntime
  ];

  meta = {
    description = "Karukan Fcitx5 Japanese IME with optional OpenVINO acceleration";
    homepage = "https://github.com/togatoga/karukan";
    license = with lib.licenses; [ mit asl20 ];
    platforms = lib.platforms.linux;
  };
}
