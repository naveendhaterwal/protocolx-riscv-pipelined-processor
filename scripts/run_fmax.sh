#!/usr/bin/env bash
# =============================================================================
# scripts/run_fmax.sh - real maximum clock frequency (Fmax) with open-source tools.
#
# Flow: Yosys (synth_ecp5) -> nextpnr-ecp5 place & route -> static timing.
# Target: Lattice ECP5 LFE5U-85F (no board needed; nextpnr only needs the chip
# database). We use ECP5 because Vivado (for Xilinx Artix-7) does not run on
# macOS; the numbers are therefore ECP5 numbers, not Artix-7 numbers.
#
# Builds two designs with the same top (fpga/fpga_top.v), the same demo program
# and the same tools: the 5-stage pipeline and the single-cycle baseline.
#
# Needs OSS CAD Suite (https://github.com/YosysHQ/oss-cad-suite-build):
#   OSS=~/tools/oss-cad-suite-20261112/oss-cad-suite bash scripts/run_fmax.sh
# Results go to fpga/results/ ; summarise with:  python3 scripts/summarize_fmax.py
# =============================================================================
set -e
cd "$(dirname "$0")/.."
OSS="${OSS:-$HOME/tools/oss-cad-suite-20261112/oss-cad-suite}"
YOSYS="$OSS/bin/yosys"
NEXTPNR="$OSS/bin/nextpnr-ecp5"
OUT=fpga/results
mkdir -p "$OUT"

python3 scripts/rvasm.py fpga/fpga_demo.s
RTL=$(ls rtl/*.v | tr '\n' ' ')

run() {   # name  use_pipeline(1/0)
  name=$1; pipe=$2
  echo ">>> $name: synthesis"
  nice -n 15 "$YOSYS" -q -l "$OUT/$name.yosys.log" -p "
    read_verilog -Irtl rtl/riscv_defines_n.vh $RTL fpga/fpga_top.v
    chparam -set USE_PIPELINE $pipe fpga_top
    synth_ecp5 -top fpga_top -json $OUT/$name.json
    tee -o $OUT/$name.utilization.txt stat"
  echo ">>> $name: place & route"
  nice -n 15 "$NEXTPNR" --85k --package CABGA381 --json "$OUT/$name.json" \
      --lpf-allow-unconstrained --freq 25 --timing-allow-fail --seed 1 \
      --report "$OUT/$name.report.json" > "$OUT/$name.nextpnr.log" 2>&1
  grep -E "Max frequency for clock" "$OUT/$name.nextpnr.log" | tail -1 | sed "s/^/    $name: /"
}

run pipeline     1
run single_cycle 0
echo "Done. Logs in $OUT/"
