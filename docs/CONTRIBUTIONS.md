# ProtocolX — Team Contributions and Responsibilities

This document has two parts:

- **Part A — Final responsibility allocation:** who is responsible for which part of the final design.
- **Part B — Historical record (Phase I):** the original breakdown, preserved unchanged.

> **What "responsible" means.** The named member answers for that part of the code base: they review it, can explain how it works and how it connects to the neighbouring stages, and are the first contact for questions about it. The allocation describes ownership going forward. It does not change the historical record in Part B.

---

## Part A — Final responsibility allocation

### A.1 Allocation

| Member | Area | RTL files | Tests and evidence |
|:---|:---|:---|:---|
| **Naveen Kumar** (2401020041) | Core architecture | `rtl/riscv_core.v`, `rtl/riscv_defines.vh`, `rtl/pipe_if_id.v`, `rtl/instruction_memory.v` | — |
| **Aditya Raj** (2401010032) | Pipeline registers and verification | `rtl/pipe_id_ex.v`, `rtl/pipe_ex_mem.v`, `rtl/pipe_mem_wb.v` | `testbench/tb_hazard_unit.v`, `testbench/tb_alu.v`; the verification report (`docs/VERIFICATION_REPORT.md`) and test evidence (`simulation/simulation_results.log`, `simulation/*.vcd`) |
| **Archit Mamodiya** (2401010095) | Instruction decode and memory | `rtl/control_unit.v`, `rtl/reg_file.v`, `rtl/imm_gen.v`, `rtl/data_memory.v` | `testbench/tb_riscv_mem.v` |
| **Shagun Vishnoi** (2401020060) | Execution and hazards | `rtl/alu.v`, `rtl/execution_unit.v`, `rtl/hazard_unit.v` | `testbench/tb_riscv_hazard.v`, `testbench/tb_riscv_branch.v` |

### A.2 The same allocation, stage by stage

| Stage | Modules | Responsible |
|:---|:---|:---|
| Top level | `riscv_core.v`, `riscv_defines.vh` | Naveen |
| IF: Instruction Fetch | PC logic in `riscv_core.v`, `instruction_memory.v`, `pipe_if_id.v` | Naveen |
| ID: Instruction Decode | `control_unit.v`, `reg_file.v`, `imm_gen.v` | Archit |
| | `pipe_id_ex.v` | Aditya |
| EX: Execute | `alu.v`, `execution_unit.v`, `hazard_unit.v` | Shagun |
| | `pipe_ex_mem.v` | Aditya |
| MEM: Memory Access | `data_memory.v` | Archit |
| | `pipe_mem_wb.v` | Aditya |
| WB: Write Back | write-back multiplexer in `riscv_core.v` | Naveen |

Each member should be able to explain their modules and how the signals cross the boundary to the stage next to them.

### A.3 Ritik Ranjan's former responsibilities, redistributed

Ritik Ranjan (2401010388) remains a member of the team. His earlier areas (architecture diagrams, GitHub documentation, video preparation) are redistributed as follows. His Phase I contributions stay recorded in Part B.

| Former responsibility | Now with | Why it fits |
|:---|:---|:---|
| Architecture block diagram and walkthrough (`docs/diagrams/`) | **Naveen**; the hazard and forwarding paths are explained by **Shagun** | The diagram shows the core architecture; the hazard paths belong to the execution and hazards area |
| GitHub documentation: `README.md` and repository structure | **Archit** | Keeps the documentation index with the decode and memory area, balancing the load across the team |
| Demonstration video script and video link | **Aditya** | The demonstration presents the verification report and test evidence |

### A.4 Shared items

These are not assigned to one person in this allocation and remain shared by the team:

- the single-cycle baseline `rtl/single_cycle_core.v`;
- testbenches `tb_riscv_core.v`, `tb_reg_file.v`, `tb_riscv_subset.v`, `tb_programs.v`, `tb_single_cycle.v` and the programs in `testbench/programs/`;
- `scripts/` (assembler, test generator, run scripts), `fpga/` and `synth/`;
- the reports, `docs/LEARNING_GUIDE.md` and the Phase II report.

---

## Part B — Historical record (Phase I)

*The text below is preserved as originally recorded. It is the Phase I record and is not changed by the allocation in Part A.*

This document gives an honest and clear breakdown of what each team member worked on for Phase I of our 5-Stage Pipelined RISC-V Processor project.

---

### Team Roster & Roles

