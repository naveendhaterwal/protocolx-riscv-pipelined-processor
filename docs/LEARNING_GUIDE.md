# ProtocolX — Learning Guide

**A 5-stage pipelined RISC-V (RV32I) processor, a single-cycle baseline, and how we measured them**

This guide explains the whole project in simple language: what we built, how each part works, which problems we faced, why we chose each design, and what the other options were. Read it once top to bottom, then use it as a reference before your viva.

---

## Contents

1. [The big picture](#1-the-big-picture)
2. [Map of the files](#2-map-of-the-files)
3. [Follow one instruction through the pipeline](#3-follow-one-instruction-through-the-pipeline)
4. [Hazards: the heart of the project](#4-hazards-the-heart-of-the-project)
5. [The single-cycle baseline](#5-the-single-cycle-baseline)
6. [How we tested it](#6-how-we-tested-it)
7. [Results](#7-results)
8. [Problems we faced, and how we solved them](#8-problems-we-faced-and-how-we-solved-them)
9. [What the course asked for, and what we did](#9-what-the-course-asked-for-and-what-we-did)
10. [How to run everything](#10-how-to-run-everything)
11. [Viva questions with answers](#11-viva-questions-with-answers)
12. [Glossary](#12-glossary)

---

## 1. The big picture

### What is a processor?
A processor repeats one loop forever:

1. **Fetch** the next instruction from memory (its address is in the **PC**, the program counter).
2. **Decode** it: what operation, which registers?
3. **Execute** it: add, compare, compute an address…
4. **Memory**: read or write data memory (only loads and stores).
5. **Write back** the result into a register.

### What is RISC-V?
RISC-V is a free, open **instruction set**: the list of instructions a processor understands and what each one does. We implement **RV32I**, the 32-bit base integer set: add, subtract, and/or/xor, shifts, comparisons, load word (`LW`), store word (`SW`), branches, jumps, and two helpers (`LUI`, `AUIPC`) for building big constants and addresses.

### What is pipelining? (the laundry example)
Washing, drying and folding one load takes 3 hours. Three loads one after another take 9 hours. But while load 1 is in the dryer, load 2 can already be in the washer. With overlap, three loads take 5 hours, and after that one load finishes **every hour**.

A processor does the same. We cut the work into 5 stages (IF, ID, EX, MEM, WB) and put a **pipeline register** between each pair. Every clock cycle each instruction moves one stage forward, so up to 5 instructions are in flight at once.

- **Single-cycle processor:** 1 instruction per cycle, but the cycle must be long enough for all 5 steps.
- **Pipelined processor:** ideally still 1 instruction per cycle, but each cycle only has to fit **one** stage, so the clock can be faster.

The catch is **hazards**: situations where the next instruction cannot go ahead yet. Most of this project is about handling them.

### Two numbers to remember
- **CPI** (cycles per instruction) = cycles ÷ instructions. The ideal pipeline has CPI 1.0. Stalls and flushes push it above 1. **IPC** = 1 ÷ CPI.
- **Execution time = instructions × CPI × clock period.** Pipelining makes CPI a bit worse but the clock period much better. Our job in Phase II was to measure whether the trade is worthwhile (it is: 1.12× to 1.30× faster).

---

## 2. Map of the files

| File | What it does |
|---|---|
| `rtl/riscv_core_n.v` | **Top level**: connects the 5 stages and 4 pipeline registers |
| `rtl/riscv_defines_n.vh` | Constants: opcodes, ALU operation codes |
| `rtl/control_unit_ar.v` | Decodes an instruction into control signals |
| `rtl/reg_file_ar.v` | 32 registers (`x0` is always 0) |
| `rtl/imm_gen_ar.v` | Builds the constant stored inside an instruction (the *immediate*) |
| `rtl/alu_s.v` | Add, subtract, logic, shifts, comparisons |
| `rtl/execution_unit_s.v` | EX stage: forwarding multiplexers, ALU, branch check, target address |
| `rtl/hazard_unit_s.v` | Decides forwarding, load-use stall and flush |
| `rtl/pipe_if_id_n.v` … `pipe_mem_wb_a.v` | The 4 pipeline registers |
| `rtl/instruction_memory_n.v`, `data_memory_ar.v` | Program memory (loaded from a `.hex` file) and data RAM |
| `rtl/single_cycle_core_n.v` | **Baseline** core for comparison |
| `testbench/tb_*.v` | Testbenches (Section 6) |
| `testbench/programs/*.s` | Test and benchmark programs written in assembly |
| `scripts/rvasm.py` | Our assembler: assembly text → `.hex` |
| `scripts/gen_isa_test.py` | Generates the 146-test self-checking program |
| `scripts/run_sim.sh`, `run_benchmarks.sh` | Run everything / run the benchmarks |
| `scripts/run_fmax.sh`, `summarize_fmax.py` | Real clock-speed measurement (Yosys + nextpnr) |
| `fpga/` | Board-level top, demo program and FPGA results |

---

## 3. Follow one instruction through the pipeline

Take `add x3, x1, x2` (x3 = x1 + x2):

| Cycle | Stage | What happens | Module |
|---|---|---|---|
| 1 | **IF** | The PC gives the address and instruction memory returns `0x002081b3`. PC becomes PC + 4. | `instruction_memory` |
| 2 | **ID** | The control unit sees opcode `0110011` (register-register) and says "ADD, write a register". The register file reads x1 and x2. | `control_unit`, `reg_file` |
| 3 | **EX** | The ALU adds the two values. If x1 or x2 was just produced by an earlier instruction, a forwarding multiplexer picks the newer value. | `execution_unit`, `hazard_unit` |
| 4 | **MEM** | Nothing to do (not a load or store); the result passes through. | — |
| 5 | **WB** | The result is written into x3. | `reg_file` |

At the end of every cycle, everything an instruction needs later is saved in the next pipeline register: the data (values, register numbers) **and** the control signals (does it write a register? is it a load?). Each instruction carries its own instructions with it down the pipeline.

- **A load** (`lw x5, 8(x1)`): EX computes the address x1 + 8, MEM reads data memory, WB writes x5.
- **A branch** (`beq x1, x2, label`): EX compares x1 and x2 and computes the target. If the branch is taken, the PC jumps there and the two instructions fetched after it are thrown away (Section 4.3).

---

## 4. Hazards: the heart of the project

### 4.1 Data hazard (RAW: read after write)
```
add x1, x2, x3     # writes x1 in WB (cycle 5)
sub x4, x1, x5     # needs x1 in EX (cycle 4)  -> too early!
```
**Our solution: forwarding (bypassing).** The answer already exists at the end of EX; it just is not in the register file yet. The hazard unit compares register numbers. If the instruction in EX/MEM or MEM/WB is writing the register we need, a multiplexer takes the value from there. EX/MEM has priority because it holds the newer value. `x0` is never forwarded (it is always 0).

| Option | Idea | Why not |
|---|---|---|
| Stall until the value is written | Wait 2–3 cycles | Very slow: dependencies are everywhere |
| Compiler inserts NOPs | A software problem | Wastes cycles and ties the program to one hardware design |
| **Forwarding** ✅ | Grab the value early | A few comparators and multiplexers; no cycles lost |

### 4.2 Load-use hazard
```
lw  x1, 0(x2)      # the data only exists at the END of MEM
add x3, x1, x1     # needs it at the START of EX -> impossible even with forwarding
```
**Solution: stall for 1 cycle.** The hazard unit holds the PC and the IF/ID register (`pc_write = 0`, `if_id_write = 0`) and puts a bubble (a do-nothing instruction) into ID/EX (`id_ex_flush = 1`). One cycle later, forwarding from MEM/WB works.

*Alternative:* a compiler can reorder instructions so something useful sits between the load and its use. We do it in hardware so every program is correct.

### 4.3 Control hazard (branches and jumps)
We only know a branch's real outcome in **EX**. By then, the two instructions after it have already been fetched. If the branch is taken they are on the wrong path, so we **flush** them (turn them into bubbles) and fetch from the target. That costs **2 cycles** per taken branch or jump. Our policy is "always guess not taken": a branch that falls through costs nothing.

| Option | Penalty | Cost |
|---|---|---|
| Always not-taken (**ours**) | 2 cycles for every taken branch | free |
| Resolve branches in ID instead of EX | 1 cycle | needs comparators and forwarding in ID, which makes ID slower |
| Dynamic branch prediction | ≈ 0 for well-predicted branches | extra tables and logic (it is a separate project in the course) |

### 4.4 Why exactly 5 stages?
It is the classic RISC design from Patterson and Hennessy:
- each stage has one clear job and roughly equal work, so the clock is set by a short stage;
- memory has its own stage, so loads and stores do not lengthen the ALU stage;
- it is deep enough to show real hazards, and simple enough for a student project.

More stages (8–20 in real CPUs) give a faster clock but bigger penalties for flushes and harder hazard handling.

### 4.5 The cycle model
Every extra cycle has a known cause, so total cycles can be predicted:

> **cycles = N + 4 + S + 2·T**
> N = instructions executed, 4 = filling the pipeline at the start, S = load-use stall cycles, T = taken branches and jumps.

Example, `sum` benchmark: 654 + 4 + 64 + 2×126 = **974**, exactly what the simulation measures. We check this on every benchmark.

---

## 5. The single-cycle baseline

The course says to verify a single-cycle datapath first and to compare against a baseline. `rtl/single_cycle_core_n.v` is built from the **same modules** (control unit, execution unit, register file, immediate generator, memories) but with **no pipeline registers, no forwarding and no hazards**. Every instruction finishes in one (long) cycle, so CPI = 1 exactly.

Why not just trust the pipeline's own CPI? Because CPI alone can mislead: the pipeline has a **higher** CPI but a **shorter** clock period. Only *cycles × clock period* tells the truth.

One detail: the register file has a "write-through bypass" (a register being written this cycle is read as the new value). In the pipeline this removes a hazard. In a single-cycle design it would create a combinational loop (the value written depends on the value read in the same cycle), so it is a parameter (`BYPASS`) and is switched off there.

---

## 6. How we tested it

| Level | Testbench | What it checks |
|---|---|---|
| Unit | `tb_alu`, `tb_reg_file`, `tb_hazard_unit` | One module alone |
| Pipeline | `tb_riscv_core`, `tb_riscv_hazard`, `tb_riscv_mem`, `tb_riscv_branch`, `tb_riscv_subset` | Small programs, register results, one exact cycle count |
| Instruction test | `tb_programs` / `tb_single_cycle` + `isa_test.s` | **146 generated tests**: every RV32I instruction with edge values, on both designs |
| Benchmarks | same two testbenches + `bench_*.s` | 4 real programs on both designs, self-checking |

### Techniques worth knowing
- **Self-checking programs.** Each program checks its own results and stores `1` (pass) or a failure code to the last word of data RAM (address `0xFFC`). The testbench watches that address, so nobody has to read waveforms to know whether it passed.
- **A golden model.** `gen_isa_test.py` contains a tiny Python model of every instruction. The expected answers come from Python, so we never hand-calculate (or mistype) hundreds of values.
- **Our own assembler.** The full GCC toolchain is a huge install and outputs files we would still have to convert. A ~250-line Python assembler is easy to read. We checked it bit for bit against hand-encoded programs and known encodings, and it refuses anything the hardware does not support.
- **Mutation testing.** To prove a test can fail, break the hardware on purpose and check the tests notice. We inverted BNE, made SRA behave like SRL, and disabled forwarding. Each time the suite failed and named the broken instruction.
- **Exact cycle counts.** The suite asserts exact cycle counts (the 7-instruction subset takes exactly 38 cycles; the benchmarks must match the cycle model). If anyone changes the hazard logic, the count changes and the test fails.

---

## 7. Results

### 7.1 Benchmarks (measured in simulation)
| Benchmark | N | Pipeline cycles | CPI | IPC | Stalls | Flushes |
|---|---|---|---|---|---|---|
| fib (Fibonacci 30) | 160 | 222 | 1.387 | 0.721 | 0 | 29 |
| sum (array of 64) | 654 | 974 | 1.489 | 0.671 | 64 | 126 |
| sort (bubble sort of 32) | 3,973 | 6,224 | 1.567 | 0.638 | 527 | 860 |
| matmul (8×8, shift-and-add) | 21,742 | 29,326 | 1.349 | 0.741 | 0 | 3,790 |

The single-cycle core takes exactly N cycles (CPI 1.000). The pipeline's extra cycles are the 4-cycle fill, load-use stalls and branch flushes. Flushes are the biggest part, because loops are made of taken branches.

### 7.2 Real clock speed (place-and-route on an FPGA chip)
Vivado (for Xilinx chips) does not run on macOS, so we used the open-source flow **Yosys → nextpnr** on a Lattice **ECP5-85F** (`make fpga`). That gives a real post-place-and-route maximum clock frequency without any board. A board-level top (`fpga/fpga_top.v`) runs `fpga/fpga_demo.s`, a program that uses every instruction, so the tools cannot delete any hardware.

| Design | Fmax | LUT4 | Flip-flops |
|---|---|---|---|
| 5-stage pipeline | **67.8 MHz** | 5,100 | 1,541 |
| Single-cycle baseline | 38.8 MHz | 5,161 | 722 |

### 7.3 What it means
- **The pipeline's clock is 1.75× faster**, but it needs 1.35–1.57× more cycles, so programs finish **1.12× to 1.30× sooner**: fib 1.26×, sum 1.17×, sort 1.12×, matmul 1.30×.
- **The gain is modest** because "always not-taken" wastes 2 cycles on every taken branch. Branch prediction would improve this.
- **The pipeline has about twice the flip-flops** (its pipeline registers) but almost the same logic.
- **The critical path is the data-memory read in the MEM stage**, in both designs.
- **Absolute MHz depends on the chip.** ECP5 numbers are not Artix-7 numbers; the comparison between our two designs is what matters.

---

## 8. Problems we faced, and how we solved them

| # | Problem | How we found it | Fix | Lesson |
|---|---|---|---|---|
| 1 | Design passed simulation but **did not synthesize** (`pipe_id_ex_a.v`) | Ran Yosys: "Multiple edge sensitive events" | Separate `if (!rst_n)` from `else if (flush)` | Simulation ≠ hardware. An async-reset branch may only test the reset signal. |
| 2 | **BNE was never tested** | Broke BNE on purpose; all tests still passed | Added a BNE loop test, then the 146-test program | Coverage must be checked, not assumed |
| 3 | Test script printed **SUCCESS even when tests failed** | Mutation runs showed failures plus a success banner | The script now searches the log for failures and exits 1 | `vvp` exits 0 even when checks fail |
| 4 | Synthesis reported only **103 cells** for a whole CPU | The number was impossibly small | Black-box the instruction memory for area runs | An empty ROM makes every instruction constant, so synthesis deletes the datapath |
| 5 | The FPGA run **optimised the whole CPU away** (21 cells, "no timing paths") | Synthesised the instruction memory alone: 0 cells | The NOP-fill `for` loop in `instruction_memory_n.v` turned into memory *write* ports and the program was lost. It is now inside `` `ifndef SYNTHESIS `` | Code that is harmless in simulation can mean something else to a synthesis tool |
| 6 | "Logic loop" warnings for the single-cycle core | Read the loop path: it went through the register-file bypass mux | The bypass is built with a `generate` block, so with `BYPASS = 0` that hardware does not exist | Use `generate` to remove hardware, not `parameter && …` |
| 7 | The data RAM was built from flip-flops | A reset loop cleared all 1,024 words in one cycle | Removed the loop; the RAM starts as zeros in simulation and maps to RAM resources | Reset loops over memories are expensive on an FPGA |
| 8 | Measured instruction count was **one too high** | Compared three independent counts | Sample 1 ns **after** the clock edge | At the edge itself, flip-flops have not updated yet |

---

## 9. What the course asked for, and what we did

From the course project document (Project 3):

| Requirement | Status |
|---|---|
| 5-stage pipeline (IF, ID, EX, MEM, WB) with pipeline registers | ✅ |
| Subset ADD, SUB, ADDI, LW, SW, BEQ, BNE | ✅ (we implement the full RV32I base set except byte/half-word loads and stores, fences and system instructions) |
| First verify a single-cycle datapath, compare against a baseline | ✅ `single_cycle_core_n.v` |
| Benchmark programs, CPI / IPC | ✅ 4 benchmarks |
| Waveforms from a simulator | ✅ `simulation/*.vcd` |
| Synthesis with resources and maximum frequency | ✅ Yosys + nextpnr (ECP5) |
| Block diagram, report, live demonstration | ✅ a simulation demonstration; the document asks for an FPGA only "where available" |

Things that are outside the project specification, so the final design does **not** include them: exception handling and interrupts (CSRs), the multiply/divide extension, dynamic branch prediction (its own project in the course), and memory-mapped I/O. They are listed only as ideas for later, never claimed as features. (Earlier experiments with some of them are still in the git history.)

---

## 10. How to run everything

Tools: Icarus Verilog (`iverilog`, `vvp`), Python 3. Optional: Yosys, GTKWave.

```bash
make test
```
Runs everything: unit tests, pipeline tests, the instruction test on both designs, and the benchmarks. Ends with "ALL VERIFICATION SUITES COMPLETED SUCCESSFULLY" or "VERIFICATION FAILED".

```bash
make bench
```
Runs the four benchmarks on both designs and prints CPI, IPC and the cycle-model check.

```bash
python3 scripts/rvasm.py myprog.s
```
Assembles your own program into `myprog.hex`. Your program must end by storing `1` to address `0xFFC` (see `testbench/programs/bench_fib.s`). Run it on the pipeline with:
```bash
iverilog -g2012 -Irtl '-Ptb_programs.PROG="myprog.hex"' -o sim.vvp rtl/*.v testbench/tb_programs.v && vvp sim.vvp
```
Add `+vcd=out.vcd` after `vvp sim.vvp` to record a waveform, then open it in GTKWave.

```bash
make synth      # Yosys area estimate
make fpga       # real Fmax (needs OSS CAD Suite: https://github.com/YosysHQ/oss-cad-suite-build)
```

---

## 11. Viva questions with answers

**Q: Why does a pipeline have CPI above 1 if it finishes one instruction per cycle?**
A: Only in the ideal case. A load-use hazard adds 1 cycle, every taken branch or jump wastes 2, and filling the pipeline at the start adds 4. Our measured CPI is 1.35 to 1.57.

**Q: What is forwarding and when does it not work?**
A: Taking a result from a pipeline register before it is written back. It cannot help a load followed immediately by its use, because the loaded value only exists at the end of MEM. So we stall one cycle.

**Q: Why is the branch penalty 2 cycles?**
A: Branches are resolved in EX, the third stage. By then two younger instructions (in IF and ID) have been fetched. If the branch is taken, both are flushed.

**Q: Why build a single-cycle processor too?**
A: The course asks for a baseline comparison, and CPI alone can mislead. The pipeline has a higher CPI but a faster clock; only cycles × clock period shows whether it is really faster.

**Q: What is your processor's maximum clock frequency?**
A: On a Lattice ECP5 FPGA, measured after place-and-route with nextpnr: 67.8 MHz for the pipeline and 38.8 MHz for the single-cycle core, so 1.75× faster. The critical path is the data-memory read.

**Q: Why ECP5 and not Artix-7?**
A: Vivado, needed for Xilinx chips, does not run on macOS, and we had no board. Yosys and nextpnr give real timing for ECP5 without a board. The absolute MHz would differ on Artix-7, but the comparison between our two designs is still valid.

**Q: How much faster is the pipeline in real time?**
A: 1.12× to 1.30× on our four benchmarks. Execution time = cycles ÷ Fmax. The pipeline needs more cycles but each is much shorter.

**Q: How can you be sure your tests actually test something?**
A: Mutation testing. We deliberately broke BNE, SRA and forwarding, and each time the suite failed and named the broken instruction. We also assert exact cycle counts, so even a one-cycle change in the hazard logic is detected.

**Q: How do the programs report their result?**
A: Each program checks its own answer and stores 1 (pass) or a failure code to the last word of data RAM. The testbench watches that address.

**Q: Why did you write your own assembler?**
A: Our programs are small. A 250-line Python assembler is easy to read and change, while the GCC toolchain is a large install and outputs formats we would still have to convert. We verified it against known encodings, and it rejects instructions the hardware does not support.

**Q: How is a load-use stall implemented?**
A: The hazard unit sees a load in EX whose destination matches a source register of the instruction in ID. It sets `pc_write = 0` and `if_id_write = 0` to hold the PC and IF/ID, and `id_ex_flush = 1` to insert a bubble.

**Q: What was the hardest bug?**
A: A design that simulated correctly but would not synthesize, because the reset and the flush were tested together inside an asynchronous-reset block. Simulation accepts that; synthesis does not. Later, a simulation-only memory-fill loop made the FPGA tools delete the entire CPU. Both taught us that simulation passing does not mean the hardware is right.

**Q: What would you improve next?**
A: Branch prediction to cut the 2-cycle cost of a taken branch (it would help CPI most), and a faster memory path, since the data-memory read limits the clock.

---

## 12. Glossary

| Term | Meaning |
|---|---|
| **Bubble** | An empty slot in the pipeline (does nothing) |
| **Stall** | Holding instructions in place for a cycle |
| **Flush** | Throwing away wrongly fetched instructions (turning them into bubbles) |
| **Forwarding / bypassing** | Using a result before it is written to the register file |
| **Hazard** | A reason the next instruction cannot proceed normally (data, control, structural) |
| **CPI / IPC** | Cycles per instruction / instructions per cycle (IPC = 1 ÷ CPI) |
| **Immediate** | A constant stored inside the instruction |
| **Sign extension** | Copying the top bit to fill a wider number, so a negative number stays negative |
| **LUT** | Look-up table, the basic logic cell of an FPGA |
| **Synthesis** | Turning Verilog into a netlist of real gates or LUTs |
| **Place and route** | Choosing where each cell sits on the chip and how it is wired |
| **Fmax** | The highest clock frequency the design can run at |
| **Testbench** | Verilog code that drives and checks the design in simulation |
| **Mutation testing** | Breaking the design on purpose to check that the tests notice |
