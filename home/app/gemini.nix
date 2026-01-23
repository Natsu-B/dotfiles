{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchNpmDeps,
  writeShellApplication,
  cacert,
  curl,
  gnused,
  jq,
  nix-prefetch-github,
  prefetch-npm-deps,
  pkg-config,
  libsecret,
}:

buildNpmPackage (finalAttrs: {
  pname = "gemini-cli";
  version = "0.17.1";

  nativeBuildInputs = [
    pkg-config
  ];
  buildInputs = [
    libsecret
  ];

  src = fetchFromGitHub {
    owner = "google-gemini";
    repo = "gemini-cli";
    # stable tag
    rev = "v0.17.1";
    hash = "sha256-zfORrAMVozHiUawWiy3TMT+pjEaRJ/DrHeDFPJiCp38=";
  };

  npmDeps = fetchNpmDeps {
    inherit (finalAttrs) src;
    hash = "sha256-dKaKRuHzvNJgi8LP4kKsb68O5k2MTqblQ+7cjYqLqs0=";
  };

  preConfigure = ''
    mkdir -p packages/generated
    echo "export const GIT_COMMIT_INFO = { commitHash: '${finalAttrs.src.rev}' };" > packages/generated/git-commit.ts
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{bin,share/gemini-cli}

    cp -r node_modules $out/share/gemini-cli/

    cp -r packages $out/share/gemini-cli/

    rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli
    rm -f $out/share/gemini-cli/node_modules/@google/gemini-cli-core
    cp -r packages/cli $out/share/gemini-cli/node_modules/@google/gemini-cli
    cp -r packages/core $out/share/gemini-cli/node_modules/@google/gemini-cli-core

    ln -s $out/share/gemini-cli/node_modules/@google/gemini-cli/dist/index.js $out/bin/gemini
    runHook postInstall
  '';

  postInstall = ''
    chmod +x "$out/bin/gemini"
  '';

  # updateScript は下に stable 追従版を提示
  passthru.updateScript = lib.getExe (writeShellApplication {
    name = "gemini-cli-update-script";
    runtimeInputs = [
      cacert curl gnused jq nix-prefetch-github prefetch-npm-deps
    ];
    text = ''
      # stable (npm latest) を追う
      latest_version=$(curl -s "https://registry.npmjs.org/@google/gemini-cli" \
        | jq -r '."dist-tags".latest')
      latest_tag="v$latest_version"

      # タグ → 実コミットSHAへ解決（annotated tag 対応）
      ref_json=$(curl -s "https://api.github.com/repos/google-gemini/gemini-cli/git/ref/tags/$latest_tag")
      obj_sha=$(echo "$ref_json" | jq -r '.object.sha')
      obj_type=$(echo "$ref_json" | jq -r '.object.type')
      if [ "$obj_type" = "tag" ]; then
        latest_rev=$(curl -s "https://api.github.com/repos/google-gemini/gemini-cli/git/tags/$obj_sha" \
          | jq -r '.object.sha')
      else
        latest_rev="$obj_sha"
      fi

      src_hash=$(nix-prefetch-github google-gemini gemini-cli --rev "$latest_rev" \
        | jq -r '.hash')

      temp_dir=$(mktemp -d)
      curl -s "https://raw.githubusercontent.com/google-gemini/gemini-cli/$latest_rev/package-lock.json" \
        > "$temp_dir/package-lock.json"
      npm_deps_hash=$(prefetch-npm-deps "$temp_dir/package-lock.json")
      rm -rf "$temp_dir"

      sed -i "s|version = \".*\";|version = \"$latest_version\";|" \
        "pkgs/by-name/ge/gemini-cli/package.nix"
      sed -i "s|rev = \".*\";|rev = \"v$latest_version\";|" \
        "pkgs/by-name/ge/gemini-cli/package.nix"
      sed -i "/src = fetchFromGitHub/,/};/s|hash = \".*\";|hash = \"$src_hash\";|" \
        "pkgs/by-name/ge/gemini-cli/package.nix"
      sed -i "/npmDeps = fetchNpmDeps/,/};/s|hash = \".*\";|hash = \"$npm_deps_hash\";|" \
        "pkgs/by-name/ge/gemini-cli/package.nix"
    '';
  });

  meta = {
    description = "AI agent that brings the power of Gemini directly into your terminal";
    homepage = "https://github.com/google-gemini/gemini-cli";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ FlameFlag ];
    platforms = lib.platforms.all;
    mainProgram = "gemini";
  };
})
