#!/usr/bin/env bash
# =============================================================================
# scripts/run_benchmarks.sh - run every testbench/programs/bench_*.hex on
#   (1) the single-cycle baseline  -> N = instructions executed (CPI = 1)
#   (2) the 5-stage pipeline       -> cycles, stalls, flushes
# and print a table with CPI, IPC and a check of the cycle model
#       cycles = N + 4 (pipeline fill) + stalls + 2 * flushes
# Also writes docs/figures/benchmark_results.csv (used by the charts / FPGA summary).
# Usage:  bash scripts/run_benchmarks.sh        (or:  make bench)
# =============================================================================
set -e
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CSV=docs/figures/benchmark_results.csv
mkdir -p docs/figures
echo "benchmark,instructions,pipeline_cycles,cpi,ipc,stalls,flushes" > "$CSV"

printf "%-14s | %7s | %9s | %5s | %5s | %6s | %7s | %s\n" \
       "benchmark" "N" "pipe cyc" "CPI" "IPC" "stalls" "flushes" "N+4+S+2T"
for hex in testbench/programs/bench_*.hex; do
  name=$(basename "$hex" .hex)
  iverilog -g2012 -Irtl "-Ptb_single_cycle.PROG=\"$hex\"" -o "$TMP/sc.vvp" rtl/*.v testbench/tb_single_cycle.v
  sc=$(vvp -n "$TMP/sc.vvp" | grep -E "RESULT|FAIL")
  iverilog -g2012 -Irtl "-Ptb_programs.PROG=\"$hex\"" -o "$TMP/p.vvp" rtl/*.v testbench/tb_programs.v
  p=$(vvp -n "$TMP/p.vvp" | grep -E "RESULT|FAIL")
  echo "$sc" | grep -q "RESULT PASS" || { echo "[FAIL] $name on single-cycle: $sc"; exit 1; }
  echo "$p"  | grep -q "RESULT PASS" || { echo "[FAIL] $name on pipeline: $p"; exit 1; }
  N=$(echo "$sc" | sed -E 's/.*instructions=([0-9]+).*/\1/')
  C=$(echo "$p"  | sed -E 's/.* cycles=([0-9]+) .*/\1/')
  S=$(echo "$p"  | sed -E 's/.*stalls=([0-9]+).*/\1/')
  T=$(echo "$p"  | sed -E 's/.*flushes=([0-9]+).*/\1/')
  model=$((N + 4 + S + 2 * T))
  [ "$model" -eq "$C" ] && ok="$model = OK" || ok="$model MISMATCH"
  cpi=$(awk -v c="$C" -v n="$N" 'BEGIN{printf "%.3f", c/n}')
  ipc=$(awk -v c="$C" -v n="$N" 'BEGIN{printf "%.3f", n/c}')
  printf "%-14s | %7d | %9d | %5s | %5s | %6d | %7d | %s\n" "$name" "$N" "$C" "$cpi" "$ipc" "$S" "$T" "$ok"
  echo "${name#bench_},$N,$C,$cpi,$ipc,$S,$T" >> "$CSV"
done
