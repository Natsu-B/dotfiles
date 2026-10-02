{ pkgs, lib, stdenvNoCC, fetchurl, dpkg, makeWrapper }:
let
  runtime = (pkgs.steam.override {
    extraPkgs = p: with p; [ gtk3 nss libsecret libnotify tpm2-tss xdg-utils ];
  }).run-free;
in
stdenvNoCC.mkDerivation {
  pname = "codex-desktop";
  version = "26.928.31416";
  # "latest" is overwritten in place and cannot be used with a Nix fixed-output
  # hash. Pin the immutable package from OpenAI's APT pool instead.
  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${version}_amd64.deb";
    hash = "sha256-gJQATxy8zzXe797RWWGqQrTbiJEhpdlSxfMM+CvYrTA=";
  };
  nativeBuildInputs = [ dpkg makeWrapper ];
  unpackPhase = ''
    dpkg-deb -x "$src" .
  '';
  dontBuild = true;
  dontFixup = true;
  installPhase = ''
    mkdir -p "$out/lib" "$out/bin"
    cp -r usr/lib/chatgpt "$out/lib/chatgpt"
    cp -r usr/share "$out/share"
    makeWrapper ${runtime}/bin/steam-run "$out/bin/chatgpt" \
      --add-flags "$out/lib/chatgpt/ChatGPT"
    ln -s chatgpt "$out/bin/codex-desktop"
    substituteInPlace "$out/share/applications/chatgpt.desktop" \
      --replace-fail 'Exec=chatgpt' "Exec=$out/bin/chatgpt"
  '';
  meta = {
    description = "Official ChatGPT desktop app with Codex";
    homepage = "https://learn.chatgpt.com/docs/linux/linux-app";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "codex-desktop";
  };
}
