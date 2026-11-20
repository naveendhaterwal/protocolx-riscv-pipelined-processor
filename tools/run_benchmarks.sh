#!/usr/bin/env bash
# Runs every bench_*.hex on (1) the single-cycle baseline, (2) the pipeline with
# the branch predictor OFF and (3) ON, and prints a results table. Run from the
# repo root:  bash tools/run_benchmarks.sh
set -e
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
printf "%-14s | %-26s | %-26s | %-26s | %s\n" "benchmark" "single-cycle (cycles, CPI)" "pipeline, no predictor" "pipeline + 2-bit predictor" "mispredicts off -> on"
for hex in testbench/programs/bench_*.hex; do
  name=$(basename "$hex" .hex)
  iverilog -g2012 -Irtl "-Ptb_single_cycle.PROG=\"$hex\"" -o "$TMP/sc.vvp" rtl/*.v testbench/tb_single_cycle.v
  sc=$(vvp -n "$TMP/sc.vvp" | grep -E "RESULT|FAIL")
  row=()
  mp=()
  for bp in 0 1; do
    iverilog -g2012 -Irtl -Ptb_programs.BP=$bp "-Ptb_programs.PROG=\"$hex\"" -o "$TMP/p.vvp" rtl/*.v testbench/tb_programs.v
    r=$(vvp -n "$TMP/p.vvp" | grep -E "RESULT|FAIL")
    echo "$r" | grep -q "RESULT PASS" || { echo "[FAIL] $name bp=$bp: $r"; exit 1; }
    row+=("$(echo "$r" | sed -E 's/.* cycles=([0-9]+) .*/\1/') cyc, CPI $(echo "$r" | sed -E 's/.*CPI=([0-9.]+).*/\1/')")
    mp+=("$(echo "$r" | sed -E 's/.*mispredicts=([0-9]+).*/\1/')")
  done
  echo "$sc" | grep -q "RESULT PASS" || { echo "[FAIL] $name single-cycle: $sc"; exit 1; }
  scc=$(echo "$sc" | sed -E 's/.* cycles=([0-9]+) .*/\1/')
  printf "%-14s | %-26s | %-26s | %-26s | %s\n" "$name" "$scc cyc, CPI 1.000" "${row[0]}" "${row[1]}" "${mp[0]} -> ${mp[1]}"
done
rm -rf "$TMP"
