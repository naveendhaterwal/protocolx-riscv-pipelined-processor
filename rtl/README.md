# RTL file naming

The suffix on each file name shows which team member is **responsible for** that
file (reviews it, explains it, answers questions about it).

| Suffix | Member | Files |
|---|---|---|
| `_n`  | Naveen  | `riscv_core_n.v`, `riscv_defines_n.vh`, `pipe_if_id_n.v`, `instruction_memory_n.v`, `single_cycle_core_n.v` |
| `_a`  | Aditya  | `pipe_id_ex_a.v`, `pipe_ex_mem_a.v`, `pipe_mem_wb_a.v` |
| `_ar` | Archit  | `control_unit_ar.v`, `reg_file_ar.v`, `imm_gen_ar.v`, `data_memory_ar.v` |
| `_s`  | Shagun  | `alu_s.v`, `execution_unit_s.v`, `hazard_unit_s.v` |

Only the **file names** carry the suffix. Module names are unchanged
(`alu`, `hazard_unit`, ...), so the code reads the same and testbenches that
instantiate a module by name did not need to change. Ritik owns the reports,
presentation and documentation, so he has no RTL file.
