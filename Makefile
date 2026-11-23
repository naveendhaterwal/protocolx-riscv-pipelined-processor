# =============================================================================
# Project:     ProtocolX RISC-V 5-Stage Pipelined Processor
# File:        Makefile
# Description: Simple build automation (Icarus Verilog, Python 3, Yosys).
#                make test           run the complete verification suite
#                make bench          benchmarks: pipeline vs single-cycle (CPI, IPC)
#                make test_programs  generated RV32I instruction test, both designs
#                make synth          Yosys synthesis: area numbers
#                make fpga           real maximum clock frequency (needs OSS CAD Suite)
#                make clean
# =============================================================================

IV = iverilog
VVP = vvp
IVFLAGS = -g2012 -Irtl
RTL = rtl/riscv_defines_n.vh rtl/*.v

.PHONY: all test test_alu test_core test_hazard test_mem test_branch test_subset \
        asm test_programs bench synth fpga clean

all: test

test:
	@bash scripts/run_sim.sh

# ---- single testbenches ------------------------------------------------------
test_alu:
	$(IV) $(IVFLAGS) -o simulation/tb_alu.vvp rtl/alu_s.v testbench/tb_alu.v
	$(VVP) simulation/tb_alu.vvp
	@rm -f simulation/tb_alu.vvp

test_core:
	$(IV) $(IVFLAGS) -o simulation/tb_riscv_core.vvp $(RTL) testbench/tb_riscv_core.v
	$(VVP) simulation/tb_riscv_core.vvp
	@rm -f simulation/tb_riscv_core.vvp

test_hazard:
	$(IV) $(IVFLAGS) -o simulation/tb_riscv_hazard.vvp $(RTL) testbench/tb_riscv_hazard.v
	$(VVP) simulation/tb_riscv_hazard.vvp
	@rm -f simulation/tb_riscv_hazard.vvp

test_mem:
	$(IV) $(IVFLAGS) -o simulation/tb_riscv_mem.vvp $(RTL) testbench/tb_riscv_mem.v
	$(VVP) simulation/tb_riscv_mem.vvp
	@rm -f simulation/tb_riscv_mem.vvp

test_branch:
	$(IV) $(IVFLAGS) -o simulation/tb_riscv_branch.vvp $(RTL) testbench/tb_riscv_branch.v
	$(VVP) simulation/tb_riscv_branch.vvp
	@rm -f simulation/tb_riscv_branch.vvp

test_subset:
	$(IV) $(IVFLAGS) -o simulation/tb_riscv_subset.vvp $(RTL) testbench/tb_riscv_subset.v
	$(VVP) simulation/tb_riscv_subset.vvp
	@rm -f simulation/tb_riscv_subset.vvp

# ---- assembler, instruction test, benchmarks ----------------------------------
# asm: regenerate isa_test.s and assemble every .s program to .hex
asm:
	@python3 scripts/gen_isa_test.py
	@for f in testbench/programs/*.s; do python3 scripts/rvasm.py $$f; done

test_programs: asm
	$(IV) $(IVFLAGS) -Ptb_programs.PROG=\"testbench/programs/isa_test.hex\" -o simulation/tb_programs.vvp $(RTL) testbench/tb_programs.v
	@$(VVP) -n simulation/tb_programs.vvp | grep -E "RESULT|FAIL"
	$(IV) $(IVFLAGS) -Ptb_single_cycle.PROG=\"testbench/programs/isa_test.hex\" -o simulation/tb_programs.vvp $(RTL) testbench/tb_single_cycle.v
	@$(VVP) -n simulation/tb_programs.vvp | grep -E "RESULT|FAIL"
	@rm -f simulation/tb_programs.vvp

bench: asm
	@bash scripts/run_benchmarks.sh

# ---- synthesis -----------------------------------------------------------------
# Yosys (Xilinx 7-series mapping). The instruction memory is a black box so its
# contents are not constant-folded away; numbers are Yosys estimates, not Vivado.
synth:
	@echo "Synthesising riscv_core with Yosys (synth_xilinx, xc7)..."
	yosys -q -l synth/synth_report.log -p "read_verilog -Irtl rtl/riscv_defines_n.vh synth/imem_blackbox.v $$(ls rtl/*.v | grep -v -e instruction_memory -e single_cycle_core | tr '\n' ' '); hierarchy -top riscv_core -chparam DMEM_DEPTH 256; synth_xilinx -top riscv_core -flatten -family xc7; tee -o synth/utilization.txt stat"
	@echo "Synthesis OK. Utilization written to synth/utilization.txt"

# Real place-and-route + maximum clock frequency (Lattice ECP5, no board needed).
fpga:
	@bash scripts/run_fmax.sh
	@python3 scripts/summarize_fmax.py

clean:
	@echo "Cleaning up generated vvp files..."
	@rm -f simulation/*.vvp *.vvp
	@echo "Clean completed."
