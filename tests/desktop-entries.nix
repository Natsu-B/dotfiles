{ pkgs, homeConfig }:
let
  inherit (pkgs) lib;
  entries = lib.filterAttrs (name: _: lib.hasPrefix "dotfiles-" name) homeConfig.xdg.desktopEntries;
  packagesByName = lib.groupBy (package: package.name or "") homeConfig.home.packages;
  # Use the actual Home Manager derivations, not a second renderer or a mock
  # entry. Merely evaluating their drvPath does not run desktop-file-validate.
  desktopFiles = lib.mapAttrsToList (name: _: let
    matches = packagesByName."${name}.desktop" or [];
  in
    assert lib.assertMsg (builtins.length matches == 1)
      "Expected exactly one Home Manager package for ${name}.desktop";
    "${builtins.head matches}/share/applications/${name}.desktop"
  ) entries;
in
assert lib.assertMsg (entries != {}) "No dotfiles desktop entries were selected for validation";
pkgs.runCommand "dotfiles-desktop-entries-check" {
  nativeBuildInputs = [ pkgs.desktop-file-utils pkgs.gnugrep ];
} ''
  set -euo pipefail

  # A negative control ensures that invalid desktop IDs are not being ignored.
  cat > invalid.desktop <<'EOF'
  [Desktop Entry]
  Type=Application
  Name=Invalid desktop ID control
  Exec=true
  OnlyShowIn=NOT_A_REGISTERED_DESKTOP_DOTFILES;
  EOF
  if desktop-file-validate invalid.desktop > invalid.log 2>&1; then
    echo "desktop-file-validate accepted an unregistered desktop ID" >&2
    exit 1
  fi
  grep -F 'contains an unregistered value' invalid.log

  count=0
  for desktop in ${lib.escapeShellArgs desktopFiles}; do
    desktop-file-validate "$desktop"
    # No X-Hyprland workaround: it would validate but not match Hyprland.
    if grep -Eq '^(OnlyShowIn=|Hidden=true$|NoDisplay=true$)' "$desktop"; then
      echo "Unexpected visibility restriction: $desktop" >&2
      exit 1
    fi
    case "$desktop" in
      */dotfiles-keyboard.desktop)
        # The keyboard action is intentionally shared with the GNOME fallback.
        if grep -q '^NotShowIn=' "$desktop"; then
          echo "The shared keyboard action is hidden in a desktop session" >&2
          exit 1
        fi
        ;;
      *) grep -Fx 'NotShowIn=GNOME;' "$desktop" ;;
    esac
    echo "Validated: $desktop"
    count=$((count + 1))
  done
  test "$count" -eq ${toString (builtins.length desktopFiles)}
  echo "Validated $count actual Home Manager desktop entries"
  touch "$out"
''
