#!/usr/bin/env python3
"""
rvasm.py - a tiny RISC-V (RV32IM + Zicsr) assembler for the ProtocolX processor.

Why we wrote our own: the full GNU toolchain (riscv64-unknown-elf-gcc) is a large
install and outputs ELF files we would then have to convert. Our test programs are
small, so a ~250-line Python assembler is easier to read, install and change.

Usage:
    python3 tools/rvasm.py program.s -o program.hex

Input format (one instruction per line):
    label:                 # a label marks an address
    addi x1, x0, 5         # registers as x0..x31 or ABI names (zero, ra, sp, t0, a0, ...)
    lw   t0, 8(sp)         # loads/stores use offset(base)
    beq  t0, t1, label     # branch/jump targets can be labels
    .word 0x12345678       # raw 32-bit word
Pseudo-instructions: nop, li, la, mv, not, neg, j, jr, ret, call, beqz, bnez, bgt, ble,
                     csrr, csrw, csrs, csrc, csrwi, csrsi, csrci
Output: one 32-bit word per line in hex, which $readmemh loads into instruction memory.
"""
import re
import sys

# ---------------------------------------------------------------- registers
ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1",
       "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
       "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
       "t3", "t4", "t5", "t6"]
REG = {name: i for i, name in enumerate(ABI)}
REG.update({f"x{i}": i for i in range(32)})
REG["fp"] = 8

CSR = {"mstatus": 0x300, "mie": 0x304, "mtvec": 0x305, "mscratch": 0x340, "mepc": 0x341,
       "mcause": 0x342, "mtval": 0x343, "mip": 0x344, "mcycle": 0xB00, "minstret": 0xB02,
       "mcycleh": 0xB80, "minstreth": 0xB82, "cycle": 0xC00, "instret": 0xC02}

# ---------------------------------------------------------------- opcode tables
#            funct7, funct3
R_TYPE = {"add": (0x00, 0), "sub": (0x20, 0), "sll": (0x00, 1), "slt": (0x00, 2),
          "sltu": (0x00, 3), "xor": (0x00, 4), "srl": (0x00, 5), "sra": (0x20, 5),
          "or": (0x00, 6), "and": (0x00, 7),
          # RV32M (funct7 = 0000001)
          "mul": (0x01, 0), "mulh": (0x01, 1), "mulhsu": (0x01, 2), "mulhu": (0x01, 3),
          "div": (0x01, 4), "divu": (0x01, 5), "rem": (0x01, 6), "remu": (0x01, 7)}
I_ALU = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SHIFT_I = {"slli": (0x00, 1), "srli": (0x00, 5), "srai": (0x20, 5)}
LOADS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
STORES = {"sb": 0, "sh": 1, "sw": 2}
BRANCHES = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}
CSR_OPS = {"csrrw": 1, "csrrs": 2, "csrrc": 3, "csrrwi": 5, "csrrsi": 6, "csrrci": 7}


