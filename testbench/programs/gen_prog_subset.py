#!/usr/bin/env python3
# =============================================================================
# Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
# Script:     gen_prog_subset.py
# Description: Generates prog_subset.hex, a program that exercises the full
#              Project-3 instruction subset (ADD, SUB, ADDI, LW, SW, BEQ, BNE)
#              and is used by tb_riscv_subset.v to measure cycles and CPI.
#              Usage (from repo root): python3 testbench/programs/gen_prog_subset.py
# =============================================================================
import os

def r_type(funct7, funct3, rd, rs1, rs2):
    return funct7 << 25 | rs2 << 20 | rs1 << 15 | funct3 << 12 | rd << 7 | 0x33

def add(rd, rs1, rs2): return r_type(0x00, 0, rd, rs1, rs2)
def sub(rd, rs1, rs2): return r_type(0x20, 0, rd, rs1, rs2)
def addi(rd, rs1, imm): return (imm & 0xFFF) << 20 | rs1 << 15 | 0 << 12 | rd << 7 | 0x13
def lw(rd, rs1, imm):   return (imm & 0xFFF) << 20 | rs1 << 15 | 2 << 12 | rd << 7 | 0x03

def sw(rs2, rs1, imm):
    imm &= 0xFFF
    return (imm >> 5) << 25 | rs2 << 20 | rs1 << 15 | 2 << 12 | (imm & 0x1F) << 7 | 0x23

def branch(funct3, rs1, rs2, offset):
    o = offset & 0x1FFF
    return ((o >> 12) & 1) << 31 | ((o >> 5) & 0x3F) << 25 | rs2 << 20 | rs1 << 15 \
        | funct3 << 12 | ((o >> 1) & 0xF) << 8 | ((o >> 11) & 1) << 7 | 0x63

def beq(rs1, rs2, offset): return branch(0, rs1, rs2, offset)
def bne(rs1, rs2, offset): return branch(1, rs1, rs2, offset)

NOP = 0x00000013

PROGRAM = [
    addi(1, 0, 0),    # 0x00  x1 = 0            (sum)
    addi(2, 0, 5),    # 0x04  x2 = 5            (loop counter)
    add(1, 1, 2),     # 0x08  loop: x1 += x2    (RAW hazards -> forwarding)
    addi(2, 2, -1),   # 0x0c  x2 -= 1
    bne(2, 0, -8),    # 0x10  bne x2, x0, loop  (taken 4x -> 2-cycle flush each)
    sw(1, 0, 0),      # 0x14  mem[0] = x1 (15)
    lw(3, 0, 0),      # 0x18  x3 = mem[0]
    add(4, 3, 3),     # 0x1c  x4 = 30           (load-use -> 1-cycle stall)
    sub(5, 4, 1),     # 0x20  x5 = 15
    beq(5, 1, 8),     # 0x24  beq x5, x1, +8    (taken -> flush)
    addi(6, 0, 99),   # 0x28  must be flushed (x6 stays 0)
    addi(7, 0, 1),    # 0x2c  x7 = 1            (end marker)
] + [NOP] * 8

if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "prog_subset.hex")
    with open(out, "w") as f:
        f.write("\n".join(f"{w:08x}" for w in PROGRAM) + "\n")
    print(f"Wrote {len(PROGRAM)} words to {out}")
