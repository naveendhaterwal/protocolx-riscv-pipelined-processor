// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       riscv_defines.vh
// Description: Global parameters, opcodes, ALU operation codes, and pipeline
//              control definitions for RV32I Base Integer Instruction Set.
// Developers:  Naveen Kumar (2401020041) - Primary RTL Developer
//              Aditya Raj   (2401010032) - Pipeline Design & Verification
// =============================================================================

`ifndef RISCV_DEFINES_VH
`define RISCV_DEFINES_VH

// -----------------------------------------------------------------------------
// Architectural Constants
// -----------------------------------------------------------------------------
`define XLEN             32
`define REG_ADDR_WIDTH   5
`define NUM_REGS         32

// -----------------------------------------------------------------------------
// RISC-V RV32I Primary Opcodes (Inst[6:0])
// -----------------------------------------------------------------------------
`define OPCODE_R_TYPE    7'b0110011 // Register-Register Arithmetic/Logic
`define OPCODE_I_TYPE    7'b0010011 // Immediate Arithmetic/Logic
`define OPCODE_LOAD      7'b0000011 // Load Instructions (LW, etc.)
`define OPCODE_STORE     7'b0100011 // Store Instructions (SW, etc.)
`define OPCODE_BRANCH    7'b1100011 // Branch Instructions (BEQ, BNE, etc.)
`define OPCODE_JAL       7'b1101111 // Jump and Link
`define OPCODE_JALR      7'b1100111 // Jump and Link Register
`define OPCODE_LUI       7'b0110111 // Load Upper Immediate
`define OPCODE_AUIPC     7'b0010111 // Add Upper Immediate to PC
`define OPCODE_FENCE     7'b0001111 // FENCE (memory ordering) - treated as NOP
`define OPCODE_SYSTEM    7'b1110011 // ECALL, EBREAK, MRET, CSR instructions (Phase II)

// -----------------------------------------------------------------------------
// Funct3 Field Definitions
// -----------------------------------------------------------------------------
// Arithmetic / Logic (R-type and I-type)
`define FUNCT3_ADD_SUB   3'b000
`define FUNCT3_SLL       3'b001
`define FUNCT3_SLT       3'b010
`define FUNCT3_SLTU      3'b011
`define FUNCT3_XOR       3'b100
`define FUNCT3_SRL_SRA   3'b101
`define FUNCT3_OR        3'b110
`define FUNCT3_AND       3'b111

// Branches
`define FUNCT3_BEQ       3'b000
`define FUNCT3_BNE       3'b001
`define FUNCT3_BLT       3'b100
`define FUNCT3_BGE       3'b101
`define FUNCT3_BLTU      3'b110
`define FUNCT3_BGEU      3'b111

// Memory Word (Load / Store)
`define FUNCT3_WORD      3'b010

// -----------------------------------------------------------------------------
// Funct7 Field Definitions
// -----------------------------------------------------------------------------
`define FUNCT7_STANDARD  7'b0000000
`define FUNCT7_ALT       7'b0100000 // SUB, SRA, SRAI
`define FUNCT7_MULDIV    7'b0000001 // RV32M: MUL, MULH, DIV, REM ... (Phase II)

// -----------------------------------------------------------------------------
// ALU Control Operations (4-bit encoding)
// -----------------------------------------------------------------------------
`define ALU_ADD          4'b0000
`define ALU_SUB          4'b0001
`define ALU_AND          4'b0010
`define ALU_OR           4'b0011
`define ALU_XOR          4'b0100
`define ALU_SLT          4'b0101
`define ALU_SLTU         4'b0110
`define ALU_SLL          4'b0111
`define ALU_SRL          4'b1000
`define ALU_SRA          4'b1001
`define ALU_PASS_B       4'b1010 // Used for LUI

// -----------------------------------------------------------------------------
// Forwarding Mux Selects
// -----------------------------------------------------------------------------
`define FWD_NONE         2'b00 // Operand from ID/EX register
`define FWD_MEM_STAGE    2'b10 // Forwarded from EX/MEM stage
`define FWD_WB_STAGE     2'b01 // Forwarded from MEM/WB stage

// -----------------------------------------------------------------------------
// NOP Instruction Encoding (addi x0, x0, 0)
// -----------------------------------------------------------------------------
`define INSTR_NOP        32'h00000013

// -----------------------------------------------------------------------------
// Phase II: memory map. Addresses with bit 31 = 1 go to devices, not to RAM.
// -----------------------------------------------------------------------------
`define MMIO_GPIO_OUT     32'h80000000 // R/W: LEDs / output pins
`define MMIO_GPIO_IN      32'h80000004 // R  : switches / input pins
`define MMIO_MTIME_LO     32'h80000010 // R/W: timer counter, low 32 bits
`define MMIO_MTIME_HI     32'h80000014 // R/W: timer counter, high 32 bits
`define MMIO_MTIMECMP_LO  32'h80000018 // R/W: timer compare, low 32 bits
`define MMIO_MTIMECMP_HI  32'h8000001C // R/W: timer compare, high 32 bits
`define MMIO_TOHOST       32'h800000F0 // W  : test programs write their result here (simulation)

// -----------------------------------------------------------------------------
// Phase II: CSR (Control and Status Register) addresses, machine mode only.
// -----------------------------------------------------------------------------
`define CSR_MSTATUS   12'h300
`define CSR_MIE       12'h304
`define CSR_MTVEC     12'h305
`define CSR_MSCRATCH  12'h340
`define CSR_MEPC      12'h341
`define CSR_MCAUSE    12'h342
`define CSR_MTVAL     12'h343
`define CSR_MIP       12'h344
`define CSR_MCYCLE    12'hB00
`define CSR_MINSTRET  12'hB02
`define CSR_MCYCLEH   12'hB80
`define CSR_MINSTRETH 12'hB82
`define CSR_CYCLE     12'hC00
`define CSR_INSTRET   12'hC02
`define CSR_CYCLEH    12'hC80
`define CSR_INSTRETH  12'hC82

`endif // RISCV_DEFINES_VH
