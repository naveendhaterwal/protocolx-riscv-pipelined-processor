# ProtocolX — 5-Stage Pipelined RISC-V Processor

[![Verilog HDL](https://img.shields.io/badge/Language-Verilog_HDL-blue.svg)](rtl/)
[![Simulator](https://img.shields.io/badge/Simulator-Icarus_Verilog_13.0-green.svg)](https://steveicarus.github.io/iverilog/)
[![Tests](https://img.shields.io/badge/Verification-51_checks_%2B_146_ISA_tests_PASS-brightgreen.svg)](docs/VERIFICATION_REPORT.md)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)
[![Phase I](https://img.shields.io/badge/Phase_I-Completed-success.svg)](docs/IEEE_Phase1_Project_Report.md)
[![Phase II](https://img.shields.io/badge/Phase_II-Completed-success.svg)](docs/IEEE_Phase2_Project_Report.pdf)

Welcome to the **ProtocolX** repository! This is our college engineering project (Modern Computer Architecture, *Project 3*) for designing, implementing, verifying and measuring a 32-bit **5-Stage Pipelined RISC-V (RV32I) Processor** in Verilog HDL, and comparing it against a **single-cycle baseline**.

> **New here?** Read [`docs/LEARNING_GUIDE.md`](docs/LEARNING_GUIDE.md): it explains every part of the design in simple language, the problems we faced and the alternatives we considered.

---

## 🔎 Where to look (for a code review)

| You want to see… | Open |
|---|---|
| The processor (all Verilog) | [`rtl/`](rtl/): start with [`riscv_core.v`](rtl/riscv_core.v) (top level) |
| How hazards are handled | [`rtl/hazard_unit.v`](rtl/hazard_unit.v) (forwarding, load-use stall, flush) |
| The single-cycle baseline | [`rtl/single_cycle_core.v`](rtl/single_cycle_core.v) |
| The tests | [`testbench/`](testbench/) (Verilog testbenches) and [`testbench/programs/`](testbench/programs/) (assembly programs) |
| Every helper script | [`scripts/`](scripts/) (assembler, test generator, run scripts, FPGA flow) |
| Architecture diagram | [`docs/diagrams/protocolx_pipeline_architecture.svg`](docs/diagrams/protocolx_pipeline_architecture.svg) |
| Reports | [`docs/`](docs/): Phase I and Phase II IEEE reports |

---

## 👥 The ProtocolX Team

Final responsibility allocation. Each member answers for these parts of the project (review, explanation, questions). Details, the stage-by-stage view and the historical Phase I record are in [`docs/CONTRIBUTIONS.md`](docs/CONTRIBUTIONS.md).

| Roll Number | Name | Area | Responsible for |
|:---:|:---|:---|:---|
| **2401020041** | **Naveen Kumar** | **Core architecture** | `riscv_core.v`, `riscv_defines.vh`, `pipe_if_id.v`, `instruction_memory.v` |
| **2401010032** | **Aditya Raj** | **Pipeline registers and verification** | `pipe_id_ex.v`, `pipe_ex_mem.v`, `pipe_mem_wb.v`, `tb_hazard_unit.v`, `tb_alu.v`, the verification report and test evidence |
| **2401010095** | **Archit Mamodiya** | **Instruction decode and memory** | `control_unit.v`, `reg_file.v`, `imm_gen.v`, `data_memory.v`, `tb_riscv_mem.v` |
| **2401020060** | **Shagun Vishnoi** | **Execution and hazards** | `alu.v`, `execution_unit.v`, `hazard_unit.v`, `tb_riscv_hazard.v`, `tb_riscv_branch.v` |
| **2401010388** | **Ritik Ranjan** | **Reports, presentation and documentation** | IEEE Phase I and Phase II reports, the presentation, architecture diagrams (`docs/diagrams/`), `README.md` and repository documentation, demonstration video material |

Each member supplies and checks the technical content for their own area, so that the reports and the presentation describe the design accurately.

---

## 🎯 Project Objective

Build a working, hardware-accurate 5-stage pipelined processor for the RISC-V base integer instruction set (RV32I), verify it, and **measure** how much the pipeline helps compared with a single-cycle design (CPI, IPC, clock speed, execution time).

Instead of waiting for one instruction to finish all its steps before starting the next (single-cycle), the processor overlaps execution across 5 stages like an assembly line:

```
Clock Cycle:   1     2     3     4     5     6     7
Instruction 1: [IF]  [ID]  [EX]  [MEM] [WB]
Instruction 2:       [IF]  [ID]  [EX]  [MEM] [WB]
Instruction 3:             [IF]  [ID]  [EX]  [MEM] [WB]
Instruction 4:                   [IF]  [ID]  [EX]  [MEM] [WB]
Instruction 5:                         [IF]  [ID]  [EX]  [MEM] [WB]
```

---

## 🏗️ Processor Architecture & Live Pipeline Execution

<p align="center">
  <img src="docs/diagrams/pipeline_animation.gif" alt="ProtocolX 5-Stage Pipeline Live Animation" width="100%" />
</p>

*Above: instructions overlapping across the 5 stages (`IF` → `ID` → `EX` → `MEM` → `WB`) with real-time data forwarding (a concept animation). The static vector schematic is [docs/diagrams/protocolx_pipeline_architecture.svg](docs/diagrams/protocolx_pipeline_architecture.svg); the walkthrough is in [docs/diagrams/diagram_description.md](docs/diagrams/diagram_description.md).*

### The 5 Pipeline Stages
1. **Instruction Fetch (IF):** Reads the 32-bit instruction from memory using the Program Counter (PC) and increments `PC = PC + 4`.
2. **Instruction Decode (ID):** Decodes the opcode and function fields, reads registers from the 32-entry Register File (`x0` is hardwired to 0), and sign-extends immediate values.
3. **Execute (EX):** The 32-bit ALU performs arithmetic, bitwise, shift, or comparison calculations. Branch conditions and target addresses are computed here.
4. **Memory Access (MEM):** Reads from or writes to the 4 KB Data Memory for `LW` and `SW`.
5. **Write-Back (WB):** Selects between the ALU result, memory data, or `PC + 4` and writes it into the destination register (`rd`).

### The 4 Pipeline Registers
- `pipe_if_id`: instruction and PC. Can be stalled or flushed.
- `pipe_id_ex`: register data, immediate, PC and control signals. Can be flushed.
- `pipe_ex_mem`: ALU result, store data and memory control lines.
- `pipe_mem_wb`: memory read data, ALU result and write-back destination.

### 🛡️ How We Handle Hazards
- **RAW data hazards:** the **forwarding unit** passes a result from EX/MEM or MEM/WB straight into the ALU input multiplexers, with no stall.
- **Load-use hazard:** data from `LW` arrives too late to forward, so the **hazard unit** holds the PC and IF/ID and inserts a 1-cycle bubble.
- **Control hazards:** branches and jumps are resolved in EX, so the two instructions fetched after a taken branch are flushed (2 cycles lost).

### The single-cycle baseline
[`rtl/single_cycle_core.v`](rtl/single_cycle_core.v) is built from the *same* modules but without pipeline registers: every instruction finishes in one (long) cycle, so CPI = 1. The pipeline needs more cycles but each one is much shorter. Comparing the two is how we show that pipelining actually pays off.

---

## 📂 Repository Structure

```
protocolx-riscv-pipelined-processor/
├── rtl/                          # Verilog design (this is the processor)
│   ├── riscv_defines.vh          #   constants: opcodes, ALU operation codes
│   ├── riscv_core.v              #   TOP LEVEL: 5-stage pipelined core
│   ├── single_cycle_core.v       #   single-cycle baseline core
│   ├── alu.v  reg_file.v  imm_gen.v  control_unit.v
│   ├── hazard_unit.v             #   forwarding, load-use stall, flush
│   ├── execution_unit.v          #   EX stage: forwarding muxes, ALU, branch check
│   ├── instruction_memory.v  data_memory.v
│   └── pipe_if_id.v  pipe_id_ex.v  pipe_ex_mem.v  pipe_mem_wb.v
│
├── testbench/                    # Verilog testbenches and test programs
│   ├── tb_alu.v  tb_reg_file.v  tb_hazard_unit.v           # unit tests
│   ├── tb_riscv_core.v  tb_riscv_hazard.v  tb_riscv_mem.v  # pipeline tests
│   ├── tb_riscv_branch.v  tb_riscv_subset.v
│   ├── tb_programs.v             #   runs any program on the pipeline (cycles, stalls, flushes)
│   ├── tb_single_cycle.v         #   runs any program on the single-cycle baseline
│   └── programs/                 #   assembly (.s) and machine code (.hex)
│       ├── prog_*.hex            #     Phase I test programs
│       ├── isa_test.s            #     146 generated, self-checking RV32I tests
│       └── bench_*.s             #     4 benchmarks: fib, sum, sort, matmul
│
├── scripts/                      # ALL helper scripts live here
│   ├── run_sim.sh                #   run the complete verification suite
│   ├── run_benchmarks.sh         #   benchmarks: CPI, IPC, cycle-model check
│   ├── rvasm.py                  #   our RV32I assembler (.s -> .hex)
│   ├── gen_isa_test.py           #   generates testbench/programs/isa_test.s
│   ├── gen_prog_subset.py        #   generates prog_subset.hex
│   ├── run_fmax.sh  summarize_fmax.py   # real Fmax with Yosys + nextpnr
│   └── make_benchmark_chart.py  build_report_pdf.py  gen_pipeline_gif.py
│
├── fpga/                         # FPGA flow: board-level top, demo program, results
├── synth/                        # Yosys synthesis helper and area report
├── simulation/                   # simulation log and VCD waveforms (real outputs)
├── docs/                         # reports, learning guide, diagrams/, figures/
├── Makefile                      # quick commands (make test, make bench, ...)
├── LICENSE
└── README.md
```

---

## ⚡ Quickstart

### Prerequisites
**Icarus Verilog** (`iverilog`) and Python 3. Optional: **GTKWave** (waveforms), **Yosys** (`make synth`).
- macOS: `brew install icarus-verilog gtkwave yosys`
- Ubuntu/Debian: `sudo apt-get install iverilog gtkwave yosys`

### Commands
| Command | What it does |
|---|---|
| `make test` | the complete verification suite (ends with *ALL VERIFICATION SUITES COMPLETED SUCCESSFULLY*, or exits with an error) |
| `make bench` | the 4 benchmarks on both designs: CPI, IPC and the cycle-model check |
| `make test_programs` | the 146-test RV32I instruction program on both designs |
| `make test_core` / `test_hazard` / `test_mem` / `test_branch` / `test_alu` | single testbenches |
| `make synth` | Yosys synthesis (area) |
| `make fpga` | real maximum clock frequency (needs [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build); no board needed) |

Open any waveform with `gtkwave simulation/waveform.vcd`.
To write your own program: `python3 scripts/rvasm.py myprog.s` produces `myprog.hex`.

---

## 📊 Results

### Verification (`make test`, all passing)

| Suite | Checks |
|---|---|
| Unit and pipeline testbenches (ALU, register file, hazard unit, arithmetic, forwarding, load-use stall, branch flush, 7-instruction subset) | **51** |
| `isa_test`: generated, self-checking program covering every RV32I instruction, on the pipeline **and** the single-cycle core | **146 tests × 2 designs** |
| Benchmarks: each program checks its own answer, on both designs | **4 × 2** |
| Cycle-model check: `cycles = N + 4 + stalls + 2·flushes` matches the measurement on every benchmark | **4 / 4 exact** |

We also did **mutation testing** (deliberately breaking the hardware: inverted BNE, SRA behaving like SRL, forwarding disabled); every break was caught by the suite, naming the broken instruction.

### Benchmarks: pipeline vs single-cycle

| Benchmark | Instructions (N) | Pipeline cycles | CPI | IPC | Load-use stalls | Flushes |
|---|---|---|---|---|---|---|
| `fib`: Fibonacci(30) | 160 | 222 | 1.387 | 0.721 | 0 | 29 |
| `sum`: sum of a 64-element array | 654 | 974 | 1.489 | 0.671 | 64 | 126 |
| `sort`: bubble sort, 32 values | 3,973 | 6,224 | 1.567 | 0.638 | 527 | 860 |
| `matmul`: 8×8 matrices, shift-and-add multiply | 21,742 | 29,326 | 1.349 | 0.741 | 0 | 3,790 |

The single-cycle core runs each program in exactly N cycles (CPI 1.000). The extra pipeline cycles are fully explained by the pipeline fill (4), load-use stalls (1 each) and flushes (2 each):

![Where the pipeline's cycles go](docs/figures/benchmark_cpi.png)

### Real clock speed: Yosys + nextpnr place-and-route, Lattice ECP5-85F

| Design | Fmax | LUT4 | Flip-flops | Critical path |
|---|---|---|---|---|
| **5-stage pipeline** | **67.8 MHz** | 5,100 | 1,541 | data-memory read (MEM stage) |
| Single-cycle baseline | 38.8 MHz | 5,161 | 722 | data-memory read after the ALU |

The pipeline's clock is **1.75× faster**. Combined with its higher CPI, programs finish **1.12× to 1.30× sooner** (execution time = cycles / Fmax):

| Benchmark | Single-cycle | Pipeline | Speed-up |
|---|---|---|---|
| fib | 4.1 µs | 3.3 µs | **1.26×** |
| sum | 16.9 µs | 14.4 µs | **1.17×** |
| sort | 102.4 µs | 91.9 µs | **1.12×** |
| matmul | 560.5 µs | 432.8 µs | **1.30×** |

These are ECP5 results (Vivado, needed for a Xilinx Artix-7, does not run on macOS, and no board was available). Absolute MHz would differ on another chip; the comparison between our two designs is what matters. Details: [Phase II report (PDF)](docs/IEEE_Phase2_Project_Report.pdf).

A complete log of the last run is in [`simulation/simulation_results.log`](simulation/simulation_results.log).

---

## 📹 Video Demonstration

- **Demonstration Video Link (Google Drive):**
  👉 **[ProtocolX Phase I Prototype Video (Google Drive)](https://drive.google.com/drive/folders/11hZyntXJBju4w4UMHXSxqYusGwjAtXKI?usp=sharing)**

---

## 🗺️ Project Status & Roadmap

### Completed in Phase I
- [x] Full 5-stage pipelined datapath (IF, ID, EX, MEM, WB) with 4 pipeline registers (stall and flush support).
- [x] RV32I instructions: arithmetic, logic, shifts, comparisons, `LW`, `SW`, all six branches, `JAL`, `JALR`, `LUI`, `AUIPC`.
- [x] Forwarding unit (RAW hazards), load-use stall, control-hazard flush.
- [x] Real simulation runs, testbenches, waveforms, IEEE Phase I report and architecture diagrams.

### Completed in Phase II
- [x] Single-cycle baseline core, built from the same modules, for comparison.
- [x] Benchmarks (4 programs) with measured CPI and IPC, and an exact cycle model (`N + 4 + stalls + 2·flushes`).
- [x] Our own RV32I assembler and a generated 146-test self-checking instruction program.
- [x] Test-suite hardening: mutation testing; the run script now fails when a check fails.
- [x] Synthesis fixes found by running real tools (reset/flush coding bug, ROM contents, RAM reset loop).
- [x] Real post-place-and-route Fmax (Yosys + nextpnr, Lattice ECP5): pipeline 67.8 MHz vs single-cycle 38.8 MHz.
- [x] [Phase II IEEE report](docs/IEEE_Phase2_Project_Report.pdf) and [`docs/LEARNING_GUIDE.md`](docs/LEARNING_GUIDE.md).

### Not done / ideas for later
- [ ] Board demonstration on a Basys 3 / Artix-7 (needs a board and Vivado; `fpga/fpga_top.v` is ready).
- [ ] Branch prediction (its own course project) to cut the 2-cycle cost of a taken branch.
- [ ] Faster memory path (the data-memory read is the critical path), caches.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