| S.No | Name | Enrollment No | Designated Role | Primary Work Area |
|:---:|:---|:---:|:---|:---|
| 1 | **Naveen Kumar** | 2401020041 | Project Lead & Primary RTL Developer | Core processor RTL, pipeline registers, datapath integration |
| 2 | **Aditya Raj** | 2401010032 | Technical Lead, Pipeline Design & Verification | Hazard detection unit, data forwarding, testbench writing, simulation runs |
| 3 | **Archit Mamodiya** | 2401010095 | Literature Review & Research | Researching RISC-V ISA, studying standard pipeline hazards and academic papers |
| 4 | **Shagun Vishnoi** | 2401020060 | IEEE Report & Documentation | Writing and organizing the IEEE Phase I report, compiling references and formatting |
| 5 | **Ritik Ranjan** | 2401010388 | Architecture Diagrams, GitHub Documentation & Video Prep | SVG architecture block diagram, diagram guide, video script and demo plan |

---

### Detailed Task Breakdown

#### 1. Naveen Kumar (2401020041) — Project Lead & Primary RTL Developer
- Planned the top-level architecture and overall timeline for Phase I.
- Implemented the core Verilog modules:
  - `rtl/riscv_defines.vh` (Constants, opcodes, funct codes, and ALU operations).
  - `rtl/alu.v` (Arithmetic Logic Unit for RV32I basic instructions).
  - `rtl/reg_file.v` (32-register bank, x0 hardwired zero, synchronous write, same-cycle bypass).
  - `rtl/imm_gen.v` (Immediate sign-extension for I, S, B, U, J types).
  - `rtl/control_unit.v` (Main instruction decoder and ALU control).
  - `rtl/pipe_if_id.v`, `rtl/pipe_id_ex.v`, `rtl/pipe_ex_mem.v`, `rtl/pipe_mem_wb.v` (The 4 pipeline registers).
  - `rtl/riscv_core.v` (Connecting all stages, wires, and modules together into the full processor core).

#### 2. Aditya Raj (2401010032) — Technical Lead, Pipeline Design & Verification
- Designed the Hazard and Forwarding logic:
  - `rtl/hazard_unit.v` (Detecting EX/MEM and MEM/WB forwarding for RAW data hazards, 1-cycle stall for load-use hazards, and pipeline flushes on taken branches).
  - `rtl/execution_unit.v` (Forwarding multiplexers, branch condition checker, target address calculation).
- Wrote the testbenches and created hex test programs:
  - `testbench/tb_alu.v` (ALU unit tests).
  - `testbench/tb_reg_file.v` (Register file unit tests).
  - `testbench/tb_hazard_unit.v` (Hazard logic unit tests).
  - `testbench/tb_riscv_core.v` (Full pipeline arithmetic tests).
  - `testbench/tb_riscv_hazard.v` (RAW hazard forwarding tests).
  - `testbench/tb_riscv_mem.v` (Data memory load/store and stall tests).
  - `testbench/tb_riscv_branch.v` (Branch condition and flush tests).
- Automated test runs using Icarus Verilog (`scripts/run_sim.sh`) and verified output waveforms.

#### 3. Archit Mamodiya (2401010095) — Literature Review & Research
- Studied the official RISC-V RV32I specification (Volume I: Unprivileged ISA).
- Researched how 5-stage pipelines handle data hazards and control hazards in textbooks (Patterson & Hennessy) and research publications.
- Conducted a comparative study of beginner-friendly and open-source academic RISC-V cores.
- Authored the Literature Review section for the Phase I IEEE project report.

#### 4. Shagun Vishnoi (2401020060) — IEEE Report & Documentation
- Structured and formatted the official Phase I project report according to IEEE conference standards.
- Drafted the Abstract, Introduction, Proposed Solution, and References sections.
- Maintained consistent project documentation across Markdown (`docs/IEEE_Phase1_Project_Report.md`) and LaTeX (`docs/IEEE_Phase1_Project_Report.tex`).
- Checked that all citations and references are genuine and properly cited.

#### 5. Ritik Ranjan (2401010388) — Architecture Diagrams, GitHub Documentation & Video Prep
- Designed the clean vector architecture block diagram (`docs/diagrams/protocolx_pipeline_architecture.svg`).
- Wrote the step-by-step architectural walkthrough guide (`docs/diagrams/diagram_description.md`).
- Prepared the 5-minute prototype presentation script (`VIDEO_DEMO_SCRIPT.md`, now kept in the team's video archive outside this repository) dividing speaking time across all 5 members.
- Created the video link placeholder document (link document; the video link is in the README) for the final demonstration recording.
- Assisted in structuring the GitHub repository README.
