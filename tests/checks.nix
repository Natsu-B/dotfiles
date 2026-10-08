{ pkgs }:
pkgs.runCommand "dotfiles-hyprland-lua-check" {
  nativeBuildInputs = [ pkgs.hyprland pkgs.lua5_4 pkgs.python3 ];
} ''
  cp -r ${../home} home
  cp ${./hyprland.lua} test-hyprland.lua
  lua test-hyprland.lua

  export HOME="$TMPDIR/home-test"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_RUNTIME_DIR="$TMPDIR/runtime"
  mkdir -p "$XDG_CONFIG_HOME/hypr/dms"
  mkdir -m 700 "$XDG_RUNTIME_DIR"
  cp ${../home/desktop/hypr}/*.lua "$XDG_CONFIG_HOME/hypr/"
  # Only the executable strings are fixtures; all compositor modules are real.
  cat > "$XDG_CONFIG_HOME/hypr/commands.lua" <<'LUA'
  return setmetatable({}, { __index = function(_, key) return "/bin/true " .. key end })
  LUA
  for part in outputs layout colors cursor windowrules; do
    echo '-- First-login writable DMS fragment' > "$XDG_CONFIG_HOME/hypr/dms/$part.lua"
  done
  Hyprland --verify-config -c "$XDG_CONFIG_HOME/hypr/hyprland.lua"
  touch "$out"
''
