# =============================================================================
# Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
# File:       Makefile
# Description: Simple, student-friendly build automation for Icarus Verilog.
# =============================================================================

IV = iverilog
VVP = vvp
IVFLAGS = -g2012 -Irtl

.PHONY: all test test_core test_hazard test_mem test_branch test_alu test_subset asm test_programs bench synth clean

all: test

test:
	@echo "Running complete ProtocolX test suite..."
	@bash simulation/run_sim.sh

test_core:
	@echo "Running top-level core arithmetic test..."
	$(IV) $(IVFLAGS) -o simulation/tb_riscv_core.vvp rtl/riscv_defines.vh rtl/*.v testbench/tb_riscv_core.v
	$(VVP) simulation/tb_riscv_core.vvp
	@rm -f simulation/tb_riscv_core.vvp

test_hazard:
	@echo "Running RAW data hazard forwarding test..."
	$(IV) $(IVFLAGS) -o simulation/tb_riscv_hazard.vvp rtl/riscv_defines.vh rtl/*.v testbench/tb_riscv_hazard.v
	$(VVP) simulation/tb_riscv_hazard.vvp
	@rm -f simulation/tb_riscv_hazard.vvp

test_mem:
	@echo "Running data memory and load-use stall test..."
	$(IV) $(IVFLAGS) -o simulation/tb_riscv_mem.vvp rtl/riscv_defines.vh rtl/*.v testbench/tb_riscv_mem.v
	$(VVP) simulation/tb_riscv_mem.vvp
	@rm -f simulation/tb_riscv_mem.vvp

test_branch:
	@echo "Running branch and control hazard flush test..."
	$(IV) $(IVFLAGS) -o simulation/tb_riscv_branch.vvp rtl/riscv_defines.vh rtl/*.v testbench/tb_riscv_branch.v
	$(VVP) simulation/tb_riscv_branch.vvp
	@rm -f simulation/tb_riscv_branch.vvp

test_alu:
	@echo "Running ALU unit test..."
	$(IV) $(IVFLAGS) -o simulation/tb_alu.vvp rtl/alu.v testbench/tb_alu.v
	$(VVP) simulation/tb_alu.vvp
	@rm -f simulation/tb_alu.vvp

test_subset:
	@echo "Running full instruction subset (ADD/SUB/ADDI/LW/SW/BEQ/BNE) and CPI test..."
	$(IV) $(IVFLAGS) -o simulation/tb_riscv_subset.vvp rtl/riscv_defines.vh rtl/*.v testbench/tb_riscv_subset.v
	$(VVP) simulation/tb_riscv_subset.vvp
	@rm -f simulation/tb_riscv_subset.vvp

# ---- Phase II ---------------------------------------------------------------
# asm:           regenerate isa_test.s and assemble every program to .hex
# test_programs: run the RV32IM instruction test and the trap/interrupt test
# bench:         benchmarks on single-cycle vs pipeline (predictor off / on)
asm:
	@python3 tools/gen_isa_test.py
	@for f in testbench/programs/*.s; do python3 tools/rvasm.py $$f; done

test_programs: asm
	@for p in isa_test trap_test; do \
	  $(IV) $(IVFLAGS) -Ptb_programs.PROG=\"testbench/programs/$$p.hex\" -o simulation/tb_programs.vvp rtl/*.v testbench/tb_programs.v && \
	  $(VVP) -n simulation/tb_programs.vvp | grep -E "RESULT|FAIL"; done
	@rm -f simulation/tb_programs.vvp

bench: asm
	@bash tools/run_benchmarks.sh

# Synthesis check with Yosys (Xilinx 7-series mapping). Instruction memory is a
# black box so its contents are not constant-folded away; resource numbers are
# Yosys estimates, not Vivado post-implementation results.
synth:
	@echo "Synthesising riscv_core with Yosys (synth_xilinx, xc7)..."
	yosys -q -l synth/synth_report.log -p "read_verilog -Irtl rtl/riscv_defines.vh synth/imem_blackbox.v $$(ls rtl/*.v | grep -v -e instruction_memory -e single_cycle_core | tr '\n' ' '); hierarchy -top riscv_core -chparam DMEM_DEPTH 256; synth_xilinx -top riscv_core -flatten -family xc7; tee -o synth/utilization.txt stat"
	@echo "Synthesis OK. Utilization written to synth/utilization.txt"

clean:
	@echo "Cleaning up generated vvp and temporary simulation files..."
	@rm -f simulation/*.vvp *.vvp
	@echo "Clean completed."
