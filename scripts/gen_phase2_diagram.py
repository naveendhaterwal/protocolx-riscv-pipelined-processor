#!/usr/bin/env python3
"""
Generates diagrams/protocolx_phase2_architecture.svg - a block-level view of the
Phase II core: every module in its pipeline stage, Phase II parts marked NEW.
Run from the repo root:  python3 diagrams/gen_phase2_diagram.py
(The detailed wire-level Phase I diagram is protocolx_pipeline_architecture.svg.)
"""
import os

W, H = 1600, 900
STAGES = [("IF", "Instruction Fetch", "#0284c7"), ("ID", "Instruction Decode", "#059669"),
          ("EX", "Execute", "#ea580c"), ("MEM", "Memory Access", "#9333ea"), ("WB", "Write Back", "#db2777")]
COL_X, COL_W, GAP = 30, 272, 44          # stage columns
REGS = ["IF/ID", "ID/EX", "EX/MEM", "MEM/WB"]

# (stage index, title, subtitle, new?)
BLOCKS = [
    (0, "Program Counter", "PC, PC + 4", False),
    (0, "Instruction Memory", "program (hex file)", False),
    (0, "Branch Predictor", "16 x 2-bit counters", True),
    (0, "Target Pre-decode", "PC + B-immediate", True),
    (1, "Control Unit", "+ RV32M, CSRs, traps", False),
    (1, "Register File", "x0 - x31, WB bypass", False),
    (1, "Immediate Generator", "I, S, B, U, J", False),
    (2, "Forwarding Muxes", "EX/MEM, MEM/WB -> EX", False),
    (2, "ALU", "add, logic, shift, compare", False),
    (2, "Multiply / Divide", "RV32M, 8 instructions", True),
    (2, "Branch Check", "condition, target, mispredict", True),
    (2, "CSR & Trap Unit", "CSRs, exceptions, interrupts", True),
    (3, "Data Memory", "byte enables (SB/SH/SW)", True),
    (3, "Load / Store Align", "LB, LH, LBU, LHU, SB, SH", True),
    (3, "GPIO", "LEDs out, switches in", True),
    (3, "Machine Timer", "mtime, mtimecmp -> IRQ", True),
    (4, "Write-back Mux", "ALU / memory / PC + 4", False),
    (4, "Perf. Counters", "mcycle, minstret", True),
]


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;")


def main():
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
         f'font-family="Helvetica Neue, Arial, sans-serif">',
         '<defs><marker id="ar" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto">'
         '<path d="M0,1 L9,5 L0,9z" fill="#475569"/></marker></defs>',
         f'<rect width="{W}" height="{H}" fill="#ffffff"/>',
         '<text x="40" y="52" font-size="30" font-weight="700" fill="#0f172a">ProtocolX: 5-Stage Pipelined RV32IM Processor (Phase II)</text>',
         '<text x="40" y="84" font-size="17" fill="#475569">Block-level view. Blocks marked NEW were added or completed in Phase II. '
         'Detailed Phase I wiring: protocolx_pipeline_architecture.svg</text>']
    top, col_h = 120, 600
    for i, (s, name, c) in enumerate(STAGES):
        x = COL_X + i * (COL_W + GAP)
        o.append(f'<rect x="{x}" y="{top}" width="{COL_W}" height="{col_h}" rx="14" fill="{c}" fill-opacity=".06" stroke="{c}" stroke-width="2"/>')
        o.append(f'<rect x="{x}" y="{top}" width="{COL_W}" height="46" rx="14" fill="{c}"/>')
        o.append(f'<text x="{x+COL_W/2}" y="{top+30}" text-anchor="middle" font-size="19" font-weight="700" fill="#fff">{s}: {name}</text>')
        if i < 4:   # pipeline register between columns
            rx = x + COL_W + GAP / 2 - 9
            o.append(f'<rect x="{rx}" y="{top+10}" width="18" height="{col_h-20}" rx="4" fill="#1e293b"/>')
            o.append(f'<text transform="translate({rx+13},{top+col_h/2}) rotate(-90)" text-anchor="middle" font-size="14" '
                     f'font-weight="700" fill="#fff" letter-spacing="2">{REGS[i]}</text>')
            o.append(f'<line x1="{x+COL_W}" y1="{top+col_h-30}" x2="{rx}" y2="{top+col_h-30}" stroke="#475569" stroke-width="2" marker-end="url(#ar)"/>')
            o.append(f'<line x1="{rx+18}" y1="{top+col_h-30}" x2="{x+COL_W+GAP}" y2="{top+col_h-30}" stroke="#475569" stroke-width="2" marker-end="url(#ar)"/>')
    counts = [0] * 5
    for st, title, sub, new in BLOCKS:
        x = COL_X + st * (COL_W + GAP) + 16
        y = top + 64 + counts[st] * 98
        counts[st] += 1
        c = STAGES[st][2]
        o.append(f'<rect x="{x}" y="{y}" width="{COL_W-32}" height="82" rx="10" fill="#fff" stroke="{c}" '
                 f'stroke-width="{3 if new else 1.5}" {"" if new else "stroke-dasharray=\"0\""}/>')
        o.append(f'<text x="{x+14}" y="{y+34}" font-size="17" font-weight="700" fill="#0f172a">{esc(title)}</text>')
        o.append(f'<text x="{x+14}" y="{y+60}" font-size="13.5" fill="#475569">{esc(sub)}</text>')
        if new:
            o.append(f'<rect x="{x+COL_W-32-58}" y="{y+8}" width="50" height="22" rx="11" fill="{c}"/>')
            o.append(f'<text x="{x+COL_W-32-33}" y="{y+24}" text-anchor="middle" font-size="12" font-weight="700" fill="#fff">NEW</text>')
    # bottom: hazard unit and feedback paths
    hy = top + col_h + 24
    o.append(f'<rect x="{COL_X+COL_W+GAP}" y="{hy}" width="{2*COL_W+GAP}" height="70" rx="10" fill="#fef3c7" stroke="#d97706" stroke-width="2"/>')
    o.append(f'<text x="{COL_X+COL_W+GAP+20}" y="{hy+30}" font-size="18" font-weight="700" fill="#0f172a">Hazard Unit</text>')
    o.append(f'<text x="{COL_X+COL_W+GAP+20}" y="{hy+54}" font-size="14" fill="#475569">forwarding select · 1-cycle load-use stall · '
             f'flush on mispredict / jump / trap / MRET</text>')
    fx = COL_X + 3 * (COL_W + GAP)
    o.append(f'<rect x="{fx}" y="{hy}" width="{2*COL_W+GAP}" height="70" rx="10" fill="#f1f5f9" stroke="#475569" stroke-width="1.5"/>')
    o.append(f'<text x="{fx+20}" y="{hy+30}" font-size="18" font-weight="700" fill="#0f172a">Feedback paths</text>')
    o.append(f'<text x="{fx+20}" y="{hy+54}" font-size="14" fill="#475569">EX -> IF: PC redirect · WB -> ID: register write · '
             f'MEM/WB -> EX: forwarding</text>')
    o.append(f'<text x="40" y="{H-22}" font-size="14" fill="#64748b">Memory map: address bit 31 = 0 -> data RAM, '
             f'1 -> devices (GPIO 0x80000000/04, timer 0x80000010-1C). Traps are taken in EX (precise).</text>')
    o.append("</svg>")
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "protocolx_phase2_architecture.svg")
    open(path, "w").write("\n".join(o))
    print("wrote", path)


if __name__ == "__main__":
    main()
