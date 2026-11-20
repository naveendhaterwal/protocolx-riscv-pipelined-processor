# ProtocolX — 5-Stage Pipelined RISC-V Processor

[![Verilog HDL](https://img.shields.io/badge/Language-Verilog_HDL-blue.svg)](rtl/)
[![Simulator](https://img.shields.io/badge/Simulator-Icarus_Verilog_13.0-green.svg)](https://steveicarus.github.io/iverilog/)
[![Tests](https://img.shields.io/badge/Verification-42%2F42_PASS-brightgreen.svg)](docs/VERIFICATION_REPORT.md)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)
[![Phase](https://img.shields.io/badge/Phase_I-Completed-success.svg)](docs/IEEE_Phase1_Project_Report.md)

Welcome to the **ProtocolX** repository! This is our college engineering project for designing, implementing, and verifying a 32-bit **5-Stage Pipelined RISC-V (RV32I) Processor** using Verilog HDL.

---

## 👥 The ProtocolX Team

| Roll Number | Name | Primary Role & Contributions |
|:---:|:---|:---|
| **2401020041** | **Naveen Kumar** | **Project Lead & Primary RTL Developer**<br>Core processor architecture, ALU, Register File, Immediate Generator, and top-level datapath integration. |
| **2401010032** | **Aditya Raj** | **Technical Lead, Pipeline Design & Verification**<br>Hazard detection unit, RAW data forwarding logic, testbench development, and simulation verification. |
| **2401010095** | **Archit Mamodiya** | **Literature Review & Research**<br>RISC-V specification analysis, comparative study of open-source academic cores, and literature review. |
| **2401020060** | **Shagun Vishnoi** | **IEEE Report & Documentation**<br>Authoring and formatting the IEEE Phase I report, compiling authentic academic citations, and documentation. |
| **2401010388** | **Ritik Ranjan** | **Architecture Diagrams, GitHub Docs & Video Preparation**<br>Creating SVG block diagrams, diagram guide, video presentation script, and video link coordination. |

---

## 🎯 Project Objective (Phase I)

The goal of Phase I was to build a working, hardware-accurate 5-stage pipelined processor implementing the base integer RISC-V instruction set (RV32I). 

Instead of waiting for one instruction to complete all its operations before starting the next one (single-cycle), our processor overlaps execution across 5 stages like an assembly line:

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
  <img src="diagrams/pipeline_animation.gif" alt="ProtocolX 5-Stage Pipeline Live Animation" width="100%" />
</p>

*Above: Live execution showing instructions overlapping across the 5 stages (`IF` $\rightarrow$ `ID` $\rightarrow$ `EX` $\rightarrow$ `MEM` $\rightarrow$ `WB`) with real-time data forwarding. For the static vector schematic, see [diagrams/protocolx_pipeline_architecture.svg](diagrams/protocolx_pipeline_architecture.svg) and the walkthrough in [diagrams/diagram_description.md](diagrams/diagram_description.md).*

### The 5 Pipeline Stages
1. **Instruction Fetch (IF):** Reads the 32-bit instruction from memory using the Program Counter (PC) and increments `PC = PC + 4`.
2. **Instruction Decode (ID):** Decodes the opcode and function fields, reads registers from the 32-entry Register File (`x0` is hardwired to 0), and sign-extends immediate values.
3. **Execute (EX):** The 32-bit ALU performs arithmetic, bitwise, shift, or comparison calculations. Branch addresses are computed here.
4. **Memory Access (MEM):** Reads from or writes to the 4KB Data Memory for `LW` and `SW` instructions.
5. **Write-Back (WB):** Selects between the ALU result, memory data, or `PC + 4` and writes back into the destination register (`rd`).

### The 4 Pipeline Registers
Between each stage sits a synchronous pipeline register that latches data and control signals on every clock tick:
- `pipe_if_id`: Holds instruction and PC. Can be stalled or flushed.
- `pipe_id_ex`: Holds register data, immediate, PC, and control signals. Can be flushed.
- `pipe_ex_mem`: Holds computed ALU result, store data, and memory control lines.
- `pipe_mem_wb`: Holds memory read data, ALU result, and writeback destination.

### 🛡️ How We Handle Hazards
- **RAW Data Hazards:** Resolved by the **Data Forwarding Unit**. If an instruction in EX needs a register calculated by an earlier instruction currently in MEM or WB, data is forwarded directly into the ALU input multiplexers without stalling.
- **Load-Use Data Hazard:** When an instruction immediately depends on data being loaded by `LW`, the data cannot be forwarded in time. Our **Hazard Unit** detects this, pauses the PC and IF/ID registers, and inserts a 1-cycle bubble (NOP).
- **Control Hazards:** When a conditional branch (`BEQ`, `BNE`, etc.) evaluates to true, instructions speculatively fetched along the wrong path are flushed (converted to NOPs).

---

## 📂 Repository Structure

```
protocolx-riscv-pipelined-processor/
├── rtl/                               # Verilog Source Files
│   ├── riscv_defines.vh               # Constants, opcodes, ALU operation codes
│   ├── riscv_core.v                   # Top-level 5-stage pipelined processor core
│   ├── alu.v                          # 32-bit Arithmetic Logic Unit
│   ├── reg_file.v                     # 32x32-bit Register File (x0=0, bypass)
│   ├── imm_gen.v                      # Sign-extending Immediate Generator
│   ├── control_unit.v                 # Instruction decoder & ALU control
│   ├── hazard_unit.v                  # Data forwarding & load-use stall logic
│   ├── execution_unit.v               # EX stage with forwarding muxes & ALU
│   ├── instruction_memory.v           # 4KB instruction ROM/RAM model
│   ├── data_memory.v                  # 4KB data RAM model
│   ├── pipe_if_id.v                   # IF/ID pipeline register
│   ├── pipe_id_ex.v                   # ID/EX pipeline register
│   ├── pipe_ex_mem.v                  # EX/MEM pipeline register
│   └── pipe_mem_wb.v                  # MEM/WB pipeline register
│
├── testbench/                         # Testbenches & Test Programs
│   ├── tb_riscv_core.v                # Full pipeline integration testbench
│   ├── tb_riscv_hazard.v              # RAW hazard forwarding testbench
│   ├── tb_riscv_mem.v                 # Load/Store & load-use stall testbench
│   ├── tb_riscv_branch.v              # Branch taken & flush testbench
│   ├── tb_alu.v                       # ALU unit testbench
│   ├── tb_reg_file.v                  # Register file unit testbench
│   ├── tb_hazard_unit.v               # Hazard unit testbench
│   └── programs/                      # Hex machine code test suites
│       ├── prog_arithmetic.hex        # Basic arithmetic instructions
│       ├── prog_hazard.hex            # RAW data hazard test program
│       ├── prog_load_store.hex        # Memory & load-use stall program
│       └── prog_branch.hex            # Branch condition test program
│
├── diagrams/                          # Architectural Diagrams
│   ├── pipeline_animation.gif         # Live animated GIF of 5-stage pipeline
│   ├── protocolx_pipeline_architecture.svg # Vector block diagram
│   ├── simulation_waveform_diagram.svg     # Timing and cycle waveform diagram
│   └── diagram_description.md         # Detailed diagram walkthrough
│
├── docs/                              # Project Documentation & Reports
│   ├── IEEE_Phase1_Project_Report.pdf  # Compiled IEEE Two-Column Conference PDF
│   ├── IEEE_Phase1_Project_Report.html # IEEE Conference Format HTML source
│   ├── IEEE_Phase1_Project_Report.md  # Official IEEE Phase I Report (Markdown)
│   ├── IEEE_Phase1_Project_Report.tex # IEEE Report LaTeX source file
│   ├── CONTRIBUTIONS.md               # Detailed individual team contributions
│   └── VERIFICATION_REPORT.md         # Test coverage & simulation audit
│
├── simulation/                        # Simulation Scripts & Real Logs
│   ├── run_sim.sh                     # Automated bash simulation runner
│   ├── simulation_results.log         # Real unabridged simulation log
│   ├── waveform.vcd                   # Core arithmetic VCD waveform
│   ├── waveform_hazard.vcd            # Forwarding test waveform
│   ├── waveform_mem.vcd               # Memory & stall waveform
│   └── waveform_branch.vcd            # Branch flush waveform
│
├── video/                             # Video Presentation Deliverables
│   ├── VIDEO_DEMO_SCRIPT.md           # 5-minute prototype presentation script
│   └── VIDEO_LINK.md                  # Video demonstration link placeholder
│
├── Makefile                           # Quick command runner
├── LICENSE                            # MIT License
└── README.md                          # Main project guide
```

---

## ⚡ Quickstart: Running Simulations

> New here? Start with [`docs/LEARNING_GUIDE.md`](docs/LEARNING_GUIDE.md).

### Prerequisites
You need **Icarus Verilog** (`iverilog`) and **GTKWave** (optional, for viewing waveforms).
- On macOS (Homebrew):
  ```bash
  brew install icarus-verilog gtkwave
  ```
- On Ubuntu/Debian Linux:
  ```bash
  sudo apt-get install iverilog gtkwave
  ```

### Run All Verification Tests
To compile and run every unit test and full pipeline testbench in one go:
```bash
./simulation/run_sim.sh
```
Or simply:
```bash
make test
```

### Run Specific Testbenches
- **Top-level Pipeline Test:** `make test_core`
- **Data Forwarding Test:** `make test_hazard`
- **Memory & Stall Test:** `make test_mem`
- **Branch Flush Test:** `make test_branch`
- **ALU Unit Test:** `make test_alu`

### Viewing Waveforms
Open any of the generated `.vcd` files in GTKWave:
```bash
gtkwave simulation/waveform.vcd
```

---

## 📊 Verification Results

`make test` runs everything below and ends with **ALL VERIFICATION SUITES COMPLETED SUCCESSFULLY** (or exits with an error if any check fails).

| Suite | Checks | Result |
|---|---|---|
| Phase I unit + pipeline testbenches (ALU, register file, hazard unit, arithmetic, forwarding, load-use, branch flush, instruction subset) | 51 | ✅ all pass |
| `isa_test` — **234 generated tests** covering every RV32IM instruction + CSRs (predictor on and off) | 234 × 2 | ✅ pass |
| `trap_test` — ECALL, EBREAK, illegal instruction, timer + external interrupts, GPIO, precise traps (predictor on and off) | 9 groups × 2 | ✅ pass |
| Benchmarks on 3 designs (self-checking) | 4 × 3 | ✅ pass |

### Benchmarks (cycles measured by the hardware counters)

| Benchmark | Single-cycle baseline | Pipeline, no predictor | Pipeline + 2-bit predictor |
|---|---|---|---|
| `bench_fib` (Fibonacci 30) | 160 cycles, CPI 1.000 | 222, CPI 1.387 | 168, CPI **1.050** |
| `bench_sum` (array sum) | 654, CPI 1.000 | 974, CPI 1.489 | 730, CPI **1.116** |
| `bench_sort` (bubble sort) | 3973, CPI 1.000 | 6224, CPI 1.566 | 4930, CPI **1.240** |
| `bench_matmul` (8×8 with MUL) | 8638, CPI 1.000 | 10302, CPI 1.192 | 9330, CPI **1.080** |

The pipeline has a higher CPI than the single-cycle core but a much shorter clock.

### Real clock speed (Yosys + nextpnr place-and-route, Lattice ECP5-85F)

| Configuration | Fmax | Benchmarks vs single-cycle |
|---|---|---|
| Pipeline, RV32IM | 5.45 MHz | 0.89–1.05× (both cores limited by the 1-cycle divider) |
| Single-cycle, RV32IM | 4.94 MHz | — |
| **Pipeline, M unit removed** | **62.4 MHz** | **1.65–1.95× faster** |
| Single-cycle, M unit removed | 30.4 MHz | — |

Run it yourself with `bash fpga/run_fmax.sh` (needs [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build); no board needed). Full write-up: [**Phase II report (PDF)**](docs/IEEE_Phase2_Project_Report.pdf) and [`docs/LEARNING_GUIDE.md`](docs/LEARNING_GUIDE.md#7-results).

A complete log of the last run is in [`simulation/simulation_results.log`](simulation/simulation_results.log).

---

## 📹 Video Demonstration

A 5-minute video presentation covering the project introduction, member roles, architecture walkthrough, Verilog code review, and live simulation is documented in [`video/VIDEO_DEMO_SCRIPT.md`](video/VIDEO_DEMO_SCRIPT.md).

- **Demonstration Video Link (Google Drive):**  
  👉 **[ProtocolX Phase I Prototype Video (Google Drive)](https://drive.google.com/drive/folders/11hZyntXJBju4w4UMHXSxqYusGwjAtXKI?usp=sharing)**  
  *(Also recorded in [`video/VIDEO_LINK.md`](video/VIDEO_LINK.md) and [`video/README.md`](video/README.md))*

---

## 🗺️ Project Status & Roadmap

### Completed in Phase I:
- [x] Full 5-stage pipelined datapath (IF, ID, EX, MEM, WB).
- [x] 4 Pipeline registers with stall and flush controls.
- [x] RV32I basic instructions (Arithmetic, Logic, Shifts, Comparisons, LW, SW, BEQ, BNE, JAL).
- [x] Hardware forwarding unit for RAW data hazards.
- [x] Hardware load-use stall unit (1-cycle bubble injection).
- [x] Control hazard pipeline flushes on taken branches.
- [x] Real simulation runs, testbenches, and waveforms.
- [x] IEEE Phase I Project Report and architecture diagrams.

### Completed in Phase II:
- [x] Dynamic branch prediction: 2-bit saturating counters, target decoded in IF (no BTB needed).
- [x] RV32M multiply / divide / remainder (all 8 instructions, spec-defined edge cases).
- [x] Byte and half-word loads/stores (LB, LH, LBU, LHU, SB, SH) with byte enables.
- [x] CSRs (Zicsr), ECALL / EBREAK / MRET, illegal-instruction trap, precise traps.
- [x] Machine timer and external interrupts.
- [x] Memory-mapped GPIO (inputs and outputs) and hardware performance counters (`mcycle`, `minstret`).
- [x] Single-cycle baseline core and 4 self-checking benchmarks for CPI comparison.
- [x] Synthesis with Yosys + logic-depth analysis (longest path reduced from 27 to 21 LUT levels).
- [x] Real post-place-and-route Fmax with nextpnr (Lattice ECP5): 62.4 MHz pipeline vs 30.4 MHz single-cycle.
- [x] Phase II IEEE report ([PDF](docs/IEEE_Phase2_Project_Report.pdf)) and Phase II architecture diagram.
- [x] Own assembler (`tools/rvasm.py`) and a generated 234-test instruction test.
- [x] [`docs/LEARNING_GUIDE.md`](docs/LEARNING_GUIDE.md): how everything works, problems faced, design choices and alternatives.

### Still open (future work):
- [ ] Board demonstration on a Basys 3 / Artix-7 (needs a board and Vivado; `fpga/fpga_top.v` is ready).
- [ ] Multi-cycle divider (the combinational divider limits the clock to ~5 MHz).
- [ ] Misaligned-access exceptions, JAL prediction, caches.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
