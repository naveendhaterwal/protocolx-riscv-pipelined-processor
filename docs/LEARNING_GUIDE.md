# ProtocolX — Learning Guide

**5-Stage Pipelined RISC-V Processor, Phase I + Phase II**

This guide explains the whole project in simple language: what we built, how each part works, which problems we faced, why we chose each design, and what the other options were. Read it top to bottom once, then use it as a reference before your viva.

---

## Contents

1. [The big picture](#1-the-big-picture)
2. [Map of the files](#2-map-of-the-files)
3. [Follow one instruction through the pipeline](#3-follow-one-instruction-through-the-pipeline)
4. [Phase I: the pipeline and its hazards](#4-phase-i-the-pipeline-and-its-hazards)
5. [Phase II: every new feature](#5-phase-ii-every-new-feature)
6. [How we tested it](#6-how-we-tested-it)
7. [Results](#7-results)
8. [Problems we faced, and how we solved them](#8-problems-we-faced-and-how-we-solved-them)
9. [What is still not done](#9-what-is-still-not-done)
10. [How to run everything](#10-how-to-run-everything)
11. [Viva questions with answers](#11-viva-questions-with-answers)
12. [Glossary](#12-glossary)

---

## 1. The big picture

### What is a processor?
A processor repeats one loop forever:

1. **Fetch** the next instruction from memory (its address is in the **PC**, program counter).
2. **Decode** it: what operation, which registers?
3. **Execute** it: add, compare, compute an address…
4. **Memory**: read or write data memory (only loads and stores).
5. **Write back** the result into a register.

### What is RISC-V?
RISC-V is a free, open **instruction set** — the list of instructions a processor understands and exactly what each one does. We implement:

| Part | What it adds | Phase |
|---|---|---|
| **RV32I** | 32-bit integer basics: add, sub, and/or/xor, shifts, compares, loads, stores, branches, jumps | I |
| **M** | multiply, divide, remainder | II |
| **Zicsr** | CSR instructions (control/status registers, used for traps and counters) | II |
| machine-mode traps | ECALL, EBREAK, MRET, illegal-instruction, timer and external interrupts | II |

### What is pipelining? (the laundry example)
Washing, drying and folding one load takes 3 hours. Doing 3 loads one after another takes 9 hours. But while load 1 is in the dryer, load 2 can already be in the washer. With overlap, 3 loads take 5 hours, and after that one load finishes **every hour**.

A processor works the same way. We cut the work into 5 stages (IF, ID, EX, MEM, WB) and put a **pipeline register** between each pair of stages. Every clock cycle, each instruction moves one stage forward, so up to 5 instructions are being worked on at the same time.

- **Single-cycle processor:** 1 instruction per cycle, but the cycle must be long enough for all 5 steps.
- **Pipelined processor:** ideally still 1 instruction per cycle, but each cycle only needs to be as long as **one** stage → a faster clock.

The catch is **hazards**: situations where the next instruction cannot go ahead yet. Most of this project is about handling them.

### Two numbers to remember
- **CPI** (cycles per instruction) = cycles ÷ instructions. Ideal pipeline = 1.0. Stalls and flushes push it above 1.
- **Execution time** = instructions × CPI × clock period. Pipelining makes CPI a bit worse but the clock period much better.

---

## 2. Map of the files

| File | What it does | Phase |
|---|---|---|
| `rtl/riscv_core.v` | **Top level**: connects all stages below | I + II |
| `rtl/riscv_defines.vh` | Constants: opcodes, ALU codes, memory map, CSR addresses | I + II |
| `rtl/control_unit.v` | Decodes an instruction into control signals | I + II |
| `rtl/reg_file.v` | 32 registers (x0 is always 0) | I |
| `rtl/imm_gen.v` | Builds the immediate (constant) from instruction bits | I |
| `rtl/alu.v` | Add, sub, logic, shifts, compares | I |
| `rtl/execution_unit.v` | EX stage: forwarding muxes, ALU, mul/div, branch check, target address | I + II |
| `rtl/hazard_unit.v` | Forwarding control, load-use stall, flush | I |
| `rtl/pipe_if_id.v` … `pipe_mem_wb.v` | The 4 pipeline registers | I + II |
| `rtl/instruction_memory.v` | Program memory (loaded from a `.hex` file) | I |
| `rtl/data_memory.v` | Data RAM with byte write-enables | I + II |
| `rtl/branch_predictor_2bit.v` | 16-entry table of 2-bit counters (Aditya) | II |
| `rtl/muldiv_unit.v` | RV32M multiply / divide / remainder | II |
| `rtl/mem_align_unit.v` | LB/LH/LBU/LHU: pick and extend a byte or half-word (Shagun) | II |
| `rtl/store_align_unit.v` | SB/SH: byte lanes and byte enables | II |
| `rtl/gpio_unit.v` | Memory-mapped input/output pins (Ritik) | II |
| `rtl/timer_unit.v` | Machine timer for timer interrupts | II |
| `rtl/csr_unit.v` | CSRs, exceptions, interrupts, MRET | II |
| `rtl/perf_counter.v` | Hardware cycle and instruction counters (Archit) | II |
| `rtl/single_cycle_core.v` | **Baseline** single-cycle core, for comparison | II |
| `tools/rvasm.py` | Our assembler: assembly text → `.hex` | II |
| `tools/gen_isa_test.py` | Generates the 234-test instruction test | II |
| `tools/run_benchmarks.sh` | Runs all benchmarks on all three designs | II |
| `testbench/tb_*.v` | Testbenches (see section 6) | I + II |
| `testbench/programs/*.s` | Test and benchmark programs | I + II |
| `synth/` | Synthesis helper and report | I + II |

---

## 3. Follow one instruction through the pipeline

Take `add x3, x1, x2` (x3 = x1 + x2):

| Cycle | Stage | What happens | Module |
|---|---|---|---|
| 1 | **IF** | PC gives the address, instruction memory gives `0x002081b3`. PC becomes PC + 4. | `instruction_memory`, PC register |
| 2 | **ID** | Control unit sees opcode `0110011` (R-type), funct3 `000`, funct7 `0000000` → "ADD, write a register". Register file reads x1 and x2. | `control_unit`, `reg_file` |
| 3 | **EX** | ALU adds the two values. If x1 or x2 was just changed by an earlier instruction, the forwarding mux takes the new value instead. | `execution_unit`, `hazard_unit` |
| 4 | **MEM** | Nothing to do (not a load/store); the result just passes through. | — |
| 5 | **WB** | Result written into x3. | `reg_file` |

At the end of every cycle, everything an instruction will need later is saved in the next pipeline register — data (values, register numbers) **and** control signals (does it write a register? is it a load?). That way each instruction carries its own "instructions to itself" down the pipeline.

**A load** (`lw x5, 8(x1)`): EX computes the address x1 + 8, MEM reads data memory, WB writes x5.
**A branch** (`beq x1, x2, label`): EX compares x1 and x2 and computes the target. If the guess made in IF was wrong, the PC is corrected (section 5.2).

---

## 4. Phase I: the pipeline and its hazards

### 4.1 Data hazard (RAW: read after write)
```
add x1, x2, x3     # writes x1 in WB (cycle 5)
sub x4, x1, x5     # needs x1 in EX (cycle 4)  -> too early!
```
**Our solution: forwarding (bypassing).** The answer already exists at the end of EX; it is just not in the register file yet. The hazard unit compares register numbers. If the instruction in EX/MEM or MEM/WB is writing the register we need, a multiplexer takes the value from there.

- Priority: EX/MEM first (it is the newer value), then MEM/WB.
- x0 is never forwarded (it is always 0).

**Other options:**
| Option | Idea | Why not |
|---|---|---|
| Stall until the value is written | Wait 2–3 cycles | Very slow: dependencies are everywhere |
| Compiler inserts NOPs | Software problem | Wastes cycles and program size; ties the program to one hardware design |
| **Forwarding** ✅ | Grab the value early | A few comparators and muxes; no lost cycles |

### 4.2 Load-use hazard
```
lw  x1, 0(x2)      # data only exists at the END of MEM
add x3, x1, x1     # needs it at the START of EX -> impossible even with forwarding
```
**Solution: stall for 1 cycle.** The hazard unit holds the PC and IF/ID, and puts a bubble (a do-nothing instruction) into ID/EX. Next cycle, forwarding from MEM/WB works.
*Alternative:* a compiler can reorder instructions to put something useful between the load and its use. We do it in hardware so every program is correct.

### 4.3 Control hazard (branches and jumps)
We only know a branch's real outcome in **EX**. By then, two more instructions were already fetched after it. If the branch is taken, those two are wrong: we **flush** them (turn them into bubbles) and fetch from the target. That costs **2 cycles**.

Phase I always guessed "not taken". Phase II added a predictor (section 5.2).

### 4.4 Why exactly 5 stages?
It is the classic RISC design (Patterson & Hennessy):
- each stage has one clear job and roughly equal work, so the clock is set by a short stage;
- memory is accessed in its own stage, so loads/stores don't lengthen the ALU stage;
- it is deep enough to show real hazards, and simple enough for a student project.

More stages (8–20 in real CPUs) give a faster clock but much bigger penalties for mispredictions and harder hazard handling.

---

## 5. Phase II: every new feature

### 5.1 The "valid" bit
**Problem:** bubbles (flushed or stalled slots) look like `addi x0, x0, 0`. For the new features we must know whether a stage holds a **real** instruction: the instruction counter must not count bubbles, and an interrupt must not be attached to a bubble (it has no meaningful PC).
**Solution:** every pipeline register got a `valid` bit. It is 1 when an instruction is fetched, and 0 after reset or flush.

### 5.2 Dynamic branch prediction (2-bit counters)
**Idea:** loops branch the same way most of the time. Remember what each branch did last time, and guess the same.

**The 2-bit counter** (Aditya's `branch_predictor_2bit.v`), one per table entry:
```
 Strongly NOT taken (00) <-> Weakly NOT taken (01) <-> Weakly taken (10) <-> Strongly taken (11)
         taken -> move right,   not taken -> move left.   Predict "taken" if the left bit is 1.
```
Why 2 bits and not 1? With 1 bit, a loop mispredicts **twice** per run (at the exit, and again at the next entry). With 2 bits, the single "not taken" at the loop exit only moves the counter to "weakly taken", so the next run is predicted correctly. That is called **hysteresis**.

**Where the target comes from (our design decision):** a predictor only says *whether* to jump, not *where*. Real CPUs use a **BTB** (branch target buffer), a table of remembered targets. We found a simpler trick: our instruction memory returns the instruction in the **same** cycle, so in IF we can already decode "is this a branch?" and compute `PC + immediate`. No BTB needed.

**How it fits the pipeline:**
1. **IF**: if the instruction is a branch and the counter says taken → next PC = target, else PC + 4. The guess (`pred_taken`) travels down the pipeline with the instruction.
2. **EX**: compare the guess with the real result. If they differ (**mispredict**), redirect the PC (to the target, or to PC + 4) and flush 2 instructions. Then update the counter.

**Other options:**
| Option | Accuracy | Cost |
|---|---|---|
| Always not-taken (Phase I) | poor for loops | free |
| Static "backward taken, forward not taken" | good for loops | tiny |
| 1-bit history | mispredicts twice per loop | tiny |
| **2-bit counters** ✅ | good | 16 × 2 bits |
| gshare / tournament (use global history) | best | bigger, more complex |
| Resolve branches in ID instead of EX | penalty 1 cycle instead of 2 | needs comparators + forwarding into ID: longer ID stage |

**Results** (section 7): mispredictions dropped from 126 to 4 in `bench_sum`, CPI from 1.49 to 1.12.

`BRANCH_PREDICTION` is a parameter (1 = on, 0 = off), so we can measure the effect.

### 5.3 RV32M: multiply and divide
`muldiv_unit.v` handles 8 instructions (`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`).

- **Multiply:** extend both inputs to 64 bits (signed or unsigned depending on the instruction), multiply once, take the low or high 32 bits.
- **Divide:** take absolute values, divide, then fix the sign.
- **Special cases the RISC-V spec defines** (no exception is raised):
  - divide by zero → quotient = −1 (all ones), remainder = the dividend;
  - −2³¹ ÷ −1 (overflow) → quotient = −2³¹, remainder = 0.

**Design choice: combinational (1 cycle).**
| Option | Speed of the instruction | Effect on the whole CPU |
|---|---|---|
| **Combinational** ✅ | 1 cycle | Very long logic path → lowers the max clock frequency for everything |
| Multi-cycle (e.g. 32 cycles, 1 bit per cycle) with a stall | 32 cycles | Short paths, faster clock, small area |
| Use FPGA DSP blocks for multiply | 1–3 cycles | Fast multiply; divide still needs its own design |

We chose combinational because it is the simplest correct design and our benchmarks rarely divide. The synthesis numbers (section 7) show its cost, and that makes a good Phase III improvement.

### 5.4 Byte and half-word loads and stores
Memory is made of 32-bit words. To support `LB`, `LH`, `LBU`, `LHU`, `SB` and `SH`:
- **Loads** (Shagun's `mem_align_unit.v`): read the whole word, pick the byte/half-word using address bits [1:0], then sign-extend (LB, LH) or zero-extend (LBU, LHU).
- **Stores** (`store_align_unit.v`): copy the byte into all four byte positions and switch on only one **byte enable**, so only that byte of the word changes.
- `data_memory.v` now has 4 byte-enables instead of one write-enable.
- `funct3` (which load/store) now travels to the MEM stage in EX/MEM.

We also **removed the reset loop** that cleared all 1024 words. Clearing a whole RAM in one cycle forces synthesis to build it from thousands of flip-flops. Without it, the FPGA tools use real RAM blocks.

**Not supported:** misaligned accesses (e.g. `lw` from address 0x101). Real CPUs either split them into two accesses or raise an exception. Our programs only use aligned addresses.

### 5.5 Memory-mapped I/O: GPIO and timer
How does a program turn on an LED? We give devices **addresses**. Normal `sw`/`lw` instructions to those addresses talk to the device instead of RAM:

| Address | Device | Read | Write |
|---|---|---|---|
| `0x80000000` | GPIO_OUT (LEDs) | last value | set the pins |
| `0x80000004` | GPIO_IN (switches) | pin values | — |
| `0x80000010/14` | mtime (timer, 64-bit) | current count | set count |
| `0x80000018/1C` | mtimecmp | value | set when to interrupt |
| `0x800000F0` | TOHOST (simulation only) | — | test result |

**Rule:** if address bit 31 is 1, it is a device, otherwise RAM. One wire decides, which keeps the decoder tiny.
*Alternative:* special I/O instructions (like x86 `in`/`out`). RISC-V uses memory-mapping: no new instructions, and every load/store works on devices.

### 5.6 CSRs, exceptions and interrupts (`csr_unit.v`)
**CSRs** (Control and Status Registers) are special registers for the operating system:

| CSR | Meaning |
|---|---|
| `mstatus` | bit 3 MIE = interrupts on/off; bit 7 MPIE = saved copy |
| `mie` | which interrupts are allowed (bit 7 timer, bit 11 external) |
| `mip` | which interrupts are waiting (read-only) |
| `mtvec` | address of the trap handler |
| `mepc` | where to return after the handler |
| `mcause` | why we trapped (11 ECALL, 3 EBREAK, 2 illegal instruction, 0x80000007 timer, 0x8000000B external) |
| `mscratch`, `mtval` | scratch space / extra information |
| `mcycle`, `minstret` | performance counters (from Archit's `perf_counter.v`) |

**A trap** = "stop what you are doing and run the handler." Causes:
- **exceptions** (caused by the instruction itself): ECALL, EBREAK, illegal instruction;
- **interrupts** (from outside): timer, external pin.

**What happens on a trap** (all in one clock cycle, when the instruction is in **EX**):
1. `mepc` ← PC of that instruction; `mcause` ← reason.
2. `MPIE` ← `MIE`, then `MIE` ← 0 (no interrupts inside the handler).
3. PC ← `mtvec`; the 2 younger instructions (IF, ID) are flushed, and the instruction in EX is cancelled (EX/MEM gets a bubble).
4. The handler finishes with **MRET**: PC ← `mepc`, `MIE` ← `MPIE`.

**Why in EX?** Older instructions (in MEM and WB) are allowed to finish, younger ones are thrown away. So the trap is **precise**: everything before `mepc` completed, nothing from `mepc` onward did. That is exactly what an operating system needs to resume a program correctly.

*Alternatives:* take traps in WB (also precise, but needs more state carried along the pipeline), or imprecise interrupts (simpler, but software can't safely resume — not acceptable for RISC-V).

### 5.7 Hardware performance counters
Archit's `perf_counter.v` counts cycles and **retired** instructions (a valid instruction leaving WB). Programs can read them as CSRs (`mcycle`, `minstret`). The testbench uses them to compute CPI, so our CPI numbers are measured **by the hardware itself**, not estimated.

### 5.8 Single-cycle baseline (`single_cycle_core.v`)
Reuses the same modules but without pipeline registers, hazards or forwarding. Every instruction takes exactly one long cycle (CPI = 1). We built it because the course asks for a comparison with a baseline, and because CPI alone can be misleading: the pipeline has a **higher** CPI but a **shorter** clock period.

One detail: the register file's same-cycle "write → read" bypass (useful in the pipeline) would create a combinational loop in a single-cycle design, so it is now a parameter (`BYPASS`).

---

## 6. How we tested it

| Level | Testbench | What it checks |
|---|---|---|
| Unit | `tb_alu`, `tb_reg_file`, `tb_hazard_unit`, `tb_mem_align_unit`, `tb_branch_predictor_2bit`, `tb_perf_counter`, `tb_gpio_unit` | One module alone |
| Pipeline (Phase I) | `tb_riscv_core`, `tb_riscv_hazard`, `tb_riscv_mem`, `tb_riscv_branch`, `tb_riscv_subset` | Small programs, register results, exact cycle counts |
| ISA (Phase II) | `tb_programs` + `isa_test.s` | **234 generated tests**: every RV32IM instruction + CSRs, edge values |
| Traps (Phase II) | `tb_programs` + `trap_test.s` | ECALL, EBREAK, illegal, timer and external interrupts, GPIO, precise traps |
| Benchmarks (Phase II) | `tb_programs`, `tb_single_cycle` | 4 real programs on 3 designs, self-checking |

### Techniques worth knowing
- **Self-checking programs:** each program checks its own results and writes PASS (1) or the failing test number to the TOHOST address. Nobody has to read waveforms to know if it passed.
- **Golden model:** `gen_isa_test.py` contains a tiny Python model of every instruction. The expected answers come from Python, so we never hand-calculate (or mistype) hundreds of values.
- **Mutation testing:** to prove a test can fail, we break the hardware on purpose (invert BNE, break the divide sign, remove the trap flush) and check that the test catches it. Every mutation we tried was caught by the test you would expect.
- **Exact cycle counts:** `tb_riscv_subset` asserts exactly 38 cycles. For example `bench_sum` with no predictor: 654 instructions + 64 stalls + 126 mispredicts × 2 + 4 fill cycles = 974 — exactly what the hardware counter measured. If any hazard logic changed, the count would change.

---

## 7. Results

### 7.1 Benchmarks (measured by the hardware counters)
| Benchmark | Single-cycle | Pipeline, no predictor | Pipeline + 2-bit predictor | Mispredicts (off → on) |
|---|---|---|---|---|
| `bench_fib` (Fibonacci 30) | 160 cyc, CPI 1.000 | 222 cyc, CPI 1.387 | 168 cyc, CPI **1.050** | 29 → 2 |
| `bench_sum` (array sum, 64) | 654 cyc, CPI 1.000 | 974 cyc, CPI 1.489 | 730 cyc, CPI **1.116** | 126 → 4 |
| `bench_sort` (bubble sort, 32) | 3973 cyc, CPI 1.000 | 6224 cyc, CPI 1.566 | 4930 cyc, CPI **1.240** | 860 → 213 |
| `bench_matmul` (8×8, MUL) | 8638 cyc, CPI 1.000 | 10302 cyc, CPI 1.192 | 9330 cyc, CPI **1.080** | 574 → 88 |

What this tells us:
- The predictor cuts the pipeline's extra cycles by **50–85 %** on loop-heavy code.
- `bench_sort` keeps the most mispredictions: whether two elements need swapping depends on the data, which no history can predict well.
- The remaining CPI above 1.0 comes from load-use stalls (64 in `bench_sum`, 512 in `matmul`) and the 4 fill cycles.

### 7.2 Synthesis (Yosys 0.71, Xilinx 7-series mapping, 256-word data RAM)
| | Pipeline (Phase II) | Single-cycle | of which: multiply/divide unit |
|---|---|---|---|
| LUTs | 7,201 | ≈ 5,127 | 4,149 |
| Flip-flops | 2,022 | ≈ 1,248 | 0 |
| CARRY4 (adder chains) | 1,326 | 904 | 1,220 |
| DSP48 (multiplier blocks) | 4 | 4 | 4 |
| RAM (LUT-RAM) | 32 × RAM256X1S | 32 × RAM256X1S | — |

These are **Yosys estimates, not Vivado** results (`make synth`). The pipeline uses more flip-flops (its 4 pipeline registers) and more logic (forwarding, hazard unit, predictor, CSRs). **The combinational multiply/divide unit alone is 58 % of the LUTs.**

### 7.3 Clock speed: logic depth instead of MHz
We have no Vivado in this setup, so we cannot report a real Fmax. Instead we measured **logic depth**: how many LUTs the longest flip-flop-to-flip-flop path passes through (Yosys `ltp` on a 6-input-LUT netlist). The clock period is set by that path, so fewer levels means a faster clock.

| Design (multiply/divide unit not counted) | Longest path | Path |
|---|---|---|
| Single-cycle | **40** LUT levels | PC → instruction → decode → register read → ALU → write-back |
| Pipeline, first version | 27 | timer 64-bit compare → trap decision → PC redirect |
| Pipeline, after registering `timer_irq` | **21** | EX/MEM → forwarding mux → branch compare → redirect → next PC |
| Multiply/divide unit alone | 87 LUTs **+ 288 carry steps** | the 32-bit divider |

What this means:
- Without the divider, the pipeline's cycle is about **40 / 21 ≈ 1.9×** shorter than the single-cycle core's. With CPI 1.05–1.24, the pipeline would run our benchmarks roughly **1.5–1.8× faster** (an estimate: real delays also depend on wiring).
- **With** the combinational divider, the divider is by far the longest path in both designs, so it would set the clock for everything. That is why the multi-cycle divider is the first item in section 9.
- Measuring depth found a real problem: the timer's 64-bit compare was on the pipeline's longest path. Adding one flip-flop (interrupts arrive 1 cycle later, which software cannot notice) cut the depth from 27 to 21 levels.

### 7.4 Real clock speed (place-and-route on an FPGA chip)
Vivado doesn't run on macOS, so we used the open-source flow (Yosys → **nextpnr**) on a Lattice **ECP5-85F** FPGA (`bash fpga/run_fmax.sh`). That gives a real post-place-and-route Fmax with no board needed. A board-level top (`fpga/fpga_top.v`) runs `fpga/fpga_demo.s`, a program that uses every instruction, so the tools can't delete any hardware.

| Configuration | Fmax (MHz) | Critical path through | LUT4 | Flip-flops | DSP (18x18) |
|---|---|---|---|---|---|
| Pipeline (5-stage), RV32IM | **5.5** | muldiv, execution_unit | 14,964 | 2,022 | 4 |
| Single-cycle, RV32IM | **4.9** | muldiv, exec, dmem | 14,252 | 962 | 4 |
| Pipeline (5-stage), M removed* | **62.4** | dmem | 6,865 | 2,022 | 0 |
| Single-cycle, M removed* | **30.4** | dmem | 6,336 | 962 | 0 |

\* M removed = multiply/divide unit replaced by a stub (fpga/muldiv_stub.v) to measure the rest of each core.

Execution time, full RV32IM cores: time = cycles / Fmax

| Benchmark | Single-cycle | Pipeline + predictor | Speed-up |
|---|---|---|---|
| fib | 32.4 µs | 30.8 µs | **1.05×** |
| matmul | 1,748.6 µs | 1,711.9 µs | **1.02×** |
| sort | 804.3 µs | 904.6 µs | **0.89×** |
| sum | 132.4 µs | 133.9 µs | **0.99×** |

Execution time, cores without the M unit (benchmarks that use MUL excluded): time = cycles / Fmax

| Benchmark | Single-cycle | Pipeline + predictor | Speed-up |
|---|---|---|---|
| fib | 5.3 µs | 2.7 µs | **1.95×** |
| sort | 130.5 µs | 79.0 µs | **1.65×** |
| sum | 21.5 µs | 11.7 µs | **1.84×** |

What it means:
- **With the one-cycle divider, both cores crawl at ~5 MHz.** The whole critical path is inside `muldiv_unit`, so pipelining can't help. The divider is also more than half of the logic.
- **Without it, pipelining doubles the clock: 62.4 vs 30.4 MHz.** Even with CPI 1.05–1.24, programs finish **1.65–1.95× sooner** than on the single-cycle core. That is the real payoff of pipelining.
- **Our logic-depth estimate predicted 1.9×; the real measurement says 2.05×.** The estimate was good.
- **Next bottleneck: the data-memory read in MEM.**

---

## 8. Problems we faced, and how we solved them

| # | Problem | How we found it | Fix | Lesson |
|---|---|---|---|---|
| 1 | Design passed simulation but **did not synthesize** (`pipe_id_ex.v`) | Ran Yosys: "Multiple edge sensitive events" | Separate `if (!rst_n)` and `else if (flush)` | Simulation ≠ hardware. An async-reset branch may only test the reset. |
| 2 | **BNE was never tested** | Broke BNE on purpose; all tests still passed | Added `tb_riscv_subset` and then the 234-test ISA test | Coverage must be checked, not assumed |
| 3 | Test script printed **SUCCESS even when tests failed** | Mutation runs showed failures + the success banner | Script now searches the log for failures and exits 1 | `vvp` exits 0 even when checks fail |
| 4 | Synthesis reported only **103 cells** for a whole CPU | Number was impossibly small | Black-box the instruction memory | An empty ROM makes all instructions constant, so synthesis deletes the datapath |
| 5 | Same async-reset mistake again in `pipe_ex_mem.v` (Phase II) | Code review while adding the trap flush | Same fix as #1 | Repeated patterns deserve a checklist |
| 6 | Trap test **timed out** | Mapped the stuck PC back to its label | Handler used `t5`/`t6`, which **are** `x30`/`x31` (our TOHOST/test registers) | Know the ABI register names |
| 7 | Measured instruction count was **one too high** | Compared 3 counts: hand, single-cycle, pipeline | Testbench samples 1 ns after the clock edge | At a clock edge, `<=` flip-flops have not updated yet |
| 8 | Synthesis "logic depth" said the pipeline was deeper than single-cycle | Result contradicted theory, plus "Detected loop" warnings | Use a generic LUT netlist for depth; the Xilinx flip-flop cells weren't recognised, so the path went *through* registers | Sanity-check every surprising number |
| 9 | Pipeline's longest path ran through the **timer compare** | Read the start/end of the `ltp` path | Register `timer_irq` (1-cycle delay): 27 → 21 levels | Measure first, then optimise the actual longest path |
| 10 | The combinational divider is huge and slow | Synthesised `muldiv_unit` on its own | Documented; multi-cycle divider is future work | The simplest design is not always the best one for hardware |
| 11 | FPGA run optimised the **whole CPU** away (21 cells, "no timing paths") | Synthesised the instruction memory alone: 0 cells, i.e. its output was constant | The NOP-fill `for` loop in `instruction_memory.v` turned into memory *write* ports, so the program was lost. Now inside `` `ifndef SYNTHESIS `` | Code that is harmless in simulation can mean something else to a synthesis tool |
| 12 | "Logic loop" warnings for the single-cycle core | Read the loop: it went through the register-file bypass mux | With `BYPASS = 0` the loop was never real (constant select), but tools check before simplifying. Now a `generate` block, so the hardware isn't built | Prefer `generate` over "parameter && …" to remove hardware |

---

## 9. What is still not done

| Item | Why it matters | Suggested approach |
|---|---|---|
| Board demonstration (Basys 3 / Artix-7 with Vivado) | Shows it running on real hardware | `fpga/fpga_top.v` is ready (clock, reset button, switches, LEDs); needs a board and Vivado (Windows/Linux) |
| Multi-cycle divider | The combinational divider limits the clock to ~5 MHz (62 MHz without it) | 32-cycle shift-subtract divider + stall signal |
| Misaligned access exception | Spec-complete behaviour | Raise mcause 4/6 when address bits don't match the size |
| JAL prediction | JAL always costs 2 cycles today | JAL target is known in IF: always redirect there |
| Caches | Real memories are slow | Direct-mapped instruction cache (Project 6 in the course list) |
| Official RISC-V compliance tests (`riscv-arch-test`) | Industry-standard check | Needs the GCC toolchain to build the tests |

---

## 10. How to run everything

Tools: Icarus Verilog (`iverilog`, `vvp`), Python 3, Yosys (optional).

```bash
make test
```
Runs everything: unit tests, Phase I pipeline tests, the ISA test, the trap test and the benchmarks. Ends with "ALL VERIFICATION SUITES COMPLETED SUCCESSFULLY" or "VERIFICATION FAILED".

```bash
bash tools/run_benchmarks.sh
```
Prints the benchmark table.

```bash
python3 tools/rvasm.py myprog.s -o myprog.hex
```
Assembles your own program. Run it with:
```bash
iverilog -g2012 -Irtl '-Ptb_programs.PROG="myprog.hex"' -o sim.vvp rtl/*.v testbench/tb_programs.v && vvp sim.vvp
```
Your program must end by storing 1 (pass) to address `0x800000F0`.

```bash
make synth
```
Synthesis with Yosys; resource numbers go to `synth/utilization.txt`.

```bash
bash fpga/run_fmax.sh
```
Real place-and-route and maximum clock frequency (Lattice ECP5, no board needed). Needs the open-source FPGA tools ([OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)); set `OSS=/path/to/oss-cad-suite` if it isn't in `~/tools/oss-cad-suite-20261112/`. Then summarise with:
```bash
python3 fpga/summarize.py
```

To record a waveform of any program run, add `+vcd=<file>` to the `vvp` command, then open it in GTKWave or any VCD viewer.

---

## 11. Viva questions with answers

**Q: Why does a pipeline have CPI > 1 if it finishes one instruction per cycle?**
A: Only in the ideal case. Load-use stalls add 1 cycle, wrong branch guesses add 2 cycles, and filling the pipeline at the start adds 4. Our measured CPI is 1.05–1.24 with the predictor.

**Q: What is forwarding and when does it not work?**
A: Taking a result from a pipeline register before it is written back. It cannot help a load followed immediately by a use, because the loaded value only exists at the end of MEM. So we stall one cycle.

**Q: Why is the branch penalty 2 cycles?**
A: Branches are resolved in EX, the third stage. By then two younger instructions (in IF and ID) were fetched on the guessed path. If the guess was wrong, both are flushed.

**Q: How does your branch predictor know the target address?**
A: Our instruction memory delivers the instruction in the same cycle, so we decode the B-type immediate in IF and compute PC + imm. No BTB needed.

**Q: Why 2-bit and not 1-bit?**
A: A 1-bit predictor mispredicts twice per loop (at the exit and at the next entry). A 2-bit counter needs two wrong outcomes in a row to change its prediction, so the single loop exit doesn't disturb it.

**Q: What is a precise exception?**
A: When the handler starts, every instruction before the faulting one has completed and none after it has. We get this by trapping in EX: older instructions in MEM/WB finish, younger ones are flushed, and the EX instruction is cancelled.

**Q: What happens on divide by zero?**
A: No exception — RISC-V defines the result: quotient = −1 (all ones), remainder = the dividend.

**Q: Why memory-mapped I/O?**
A: No new instructions are needed; normal loads and stores reach devices. We decode it with one address bit (bit 31).

**Q: What is the difference between CPI and execution time?**
A: Execution time = instructions × CPI × clock period. The single-cycle core has CPI = 1 but a long clock period; the pipeline has CPI ≈ 1.1 and a much shorter period.

**Q: How do you know your tests actually test something?**
A: Mutation testing: we deliberately broke BNE, the divide sign, SB byte-enables, MULHSU and the trap flush. Each time a test failed, naming the exact broken instruction.

**Q: What is your processor's maximum clock frequency?**
A: On a Lattice ECP5 FPGA (real place-and-route with nextpnr): 62.4 MHz for the pipeline without the M unit, versus 30.4 MHz for the single-cycle core. With our single-cycle divider, both drop to about 5 MHz, because the divider is the longest path.

**Q: Why ECP5 and not Artix-7?**
A: Vivado, needed for Xilinx chips, doesn't run on macOS, and we had no board. Yosys + nextpnr give real timing for ECP5 without a board. The absolute MHz would differ on Artix-7, but the comparison between our two cores is still valid.

**Q: Why did you write your own assembler?**
A: Our programs are small. A 280-line Python assembler is easy to read and change, while the GCC toolchain is a large install that outputs ELF files we'd still have to convert. We validated it against known encodings and the old hand-made hex files.

**Q: Why remove the reset from data memory?**
A: Clearing 1024 words in one cycle forces synthesis to use flip-flops for the RAM. Without the reset, the FPGA can use its RAM resources.

---

## 12. Glossary

| Term | Meaning |
|---|---|
| **Bubble** | An empty slot in the pipeline (does nothing) |
| **Stall** | Holding instructions in place for a cycle |
| **Flush** | Throwing away wrongly-fetched instructions (turning them into bubbles) |
| **Forwarding / bypassing** | Using a result before it is written to the register file |
| **Hazard** | A reason the next instruction can't proceed normally (data, control, structural) |
| **CPI / IPC** | Cycles per instruction / instructions per cycle (IPC = 1/CPI) |
| **Retire** | An instruction finishes (leaves WB) |
| **Immediate** | A constant stored inside the instruction |
| **Sign extension** | Copying the top bit to fill a wider number, so negative stays negative |
| **CSR** | Control and Status Register |
| **Trap** | Jump to the handler because of an exception or interrupt |
| **MMIO** | Memory-mapped I/O: devices answer to addresses |
| **LUT** | Look-up table, the basic logic cell of an FPGA |
| **Synthesis** | Turning Verilog into a netlist of real gates/LUTs |
| **Fmax** | Highest clock frequency the design can run at |
| **Testbench** | Verilog code that drives and checks the design in simulation |
| **Mutation testing** | Breaking the design on purpose to check that tests notice |
