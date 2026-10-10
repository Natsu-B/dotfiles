{ pkgs, karukan }:
pkgs.runCommand "karukan-async-frontend-check" {
  nativeBuildInputs = [ pkgs.gcc pkgs.pkg-config pkgs.python3 ];
  buildInputs = [ pkgs.fcitx5 pkgs.libxkbcommon ];
} ''
  cp -r ${karukan.src} source
  chmod -R u+w source
  python3 ${../nixos/patch-karukan.py} source
  python3 ${../nixos/patch-karukan-async.py} source ${../nixos/karukan-async-live.rs}
  mkdir -p "$out/bin"
  c++ -std=c++20 -DFCITX5_HAS_CANDIDATE_SET_COMMENT \
    -Isource/karukan-im/fcitx5/fcitx5-addon/src \
    ${./karukan_frontend.cpp} source/karukan-im/fcitx5/fcitx5-addon/src/karukan.cpp \
    $(pkg-config --cflags --libs Fcitx5Core Fcitx5Config Fcitx5Utils xkbcommon) \
    -L${karukan}/lib/fcitx5 -lkarukan_fcitx5 \
    -Wl,-rpath,${karukan}/lib/fcitx5 \
    -o "$out/bin/karukan-frontend-check"
''
