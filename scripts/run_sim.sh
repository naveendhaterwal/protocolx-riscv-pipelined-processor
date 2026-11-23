#!/usr/bin/env bash
# =============================================================================
# Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
# Script:     scripts/run_sim.sh
# Description: Runs the complete verification suite with Icarus Verilog:
#                1-3   unit tests (ALU, register file, hazard unit)
#                4-8   full-pipeline tests (arithmetic, forwarding, load/store +
#                      load-use stall, branches + flush, 7-instruction subset)
#                9-10  generated RV32I instruction test, on BOTH the pipeline
#                      and the single-cycle baseline
#                11    four benchmarks, both designs, cycle-model check
#              Output goes to the screen and to simulation/simulation_results.log.
#              Exits 1 (and says so) if any check fails.
# Usage:      bash scripts/run_sim.sh        (or:  make test)
# =============================================================================

set -e
cd "$(dirname "${BASH_SOURCE[0]}")/.."          # always run from the repo root

LOG=simulation/simulation_results.log
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "================================================================================" > "$LOG"
echo "           PROTOCOLX RISC-V 5-STAGE PROCESSOR - FULL VERIFICATION SUITE         " >> "$LOG"
echo "                       Execution Date: $(date)                                  " >> "$LOG"
echo "================================================================================" >> "$LOG"

# run_tb "title" "verilog files" -> compile and run, show and log the output
run_tb() {
  echo -e "\n>>> $1" | tee -a "$LOG"
  iverilog -g2012 -Irtl -o "$TMP/t.vvp" $2
  vvp -n "$TMP/t.vvp" | tee -a "$LOG"
}

RTL="rtl/riscv_defines.vh rtl/*.v"

run_tb "1. ALU Unit Test..."                      "rtl/alu.v testbench/tb_alu.v"
run_tb "2. Register File Unit Test..."            "rtl/reg_file.v testbench/tb_reg_file.v"
run_tb "3. Hazard Unit Test..."                   "rtl/hazard_unit.v testbench/tb_hazard_unit.v"
run_tb "4. Core Pipeline Arithmetic Test..."      "$RTL testbench/tb_riscv_core.v"
run_tb "5. Core RAW Data Hazard Forwarding Test..." "$RTL testbench/tb_riscv_hazard.v"
run_tb "6. Core Memory & Load-Use Stall Test..."  "$RTL testbench/tb_riscv_mem.v"
run_tb "7. Core Branch & Control Hazard Flush Test..." "$RTL testbench/tb_riscv_branch.v"
run_tb "8. Instruction Subset (ADD/SUB/ADDI/LW/SW/BEQ/BNE) & CPI Test..." "$RTL testbench/tb_riscv_subset.v"

echo -e "\n>>> 9. Assembling test programs (scripts/rvasm.py)..." | tee -a "$LOG"
python3 scripts/gen_isa_test.py | tee -a "$LOG"
for s in testbench/programs/*.s; do python3 scripts/rvasm.py "$s" | tee -a "$LOG"; done

echo -e "\n>>> 10. RV32I instruction test on the pipeline and on the single-cycle baseline..." | tee -a "$LOG"
iverilog -g2012 -Irtl "-Ptb_programs.PROG=\"testbench/programs/isa_test.hex\"" -o "$TMP/t.vvp" $RTL testbench/tb_programs.v
vvp -n "$TMP/t.vvp" | grep -E "RESULT|FAIL" | tee -a "$LOG"
iverilog -g2012 -Irtl "-Ptb_single_cycle.PROG=\"testbench/programs/isa_test.hex\"" -o "$TMP/t.vvp" $RTL testbench/tb_single_cycle.v
vvp -n "$TMP/t.vvp" | grep -E "RESULT|FAIL" | tee -a "$LOG"

echo -e "\n>>> 11. Benchmarks: pipeline vs single-cycle baseline (CPI, IPC, cycle-model check)..." | tee -a "$LOG"
bash scripts/run_benchmarks.sh | tee -a "$LOG"

# vvp exits 0 even when checks fail, so decide pass/fail from the logged results.
echo -e "\n================================================================================" | tee -a "$LOG"
if grep -qE "^\[FAIL\]|Failed = [1-9]|[1-9][0-9]* Failed|RESULT FAIL|MISMATCH" "$LOG"; then
    echo "           VERIFICATION FAILED - see [FAIL] lines above                         " | tee -a "$LOG"
    echo "================================================================================" | tee -a "$LOG"
    exit 1
fi
echo "           ALL VERIFICATION SUITES COMPLETED SUCCESSFULLY!                      " | tee -a "$LOG"
echo "================================================================================" | tee -a "$LOG"
