{ pkgs, lib, stdenvNoCC, fetchurl, dpkg, makeWrapper }:
let
  version = "26.928.31416";
  runtime = (pkgs.steam.override {
    extraPkgs = p: with p; [ gtk3 nss libsecret libnotify tpm2-tss xdg-utils ];
  }).run-free;
in
stdenvNoCC.mkDerivation {
  pname = "codex-desktop";
  inherit version;
  # "latest" is overwritten in place and cannot be used with a Nix fixed-output
  # hash. Pin the immutable package from OpenAI's APT pool instead.
  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${version}_amd64.deb";
    hash = "sha256-xGNyfx7V3O14M4yOKmXYib0VMnb/Nz/XdpjMua8y0YE=";
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
    # ChatGPT defaults to XWayland. On fractional-scale Hyprland that makes
    # the Chromium surface blurry/incorrectly scaled, and Fcitx preedit is
    # unreliable. Use the app's documented native Wayland path explicitly.
    makeWrapper ${runtime}/bin/steam-run "$out/bin/chatgpt" \
      --add-flags "$out/lib/chatgpt/ChatGPT" \
      --add-flags "--enable-features=UseOzonePlatform" \
      --add-flags "--ozone-platform=wayland" \
      --add-flags "--enable-wayland-ime"
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
