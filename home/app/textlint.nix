{ buildNpmPackage, textlint, textlint-rule-preset-ja-technical-writing }:
let
  # preset-japanese と preset-ai-writing は nixpkgs にないので npm から入れる。
  presets = buildNpmPackage {
    pname = "textlint-presets";
    version = "1.0.0";
    src = ./textlint-presets;
    npmDepsHash = "sha256-5/0QrcixEUz9TAh6NFrqGxsBn4J64ft8Z4RGtfioicc=";
    dontNpmBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib
      cp -r node_modules $out/lib/node_modules
      runHook postInstall
    '';
  };
in
textlint.withPackages [ presets textlint-rule-preset-ja-technical-writing ]
