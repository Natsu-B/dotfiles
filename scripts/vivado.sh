#!/usr/bin/env bash
# Called by the Home Manager 'vivado' wrapper with the FHS executable as $1.
set -euo pipefail

fhs=${1:?missing vivado-fhs launcher}
shift

if [[ -n "${XILINX_VIVADO:-}" ]]; then
  vivado_dir=${XILINX_VIVADO%/}
else
  # AMD 2025.1+: <prefix>/<version>/Vivado; older releases:
  # <prefix>/Vivado/<version>. Ignore incomplete installations.
  shopt -s nullglob
  candidates=()
  if [[ -n "${VIVADO_INSTALL_ROOT:-}" ]]; then
    roots=("$VIVADO_INSTALL_ROOT")
  else
    roots=(/opt/Xilinx /opt/AMD /opt/amd "$HOME/Xilinx" "$HOME/AMD" "$HOME/amd")
  fi
  for root in "${roots[@]}"; do
    for dir in "$root"/*/Vivado "$root"/Vivado/*; do
      if [[ -f "$dir/settings64.sh" && -x "$dir/bin/vivado" ]]; then
        candidates+=("$dir")
      fi
    done
  done

  if (( ${#candidates[@]} != 1 )); then
    if (( ${#candidates[@]} == 0 )); then
      echo 'vivado: installation not found.' >&2
    else
      echo 'vivado: multiple installations found:' >&2
      printf '  %s\n' "${candidates[@]}" >&2
    fi
    echo 'Install AMD Vivado separately, then set XILINX_VIVADO to its Vivado directory.' >&2
    echo 'Example: export XILINX_VIVADO=/opt/Xilinx/2025.2/Vivado' >&2
    exit 1
  fi
  vivado_dir=${candidates[0]}
fi

if [[ ! -f "$vivado_dir/settings64.sh" || ! -x "$vivado_dir/bin/vivado" ]]; then
  echo "vivado: expected settings64.sh and executable bin/vivado in: $vivado_dir" >&2
  exit 1
fi

# The GUI is bundled Qt5 + Java AWT, which only work through XWayland.
# Host Qt6/Wayland settings break Qt (blank window); non-reparenting WMs
# (Hyprland, sway) leave Java windows white. Set VIVADO_KEEP_QT_ENV=1 to skip.
if [[ -z "${VIVADO_KEEP_QT_ENV:-}" ]]; then
  unset QT_PLUGIN_PATH QT_QPA_PLATFORMTHEME QT_QPA_PLATFORMTHEME_QT6 \
    QML2_IMPORT_PATH QML_IMPORT_PATH QT_IM_MODULE
  export QT_QPA_PLATFORM=xcb
fi
export _JAVA_AWT_WM_NONREPARENTING=1

# Source AMD's environment inside the same FHS process used to launch Vivado.
# Forward arguments unchanged (e.g. -mode batch -source build.tcl).
exec "$fhs" -c 'source "$1"; shift; exec "$1" "${@:2}"' \
  vivado "$vivado_dir/settings64.sh" "$vivado_dir/bin/vivado" "$@"
