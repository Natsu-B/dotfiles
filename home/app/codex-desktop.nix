{ pkgs, lib, stdenvNoCC, fetchurl, dpkg, makeWrapper, autoPatchelfHook }:
let
  version = "26.928.31416";
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
  nativeBuildInputs = [ dpkg makeWrapper autoPatchelfHook ];
  buildInputs = with pkgs; [
    stdenv.cc.cc
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    gtk4
    libdrm
    libgbm
    libGL
    libnotify
    libsecret
    libusb1
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libxshmfence
    nspr
    nss
    pango
    pipewire
    systemd
    tpm2-tss
    vulkan-loader
    zlib
  ];
  # These libraries are loaded dynamically, so keep them in the ELF runpath.
  # Do not export LD_LIBRARY_PATH into browsers launched by the app.
  runtimeDependencies = with pkgs; [ libsecret libnotify libGL pipewire tpm2-tss vulkan-loader ];
  # Bundled optional musl prebuilds are not used on glibc-based NixOS.
  autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" ];
  unpackPhase = ''
    dpkg-deb -x "$src" .
  '';
  dontBuild = true;
  dontStrip = true;
  preFixup = ''
    # Electron ships both Qt shims; load their libraries without combining
    # the mutually exclusive Qt 5 and Qt 6 build setup hooks.
    addAutoPatchelfSearchPath ${lib.getLib pkgs.qt5.qtbase}/lib
    addAutoPatchelfSearchPath ${lib.getLib pkgs.qt6.qtbase}/lib
  '';
  installPhase = ''
    mkdir -p "$out/lib" "$out/bin"
    cp -r usr/lib/chatgpt "$out/lib/chatgpt"
    cp -r usr/share "$out/share"
    # ChatGPT defaults to XWayland. On fractional-scale Hyprland that makes
    # the Chromium surface blurry/incorrectly scaled, and Fcitx preedit is
    # unreliable. Use the app's documented native Wayland path explicitly.
    # Run in the desktop's namespaces: Chromium's profile socket lives in /tmp.
    makeWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.xdg-utils pkgs.bubblewrap ]} \
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
