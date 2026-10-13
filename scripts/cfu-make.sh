#!/usr/bin/env bash
# Adapt CFU-Proving-Ground's absolute tool paths without editing its Makefile.
set -euo pipefail

: "${CFU_PG_GCC:?RISC-V GCC is not configured}"
: "${CFU_PG_GPP:?RISC-V G++ is not configured}"
: "${CFU_PG_OBJCOPY:?RISC-V objcopy is not configured}"
: "${CFU_PG_OBJDUMP:?RISC-V objdump is not configured}"
: "${CFU_PG_VERILATOR:?Verilator is not configured}"
: "${CFU_PG_VIVADO:?Vivado wrapper is not configured}"

exec "${CFU_PG_MAKE:-make}" \
  "GCC=$CFU_PG_GCC" \
  "GPP=$CFU_PG_GPP" \
  "OBJCOPY=$CFU_PG_OBJCOPY" \
  "OBJDUMP=$CFU_PG_OBJDUMP" \
  "RTLSIM=$CFU_PG_VERILATOR" \
  "VIVADO=$CFU_PG_VIVADO" \
  "VPP=${CFU_PG_VPP:-v++}" \
  "$@"