def r_type(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def i_type(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def s_type(imm, rs2, rs1, f3):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | 0x23


def b_type(off, rs2, rs1, f3):
    o = off & 0x1FFF
    return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | 0x63


def u_type(imm20, rd, op):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op


def j_type(off, rd):
    o = off & 0x1FFFFF
    return (((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20) | \
           (((o >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


# ---------------------------------------------------------------- helpers
class AsmError(Exception):
    pass


def reg(tok):
    tok = tok.strip().lower()
    if tok not in REG:
        raise AsmError(f"unknown register '{tok}'")
    return REG[tok]


def num(tok, labels=None):
    tok = tok.strip()
    if labels is not None and tok in labels:
        return labels[tok]
    try:
        return int(tok, 0)
    except ValueError:
        raise AsmError(f"bad number or unknown label '{tok}'")


def mem_operand(tok):
    m = re.fullmatch(r"\s*(-?\w*)\s*\(\s*(\w+)\s*\)\s*", tok)
    if not m:
        raise AsmError(f"expected offset(reg), got '{tok}'")
    return (num(m.group(1)) if m.group(1) else 0), reg(m.group(2))


def li_parts(value):
    """Split a 32-bit constant into (upper20, lower12) so that lui+addi rebuilds it."""
    value &= 0xFFFFFFFF
    lo = value & 0xFFF
    if lo >= 0x800:        # addi sign-extends, so borrow one from the upper part
        lo -= 0x1000
    hi = ((value - lo) >> 12) & 0xFFFFF
    return hi, lo


def fits12(v):
    return -2048 <= v <= 2047


def expand(mn, ops):
    """Rewrite pseudo-instructions into real ones. Returns a list of (mnemonic, operands)."""
    if mn == "nop":
        return [("addi", ["x0", "x0", "0"])]
    if mn == "mv":
        return [("addi", [ops[0], ops[1], "0"])]
    if mn == "not":
        return [("xori", [ops[0], ops[1], "-1"])]
    if mn == "neg":
        return [("sub", [ops[0], "x0", ops[1]])]
    if mn == "j":
        return [("jal", ["x0", ops[0]])]
    if mn == "jr":
        return [("jalr", ["x0", f"0({ops[0]})"])]
    if mn == "ret":
        return [("jalr", ["x0", "0(ra)"])]
    if mn == "call":
        return [("jal", ["ra", ops[0]])]
    if mn == "beqz":
        return [("beq", [ops[0], "x0", ops[1]])]
    if mn == "bnez":
        return [("bne", [ops[0], "x0", ops[1]])]
    if mn == "bgt":
        return [("blt", [ops[1], ops[0], ops[2]])]
    if mn == "ble":
        return [("bge", [ops[1], ops[0], ops[2]])]
    if mn == "csrr":
        return [("csrrs", [ops[0], ops[1], "x0"])]
    if mn == "csrw":
        return [("csrrw", ["x0", ops[0], ops[1]])]
    if mn == "csrs":
        return [("csrrs", ["x0", ops[0], ops[1]])]
    if mn == "csrc":
        return [("csrrc", ["x0", ops[0], ops[1]])]
    if mn in ("csrwi", "csrsi", "csrci"):     # immediate forms, result discarded
        return [("csrr" + mn[3] + "i", ["x0", ops[0], ops[1]])]
    if mn == "la":                      # load address of a label: always auipc + addi
        return [("auipc", [ops[0], "%pcrel_hi " + ops[1]]),
                ("addi", [ops[0], ops[0], "%pcrel_lo " + ops[1]])]
    if mn == "li":
        v = num(ops[1])
        if fits12(v):
            return [("addi", [ops[0], "x0", str(v)])]
        hi, lo = li_parts(v)
        out = [("lui", [ops[0], str(hi)])]
        if lo:
            out.append(("addi", [ops[0], ops[0], str(lo)]))
        return out
    return [(mn, ops)]


def encode(mn, ops, pc, labels):
    def target(tok):
        return num(tok, labels) - pc

    # "la" expands to these two; handle them before the general rules below
    if mn == "auipc" and ops[1].startswith("%pcrel_hi "):
        off = num(ops[1].split()[1], labels) - pc               # distance from this auipc
        return u_type((off + 0x800) >> 12, reg(ops[0]), 0x17)
    if mn == "addi" and ops[2].startswith("%pcrel_lo "):
        off = num(ops[2].split()[1], labels) - (pc - 4)         # the auipc is one instruction back
        lo = off - (((off + 0x800) >> 12) << 12)
        return i_type(lo, reg(ops[1]), 0, reg(ops[0]), 0x13)
    if mn in R_TYPE:
        f7, f3 = R_TYPE[mn]
        return r_type(f7, reg(ops[2]), reg(ops[1]), f3, reg(ops[0]), 0x33)
    if mn in I_ALU:
        return i_type(num(ops[2]), reg(ops[1]), I_ALU[mn], reg(ops[0]), 0x13)
    if mn in SHIFT_I:
        f7, f3 = SHIFT_I[mn]
        return r_type(f7, num(ops[2]) & 31, reg(ops[1]), f3, reg(ops[0]), 0x13)
    if mn in LOADS:
        off, base = mem_operand(ops[1])
        return i_type(off, base, LOADS[mn], reg(ops[0]), 0x03)
    if mn in STORES:
        off, base = mem_operand(ops[1])
        return s_type(off, reg(ops[0]), base, STORES[mn])
    if mn in BRANCHES:
        return b_type(target(ops[2]), reg(ops[1]), reg(ops[0]), BRANCHES[mn])
    if mn == "jal":
        if len(ops) == 1:
            ops = ["ra", ops[0]]
        return j_type(target(ops[1]), reg(ops[0]))
    if mn == "jalr":
        if "(" in ops[1]:
            off, base = mem_operand(ops[1])
        else:
            base, off = reg(ops[1]), (num(ops[2]) if len(ops) > 2 else 0)
        return i_type(off, base, 0, reg(ops[0]), 0x67)
    if mn == "lui":
        return u_type(num(ops[1]), reg(ops[0]), 0x37)
    if mn == "auipc":
        return u_type(num(ops[1]), reg(ops[0]), 0x17)
    if mn in CSR_OPS:
        csr = CSR.get(ops[1].strip().lower()) if ops[1].strip().lower() in CSR else num(ops[1])
        src = num(ops[2]) & 31 if mn.endswith("i") else reg(ops[2])
        return i_type(csr, src, CSR_OPS[mn], reg(ops[0]), 0x73)
    if mn == "ecall":
        return 0x00000073
    if mn == "ebreak":
        return 0x00100073
    if mn == "mret":
        return 0x30200073
    raise AsmError(f"unknown instruction '{mn}'")


def assemble(text):
    # Pass 1: strip comments, expand pseudo-instructions, give every label an address.
    items, labels, pc = [], {}, 0
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#")[0].strip()
        while ":" in line:                       # one or more "label:" at line start
            lab, line = line.split(":", 1)
            labels[lab.strip()] = pc
            line = line.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        mn = parts[0].lower()
        ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
        try:
            if mn == ".word":
                items.append((lineno, raw, ".word", ops, pc))
                pc += 4
                continue
            for emn, eops in expand(mn, ops):
                items.append((lineno, raw, emn, eops, pc))
                pc += 4
        except AsmError as e:
            raise AsmError(f"line {lineno}: {e}\n    {raw.strip()}")
    # Pass 2: encode, now that all label addresses are known.
    words = []
    for lineno, raw, mn, ops, pc in items:
        try:
            words.append(num(ops[0], labels) & 0xFFFFFFFF if mn == ".word" else encode(mn, ops, pc, labels))
        except (AsmError, IndexError) as e:
            raise AsmError(f"line {lineno}: {e}\n    {raw.strip()}")
    return words, labels


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    out = sys.argv[sys.argv.index("-o") + 1] if "-o" in sys.argv else src.rsplit(".", 1)[0] + ".hex"
    try:
        words, _ = assemble(open(src).read())
    except AsmError as e:
        sys.exit(f"{src}: {e}")
    with open(out, "w") as f:
        f.write("\n".join(f"{w:08x}" for w in words) + "\n")
    print(f"{src}: {len(words)} instructions -> {out}")


if __name__ == "__main__":
    main()
