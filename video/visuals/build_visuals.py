#!/usr/bin/env python3
"""
ProtocolX Phase I video visuals.

Builds every still used in the video as HTML/SVG and renders it to a 1920x1080
PNG with headless Chromium (Playwright). Run from the repo root:

    python3 video/visuals/build_visuals.py            # all scenes
    python3 video/visuals/build_visuals.py wave       # only scenes whose name contains "wave"

Honesty rules this script follows:
  * Waveforms are drawn ONLY from real VCD files written by Icarus Verilog.
  * Terminal/test-result cards show text copied from a real `make test` run log.
  * Numbers on the status board come from that log and from synth/utilization.txt.
  * Purely explanatory drawings are labelled "Concept illustration".
"""
import html
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "video", "visuals", "out")
sys.path.insert(0, os.path.join(ROOT, "testbench", "programs"))

# ----------------------------------------------------------------------------
# Theme
# ----------------------------------------------------------------------------
BG, PANEL, BORDER = "#0b1120", "#111a2e", "#24324d"
TEXT, MUTED, DIM = "#e2e8f0", "#94a3b8", "#475569"
STAGE = {"IF": "#38bdf8", "ID": "#34d399", "EX": "#fb923c", "MEM": "#c084fc", "WB": "#f472b6"}
ACCENT, OK, WARN, BAD = "#38bdf8", "#34d399", "#fbbf24", "#f87171"
SANS = "'Helvetica Neue', Helvetica, Arial, sans-serif"
MONO = "Menlo, 'SF Mono', Monaco, monospace"

BASE_CSS = f"""
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:1920px;height:1080px;overflow:hidden}}
body{{background:{BG};color:{TEXT};font-family:{SANS};
     background-image:radial-gradient(circle at 15% 10%, #13213d 0, transparent 45%),
                      radial-gradient(circle at 90% 95%, #1a1530 0, transparent 40%);}}
.frame{{position:absolute;inset:0;padding:70px 90px}}
.kicker{{font:600 22px {SANS};letter-spacing:.18em;text-transform:uppercase;color:{ACCENT}}}
h1{{font:700 64px/1.1 {SANS};margin-top:14px}}
h2{{font:700 46px/1.15 {SANS};margin-top:10px}}
.sub{{font:400 28px/1.45 {SANS};color:{MUTED}}}
.tag{{position:absolute;right:90px;bottom:50px;font:500 20px {SANS};color:{MUTED};
     border:1px solid {BORDER};padding:8px 16px;border-radius:8px;background:{PANEL}}}
.src{{position:absolute;left:90px;bottom:50px;font:400 20px {MONO};color:{MUTED}}}
.brand{{position:absolute;right:90px;top:62px;font:700 22px {SANS};color:{DIM};letter-spacing:.12em}}
"""


def page(body, css="", brand=True):
    b = '<div class="brand">PROTOCOLX</div>' if brand else ""
    return f"<!doctype html><html><head><meta charset='utf-8'><style>{BASE_CSS}{css}</style></head><body>{b}{body}</body></html>"


def esc(s):
    return html.escape(str(s))


# ----------------------------------------------------------------------------
# Real data sources
# ----------------------------------------------------------------------------
def parse_vcd(path, wanted):
    """Minimal VCD reader. wanted: list of full hierarchical names.
    Returns {name: [(time, value_str), ...]} (value '1'/'0' or binary string)."""
    ids, scope, changes, t = {}, [], {}, 0
    with open(path) as f:
        in_defs = True
        for line in f:
            tok = line.split()
            if not tok:
                continue
            if in_defs:
                if tok[0] == "$scope":
                    scope.append(tok[2])
                elif tok[0] == "$upscope":
                    scope.pop()
                elif tok[0] == "$var":
                    name = ".".join(scope + [tok[4]])
                    if name in wanted:
                        ids.setdefault(tok[3], []).append(name)
                        changes[name] = []
                elif tok[0] == "$enddefinitions":
                    in_defs = False
                continue
            c = tok[0]
            if c[0] == "#":
                t = int(c[1:])
            elif c[0] in "01xz" and c[1:] in ids:
                for n in ids[c[1:]]:
                    changes[n].append((t, c[0]))
            elif c[0] == "b" and len(tok) > 1 and tok[1] in ids:
                for n in ids[tok[1]]:
                    changes[n].append((t, c[1:]))
    missing = [w for w in wanted if w not in changes]
    if missing:
        raise SystemExit(f"VCD {path}: signals not found: {missing}")
    return changes


def value_at(chg, t):
    v = None
    for ct, cv in chg:
        if ct > t:
            break
        v = cv
    return v


def to_int(v):
    try:
        return int(v, 2)
    except (TypeError, ValueError):
        return None


def disasm_table():
    """Map machine words of prog_subset.hex back to the assembly they encode."""
    import gen_prog_subset as g
    asm = ["addi x1, x0, 0", "addi x2, x0, 5", "add x1, x1, x2", "addi x2, x2, -1",
           "bne x2, x0, loop", "sw x1, 0(x0)", "lw x3, 0(x0)", "add x4, x3, x3",
           "sub x5, x4, x1", "beq x5, x1, +8", "addi x6, x0, 99", "addi x7, x0, 1"]
    table = {w: a.replace(", ", ",") for w, a in zip(g.PROGRAM, asm)}
    table[0x00000013] = "bubble"
    return table


def run_log():
    """Re-run the real suite and return its log text (source of truth for numbers)."""
    subprocess.run(["bash", "simulation/run_sim.sh"], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with open(os.path.join(ROOT, "simulation", "simulation_results.log")) as f:
        return f.read()


def log_facts(log):
    summaries = re.findall(r"^\s*(.*Summary.*)$", log, re.M)
    passed = failed = 0
    for s in summaries:
        m = re.search(r"Passed = (\d+), Failed = (\d+)", s) or re.search(r"(\d+) Passed, (\d+) Failed", s)
        passed += int(m.group(1))
        failed += int(m.group(2))
    perf = re.search(r"instructions = (\d+) \| cycles = (\d+) \| stall cycles = (\d+) \| taken-branch flushes = (\d+)", log)
    cpi = re.search(r"CPI \(incl\. 4-cycle pipeline fill\) = ([\d.]+) \| CPI \(steady state, excl\. fill\) = ([\d.]+)", log)
    ok = "ALL VERIFICATION SUITES COMPLETED SUCCESSFULLY" in log
    return dict(summaries=summaries, passed=passed, failed=failed, suites=len(summaries),
                instr=int(perf.group(1)), cycles=int(perf.group(2)), stalls=int(perf.group(3)),
                flushes=int(perf.group(4)), cpi=cpi.group(1), cpi_ss=cpi.group(2), ok=ok)


def synth_facts():
    p = os.path.join(ROOT, "synth", "utilization.txt")
    txt = open(p).read()
    luts = sum(int(n) for n in re.findall(r"^\s+(\d+)\s+LUT\d", txt, re.M))
    ffs = sum(int(n) for n in re.findall(r"^\s+(\d+)\s+FD\w+", txt, re.M))
    return dict(luts=luts, ffs=ffs)


# ----------------------------------------------------------------------------
# Scene: real waveform
# ----------------------------------------------------------------------------
TB = "tb_riscv_subset"
D = TB + ".dut."
WAVE_SIGNALS = [TB + ".clk", D + "pc_reg", D + "instr_id", D + "forward_a", D + "forward_b",
                D + "pc_write", D + "if_id_flush", D + "reg_write_wb", D + "rd_wb", D + "wb_data"]


def sample_cycles(vcd_path, n_cycles):
    ch = parse_vcd(vcd_path, WAVE_SIGNALS)
    # Cycle k = the state just after the k-th rising clock edge following reset release.
    rises = [t for (t, v) in ch[TB + ".clk"] if v == "1"]
    rst_release = 22000  # tb: #22 rst_n = 1 (timescale 1ns, VCD in ps)
    rises = [t for t in rises if t > rst_release][:n_cycles]
    rows = []
    for t in rises:
        s = t + 1000
        rows.append({k.split(".")[-1]: value_at(ch[k], s) for k in WAVE_SIGNALS})
    return rows


def wave_svg(rows, c0, c1, show_text, width=1740):
    # Overview (no text) omits the instruction row: names don't fit at 40 cycles.
    dis = disasm_table()
    lab_w, row_h, top = 250, 74, 46
    n = c1 - c0
    cw = (width - lab_w) / n
    names = [("clk", "clk"), ("PC", "pc_reg"), ("Instr in ID", "instr_id"),
             ("forward_a", "forward_a"), ("forward_b", "forward_b"),
             ("stall (!pc_write)", "stall"), ("flush (IF/ID)", "if_id_flush"), ("Write-back", "wb")]
    if not show_text:
        names = [nm for nm in names if nm[1] != "instr_id"]
    h = top + row_h * len(names) + 10
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{h}" font-family="{MONO}">']
    for k in range(n):  # cycle grid + numbers
        x = lab_w + k * cw
        o.append(f'<line x1="{x:.1f}" y1="{top-8}" x2="{x:.1f}" y2="{h}" stroke="#1c2840" stroke-width="1"/>')
        o.append(f'<text x="{x+cw/2:.1f}" y="{top-18}" fill="{MUTED}" font-size="15" text-anchor="middle">{c0+k}</text>')
    o.append(f'<text x="0" y="{top-18}" fill="{MUTED}" font-size="15">cycle</text>')
    for i, (label, key) in enumerate(names):
        y = top + i * row_h
        mid, hi, lo = y + row_h / 2, y + 16, y + row_h - 16
        o.append(f'<text x="0" y="{mid+6:.1f}" fill="{TEXT}" font-size="19" font-family="{SANS}" font-weight="600">{esc(label)}</text>')
        if key == "clk":
            for k in range(n):
                x = lab_w + k * cw
                o.append(f'<polyline fill="none" stroke="{ACCENT}" stroke-width="2" points="{x:.1f},{lo} {x:.1f},{hi} {x+cw/2:.1f},{hi} {x+cw/2:.1f},{lo} {x+cw:.1f},{lo}"/>')
            continue
        if key in ("stall", "if_id_flush"):
            colr = BAD if key == "stall" else WARN
            for k in range(n):
                r = rows[c0 + k]
                v = (r["pc_write"] == "0") if key == "stall" else (r["if_id_flush"] == "1")
                x = lab_w + k * cw
                yy = hi if v else lo
                o.append(f'<line x1="{x:.1f}" y1="{yy}" x2="{x+cw:.1f}" y2="{yy}" stroke="{colr if v else DIM}" stroke-width="{3 if v else 2}"/>')
                if v:
                    o.append(f'<rect x="{x:.1f}" y="{hi}" width="{cw:.1f}" height="{lo-hi}" fill="{colr}" opacity=".18"/>')
                if k and ((rows[c0+k-1]["pc_write"] == "0") if key == "stall" else (rows[c0+k-1]["if_id_flush"] == "1")) != v:
                    o.append(f'<line x1="{x:.1f}" y1="{hi}" x2="{x:.1f}" y2="{lo}" stroke="{colr}" stroke-width="2"/>')
            continue
        # bus rows
        for k in range(n):
            r = rows[c0 + k]
            x = lab_w + k * cw
            fill, txt, colr = "none", "", MUTED
            if key == "pc_reg":
                txt = f"{to_int(r['pc_reg']):02x}"
            elif key == "instr_id":
                txt = dis.get(to_int(r["instr_id"]), f"{to_int(r['instr_id']):08x}")
                colr = DIM if txt == "bubble" else TEXT
            elif key in ("forward_a", "forward_b"):
                v = to_int(r[key])
                txt = {0: "00", 2: "10 EX/MEM", 1: "01 MEM/WB"}.get(v, "?")
                if v:
                    fill, colr = OK, OK
            elif key == "wb":
                if r["reg_write_wb"] == "1" and to_int(r["rd_wb"]):
                    txt = f"x{to_int(r['rd_wb'])}={to_int(r['wb_data'])}"
                    fill, colr = STAGE["WB"], STAGE["WB"]
            pts = f"{x+4:.1f},{mid} {x+10:.1f},{hi} {x+cw-10:.1f},{hi} {x+cw-4:.1f},{mid} {x+cw-10:.1f},{lo} {x+10:.1f},{lo}"
            o.append(f'<polygon points="{pts}" fill="{fill}" fill-opacity=".16" stroke="{colr if fill != "none" else "#3b4a66"}" stroke-width="1.6"/>')
            if txt and (show_text or key in ("forward_a", "forward_b", "wb", "pc_reg")):
                fs = 14 if show_text else 12
                if not show_text and key in ("forward_a", "forward_b"):
                    txt = txt.split()[0] if fill == "none" else txt.split()[0]
                if not show_text and key == "wb":
                    txt = txt.split("=")[0]
                o.append(f'<text x="{x+cw/2:.1f}" y="{mid+5:.1f}" fill="{colr}" font-size="{fs}" text-anchor="middle">{esc(txt)}</text>')
    o.append("</svg>")
    return "".join(o)


def scene_waveforms():
    vcd = os.path.join(ROOT, "simulation", "waveform_subset.vcd")
    rows = sample_cycles(vcd, 40)
    stall_c = [i for i, r in enumerate(rows) if r["pc_write"] == "0"]
    flush_c = [i for i, r in enumerate(rows) if r["if_id_flush"] == "1"]
    src = "Rendered from simulation/waveform_subset.vcd  •  Icarus Verilog  •  tb_riscv_subset.v"
    css = ".wave{margin-top:34px;background:#0d1628;border:1px solid " + BORDER + ";border-radius:14px;padding:28px 34px}"
    full = page(f"""<div class="frame"><div class="kicker">Real simulation waveform</div>
      <h2>Full test program: BNE loop, load-use stall, branch flushes</h2>
      <div class="wave">{wave_svg(rows, 0, 40, False)}</div>
      <div class="src">{esc(src)}</div>
      <div class="tag">stall: cycle {", ".join(map(str, stall_c))} • flush: cycles {", ".join(map(str, flush_c))}</div></div>""", css)
    z0 = max(0, stall_c[0] - 4)
    zoom = page(f"""<div class="frame"><div class="kicker">Real simulation waveform • zoom</div>
      <h2>Load-use stall, then a taken BEQ flush</h2>
      <div class="wave">{wave_svg(rows, z0, z0 + 12, True)}</div>
      <div class="src">{esc(src)}</div></div>""", css)
    loop = page(f"""<div class="frame"><div class="kicker">Real simulation waveform • zoom</div>
      <h2>BNE loop: forwarding every iteration, flush on each taken branch</h2>
      <div class="wave">{wave_svg(rows, 2, 14, True)}</div>
      <div class="src">{esc(src)}</div></div>""", css)
    return {"aditya_10_waveform_full": full, "aditya_11_waveform_loadstall_beq": zoom,
            "aditya_12_waveform_bne_loop": loop}


# ----------------------------------------------------------------------------
# Scene: architecture / block diagram (one drawing, many highlight states)
# ----------------------------------------------------------------------------
# Pipeline register bars (x positions) and stage column spans in diagram units.
REGS = [("IF / ID", 330), ("ID / EX", 760), ("EX / MEM", 1170), ("MEM / WB", 1460)]
COLS = {"IF": (0, 330), "ID": (356, 760), "EX": (786, 1170), "MEM": (1196, 1460), "WB": (1486, 1740)}
# id: (x, y, w, h, title, subtitle, stage, kind)
BLOCKS = {
    "pcmux":  (24, 300, 34, 120, "", "", "IF", "mux"),
    "pc":     (84, 320, 86, 80, "PC", "", "IF", "box"),
    "add4":   (196, 170, 90, 60, "+4", "", "IF", "box"),
    "imem":   (196, 290, 120, 190, "Instruction", "Memory", "IF", "box"),
    "ctrl":   (396, 92, 330, 92, "Control Unit", "RegWrite · MemRead · MemWrite · ALUOp", "ID", "box"),
    "rf":     (396, 252, 250, 220, "Register File", "x0–x31 · 2 read, 1 write", "ID", "box"),
    "imm":    (396, 528, 250, 84, "Immediate Gen", "I · S · B · U · J", "ID", "box"),
    "fwa":    (806, 262, 34, 110, "", "", "EX", "mux"),
    "fwb":    (806, 402, 34, 110, "", "", "EX", "mux"),
    "alusrc": (876, 430, 34, 110, "", "", "EX", "mux"),
    "alu":    (950, 268, 130, 250, "ALU", "", "EX", "alu"),
    "badd":   (930, 104, 210, 84, "Branch target", "PC + imm", "EX", "box"),
    "bcmp":   (930, 560, 210, 70, "Branch compare", "BEQ · BNE · …", "EX", "box"),
    "dmem":   (1222, 262, 214, 230, "Data Memory", "LW / SW", "MEM", "box"),
    "wbmux":  (1540, 288, 40, 170, "", "", "WB", "mux"),
    "hazard": (396, 718, 770, 86, "Hazard Detection & Forwarding Unit", "forward_a / forward_b · stall · flush", "HZ", "box"),
}
# (points, kind, stage) kind: data | ctrl | fwd | wb | br
WIRES = [
    ([(58, 360), (84, 360)], "data", "IF"),
    ([(170, 360), (196, 360)], "data", "IF"),
    ([(150, 320), (150, 200), (196, 200)], "data", "IF"),
    ([(286, 200), (310, 200), (310, 140), (10, 140), (10, 330), (24, 330)], "data", "IF"),
    ([(316, 385), (330, 385)], "data", "IF"),
    ([(356, 300), (396, 300)], "data", "ID"),
    ([(356, 420), (396, 420)], "data", "ID"),
    ([(356, 570), (396, 570)], "data", "ID"),
    ([(376, 300), (376, 138), (396, 138)], "ctrl", "ID"),
    ([(726, 138), (760, 138)], "ctrl", "ID"),
    ([(646, 310), (760, 310)], "data", "ID"),
    ([(646, 430), (760, 430)], "data", "ID"),
    ([(646, 570), (760, 570)], "data", "ID"),
    ([(786, 310), (806, 310)], "data", "EX"),
    ([(786, 450), (806, 450)], "data", "EX"),
    ([(840, 317), (950, 317)], "data", "EX"),
    ([(840, 457), (876, 457)], "data", "EX"),
    ([(786, 570), (860, 570), (860, 515), (876, 515)], "data", "EX"),
    ([(910, 485), (950, 485)], "data", "EX"),
    ([(855, 457), (855, 595), (930, 595)], "data", "EX"),
    ([(1080, 393), (1170, 393)], "data", "EX"),
    ([(855, 600), (855, 660), (1150, 660), (1150, 460), (1170, 460)], "data", "EX"),
    ([(1196, 393), (1222, 393)], "data", "MEM"),
    ([(1196, 460), (1222, 460)], "data", "MEM"),
    ([(1436, 340), (1460, 340)], "data", "MEM"),
    ([(1205, 393), (1205, 530), (1450, 530), (1450, 420), (1460, 420)], "data", "MEM"),
    ([(1486, 340), (1540, 340)], "data", "WB"),
    ([(1486, 420), (1540, 420)], "data", "WB"),
    ([(1580, 373), (1640, 373), (1640, 690), (380, 690), (380, 452), (396, 452)], "wb", "WB"),
    ([(1185, 393), (1185, 640), (790, 640), (790, 345), (806, 345)], "fwd", "FWD"),
    ([(790, 485), (806, 485)], "fwd", "FWD"),
    ([(1610, 373), (1610, 675), (800, 675), (800, 365), (806, 365)], "fwd", "FWD"),
    ([(1140, 146), (1150, 146), (1150, 60), (40, 60), (40, 300)], "br", "EX"),
]
WIRE_STYLE = {"data": ("#64748b", ""), "ctrl": (WARN, "7 6"), "fwd": (OK, ""),
              "wb": (STAGE["WB"], ""), "br": (BAD, "")}


def arch_svg(active=None, stage=None, flows=False):
    """active: set of block ids to emphasise (others dimmed); stage: column to frame."""
    W, H = 1740, 820
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="{SANS}">',
         '<defs>' + "".join(
             f'<marker id="a{k}" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,1 L9,5 L0,9z" fill="{c}"/></marker>'
             for k, (c, _) in WIRE_STYLE.items()) + '</defs>']
    if stage:
        x0, x1 = COLS[stage]
        o.append(f'<rect x="{x0-6}" y="74" width="{x1-x0+12}" height="{632}" rx="16" fill="{STAGE[stage]}" fill-opacity=".07" stroke="{STAGE[stage]}" stroke-width="3"/>')
    for s, (x0, x1) in COLS.items():
        on = stage in (None, s)
        o.append(f'<rect x="{x0}" y="0" width="{x1-x0}" height="40" rx="8" fill="{STAGE[s]}" opacity="{.95 if on else .25}"/>')
        o.append(f'<text x="{(x0+x1)/2}" y="27" text-anchor="middle" font-size="19" font-weight="700" fill="#0b1120" opacity="{1 if on else .5}">{s}</text>')

    def dim_block(bid):
        return active is not None and bid not in active

    for pts, kind, st in WIRES:
        c, dash = WIRE_STYLE[kind]
        if active is not None:
            op = 1 if (kind == "fwd" and "FWD" in active) or (kind == "wb" and "WBPATH" in active) or \
                (kind == "br" and "BRPATH" in active) or (kind in ("data", "ctrl") and st in (active or ())) else .18
        else:
            op = .18 if (stage and st not in (stage,) and not (stage == "WB" and kind == "wb")) else 1
        if flows and kind == "ctrl":
            op = 1
        d = " ".join(f"{x},{y}" for x, y in pts)
        o.append(f'<polyline points="{d}" fill="none" stroke="{c}" stroke-width="{3 if kind != "data" else 2.4}" stroke-dasharray="{dash}" opacity="{op}" marker-end="url(#a{kind})"/>')
    for name, x in REGS:
        on = active is not None and name in active
        o.append(f'<rect x="{x}" y="74" width="26" height="632" rx="6" fill="{"#0e3a52" if on else "#1e293b"}" stroke="{ACCENT if on else "#64748b"}" stroke-width="{4 if on else 2}" opacity="{.35 if dim_block(name) else 1}"/>')
        o.append(f'<text transform="translate({x+18},{390}) rotate(-90)" text-anchor="middle" font-size="15" font-weight="700" fill="{TEXT}" letter-spacing="2" opacity="{.35 if dim_block(name) else 1}">{name}</text>')
    for bid, (x, y, w, h, t, sub, st, kind) in BLOCKS.items():
        col = WARN if st == "HZ" else STAGE[st]
        if active is not None:
            op = .2 if dim_block(bid) else 1
        else:
            op = .2 if (stage and st != stage) else 1
        glow = active is not None and not dim_block(bid)
        sw = 4 if glow else 2
        if kind == "mux":
            o.append(f'<path d="M{x},{y} L{x+w},{y+14} L{x+w},{y+h-14} L{x},{y+h} Z" fill="{PANEL}" stroke="{col}" stroke-width="{sw}" opacity="{op}"/>')
            o.append(f'<text x="{x+w/2}" y="{y+h/2+6}" text-anchor="middle" font-size="15" font-weight="700" fill="{col}" opacity="{op}">M</text>')
            continue
        if kind == "alu":
            o.append(f'<path d="M{x},{y} L{x+w},{y+50} L{x+w},{y+h-50} L{x},{y+h} L{x},{y+h/2+26} L{x+26},{y+h/2} L{x},{y+h/2-26} Z" fill="{PANEL}" stroke="{col}" stroke-width="{sw}" opacity="{op}"/>')
            o.append(f'<text x="{x+w/2+12}" y="{y+h/2+10}" text-anchor="middle" font-size="28" font-weight="700" fill="{TEXT}" opacity="{op}">ALU</text>')
            continue
        o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{PANEL}" stroke="{col}" stroke-width="{sw}" opacity="{op}"/>')
        ty = y + h / 2 + (0 if sub else 9)
        fs = min(26 if h > 150 else 22, int(1.75 * w / max(len(t), 1)))
        o.append(f'<text x="{x+w/2}" y="{ty}" text-anchor="middle" font-size="{fs}" font-weight="700" fill="{TEXT}" opacity="{op}">{esc(t)}</text>')
        if sub:
            o.append(f'<text x="{x+w/2}" y="{ty+28}" text-anchor="middle" font-size="16" fill="{MUTED}" opacity="{op}">{esc(sub)}</text>')
    lg = [("data", "data path"), ("ctrl", "control signals"), ("fwd", "forwarding"), ("wb", "write-back"), ("br", "branch target")]
    lx = 0
    for k, lab in lg:
        c, dash = WIRE_STYLE[k]
        o.append(f'<line x1="{1190+lx}" y1="{790}" x2="{1220+lx}" y2="{790}" stroke="{c}" stroke-width="3" stroke-dasharray="{dash}"/>')
        o.append(f'<text x="{1226+lx}" y="{796}" font-size="15" fill="{MUTED}">{lab}</text>')
        lx += 112 if k != "ctrl" else 150
    o.append("</svg>")
    return "".join(o)


def arch_page(kicker, title, svg, note=""):
    tag = f'<div class="tag">{esc(note)}</div>' if note else ""
    return page(f"""<div class="frame"><div class="kicker">{esc(kicker)}</div><h2>{esc(title)}</h2>
      <div style="margin-top:26px">{svg}</div>{tag}</div>""",
                "svg{display:block;width:1740px;height:auto}")


STAGE_TEXT = {
    "IF": ("Instruction Fetch", "PC addresses instruction memory · PC + 4"),
    "ID": ("Instruction Decode", "Control unit · register read · immediate generation"),
    "EX": ("Execute", "ALU operation · branch compare · target address"),
    "MEM": ("Memory Access", "LW reads / SW writes data memory"),
    "WB": ("Write Back", "Result written to destination register"),
}


def scene_architecture():
    sc = {"aditya_01_arch_overview": arch_page("Five-stage RISC-V architecture", "IF → ID → EX → MEM → WB",
                                               arch_svg(), "Source: rtl/riscv_core.v")}
    for i, s in enumerate(["IF", "ID", "EX", "MEM", "WB"], 2):
        name, what = STAGE_TEXT[s]
        sc[f"aditya_0{i}_stage_{s}"] = arch_page(f"Stage {i-1} of 5 · {s}", f"{name}: {what}", arch_svg(stage=s))
    sc["aditya_07_hazard_paths"] = arch_page("Hazard handling", "Forwarding paths, stall and flush",
                                             arch_svg(active={"hazard", "fwa", "fwb", "FWD", "BRPATH", "pcmux"}),
                                             "rtl/hazard_unit.v · rtl/execution_unit.v")
    groups = [
        ("naveen_02_blk_fetch", "Program Counter → Instruction Memory → IF/ID", {"pcmux", "pc", "add4", "imem", "IF / ID", "IF"}),
        ("naveen_03_blk_decode", "Control Unit · Register File · Immediate Gen → ID/EX", {"ctrl", "rf", "imm", "ID / EX", "ID"}),
        ("naveen_04_blk_execute", "Forwarding muxes · ALU · branch logic → EX/MEM", {"fwa", "fwb", "alusrc", "alu", "badd", "bcmp", "EX / MEM", "EX", "FWD"}),
        ("naveen_05_blk_mem_wb", "Data Memory → MEM/WB → write-back mux → Register File", {"dmem", "wbmux", "rf", "MEM / WB", "MEM", "WB", "WBPATH"}),
        ("naveen_06_blk_pipe_regs", "Four pipeline registers carry data and control forward", {"IF / ID", "ID / EX", "EX / MEM", "MEM / WB"}),
    ]
    sc["naveen_01_block_diagram"] = arch_page("Processor block diagram", "Modules and how they connect", arch_svg(flows=True),
                                              "data path solid · control dashed")
    for key, title, act in groups:
        sc[key] = arch_page("Internal design", title, arch_svg(active=act))
    return sc


# ----------------------------------------------------------------------------
# Scenes: code close-ups (real source lines)
# ----------------------------------------------------------------------------
def code_card(path, first, last, hl=(), title="", note=""):
    from pygments import highlight
    from pygments.formatters import HtmlFormatter
    from pygments.lexers import VerilogLexer
    lines = open(os.path.join(ROOT, path)).read().split("\n")[first - 1:last]
    fmt = HtmlFormatter(style="github-dark", linenos="table", linenostart=first,
                        hl_lines=[h - first + 1 for h in hl], nowrap=False)
    code = highlight("\n".join(lines), VerilogLexer(), fmt)
    n = last - first + 1
    fs = 27 if n <= 14 else 23 if n <= 20 else 19
    css = fmt.get_style_defs(".highlight") + f"""
      .card{{margin-top:30px;background:#0d1117;border:1px solid {BORDER};border-radius:14px;overflow:hidden}}
      .bar{{background:#161b22;padding:14px 22px;font:500 20px {MONO};color:{MUTED};border-bottom:1px solid {BORDER}}}
      .highlight pre,.linenos pre{{font:{fs}px/1.5 {MONO}}}
      .highlighttable{{border-spacing:0;padding:18px 10px}} .linenos{{color:#484f58;padding-right:22px;text-align:right}}
      .highlight .hll{{background:rgba(56,189,248,.16);display:block;box-shadow:inset 4px 0 0 {ACCENT}}}
      .highlight{{background:#0d1117}}"""
    t = f'<div class="tag">{esc(note)}</div>' if note else ""
    return page(f"""<div class="frame"><div class="kicker">Verilog source</div><h2>{esc(title)}</h2>
        <div class="card"><div class="bar">{esc(path)} · lines {first}–{last}</div>{code}</div>{t}</div>""", css)


def find_line(path, needle, start=1):
    for i, l in enumerate(open(os.path.join(ROOT, path)).read().split("\n"), 1):
        if i >= start and needle in l:
            return i
    raise SystemExit(f"{needle!r} not found in {path}")


def scene_code():
    hz = "rtl/hazard_unit.v"
    fa = find_line(hz, "// Forward A Logic")
    ld = find_line(hz, "// Check for control hazards")
    core = "rtl/riscv_core.v"
    insts = [find_line(core, s) for s in ("u_imem (", "pipe_if_id u_pipe_if_id", "control_unit u_control_unit",
                                          "reg_file u_reg_file", "imm_gen u_imm_gen", "pipe_id_ex u_pipe_id_ex",
                                          "execution_unit u_execution_unit", "pipe_ex_mem u_pipe_ex_mem",
                                          "u_dmem (", "pipe_mem_wb u_pipe_mem_wb", "hazard_unit u_hazard_unit")]
    # Module map: the real instantiation lines of the top level, each with its line number.
    src = open(os.path.join(ROOT, core)).read().split("\n")
    def inst_text(n):
        line = src[n - 1].strip().rstrip("(").strip()
        if line.startswith(")"):  # parameterised: module name is on the "#(" line above
            mod = next(src[k].split()[0] for k in range(n - 2, 0, -1) if "#(" in src[k])
            line = f"{mod} {line[1:].strip()}"
        return line
    rows = "".join(f'<div class="r"><span class="ln">{n}</span><span class="m">{esc(inst_text(n))}</span></div>' for n in insts)
    css = f""".map{{margin-top:34px;background:#0d1117;border:1px solid {BORDER};border-radius:14px;padding:26px 34px;columns:2;column-gap:60px}}
      .r{{font:26px/2.05 {MONO};break-inside:avoid}} .ln{{color:#484f58;display:inline-block;width:70px;text-align:right;margin-right:26px}}
      .m{{color:#79c0ff}} .bar{{font:500 20px {MONO};color:{MUTED};margin-top:18px}}"""
    module_map = page(f"""<div class="frame"><div class="kicker">Verilog source · top level</div>
        <h2>riscv_core wires every module together</h2><div class="map">{rows}</div>
        <div class="bar">{core} · module instances</div></div>""", css)
    return {
        "aditya_08_code_forwarding": code_card(hz, fa, fa + 7, hl=(fa + 1, fa + 2, fa + 3, fa + 4),
                                               title="Forwarding: EX/MEM first, then MEM/WB"),
        "aditya_09_code_stall_flush": code_card(hz, ld, ld + 13, hl=(ld + 1, ld + 3, ld + 4, ld + 7, ld + 9, ld + 10, ld + 11),
                                                title="Flush on taken branch · 1-cycle load-use stall"),
        "naveen_07_code_pipe_if_id": code_card("rtl/pipe_if_id.v", 26, 40, hl=(31, 32, 33, 35, 36, 37),
                                               title="A pipeline register: IF/ID with flush and stall"),
        "naveen_08_code_core_modules": module_map,
    }


# ----------------------------------------------------------------------------
# Scenes: concept slides, test results, status, cards
# ----------------------------------------------------------------------------
def concept_gantt():
    st = ["IF", "ID", "EX", "MEM", "WB"]
    cell, gap, lab = 64, 6, 150

    def grid(rows, n_cycles, title, total):
        h = 40 + len(rows) * (cell + gap)
        o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{lab + n_cycles*(cell+gap)+10}" height="{h+10}" font-family="{SANS}">']
        for c in range(n_cycles):
            o.append(f'<text x="{lab + c*(cell+gap) + cell/2}" y="24" text-anchor="middle" font-size="17" fill="{MUTED}">{c+1}</text>')
        for r, start in enumerate(rows):
            y = 40 + r * (cell + gap)
            o.append(f'<text x="0" y="{y+cell/2+8}" font-size="22" font-weight="600" fill="{TEXT}">Instr {r+1}</text>')
            for c in range(n_cycles):
                o.append(f'<rect x="{lab + c*(cell+gap)}" y="{y}" width="{cell}" height="{cell}" rx="8" fill="#131d33"/>')
            for k, s in enumerate(st):
                x = lab + (start + k) * (cell + gap)
                o.append(f'<rect x="{x}" y="{y}" width="{cell}" height="{cell}" rx="8" fill="{STAGE[s]}"/>')
                o.append(f'<text x="{x+cell/2}" y="{y+cell/2+7}" text-anchor="middle" font-size="17" font-weight="700" fill="#0b1120">{s}</text>')
        o.append("</svg>")
        return f'<div class="g"><div class="gt">{title}<span>{total}</span></div>{"".join(o)}</div>'
    seq = grid([0, 5, 10], 15, "Sequential (no overlap)", "15 cycles")
    pipe = grid([0, 1, 2], 15, "Pipelined (stages overlap)", "7 cycles")
    css = f""".g{{margin-top:30px}} .gt{{font:700 30px {SANS};margin-bottom:10px}}
      .gt span{{margin-left:22px;color:{ACCENT}}}"""
    return page(f"""<div class="frame"><div class="kicker">Concept</div><h2>Sequential vs pipelined execution</h2>
       {seq}{pipe}<div class="tag">Concept illustration · ideal pipeline, no hazards · cycles = n + k − 1</div></div>""", css)


def stage_flow():
    items = "".join(
        f'<div class="s" style="border-color:{STAGE[s]}"><div class="k" style="color:{STAGE[s]}">{s}</div>'
        f'<div class="n">{STAGE_TEXT[s][0]}</div><div class="d">{STAGE_TEXT[s][1]}</div></div>'
        + ('<div class="ar">→</div>' if s != "WB" else "")
        for s in ["IF", "ID", "EX", "MEM", "WB"])
    css = f""".row{{display:flex;align-items:stretch;margin-top:120px;gap:0}}
      .s{{flex:1;background:{PANEL};border:3px solid;border-radius:18px;padding:34px 24px;min-height:330px}}
      .k{{font:800 54px {SANS}}} .n{{font:700 27px {SANS};margin-top:14px}} .d{{font:400 22px/1.45 {SANS};color:{MUTED};margin-top:16px}}
      .ar{{font:300 60px {SANS};color:{DIM};align-self:center;padding:0 12px}}"""
    return page(f"""<div class="frame"><div class="kicker">Our solution</div><h2>Five stages, one instruction entering every cycle</h2>
       <div class="row">{items}</div><div class="tag">Concept illustration</div></div>""", css)


def cpu_icon(size=420):
    pins = "".join(f'<rect x="{60+i*44}" y="0" width="14" height="40" rx="3" fill="#334155"/>'
                   f'<rect x="{60+i*44}" y="{size-40}" width="14" height="40" rx="3" fill="#334155"/>'
                   f'<rect x="0" y="{60+i*44}" width="40" height="14" rx="3" fill="#334155"/>'
                   f'<rect x="{size-40}" y="{60+i*44}" width="40" height="14" rx="3" fill="#334155"/>' for i in range(7))
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}">{pins}'
            f'<rect x="40" y="40" width="{size-80}" height="{size-80}" rx="26" fill="{PANEL}" stroke="{ACCENT}" stroke-width="4"/>'
            f'<text x="{size/2}" y="{size/2-6}" text-anchor="middle" font-family="{SANS}" font-size="52" font-weight="800" fill="{TEXT}">RV32I</text>'
            f'<text x="{size/2}" y="{size/2+40}" text-anchor="middle" font-family="{SANS}" font-size="24" fill="{MUTED}">5-stage pipeline</text></svg>')


def scene_slides():
    lf = log_facts(run_log())
    sy = synth_facts()
    if not lf["ok"] or lf["failed"]:
        raise SystemExit("Test suite is failing - refusing to render result slides.")
    title = page(f"""<div class="frame" style="display:flex;align-items:center;gap:110px">
        <div style="flex:1"><div class="kicker">Modern Computer Architecture · Phase I</div>
        <h1 style="font-size:84px;margin-top:22px">5-Stage Pipelined<br>RISC-V Processor</h1>
        <div class="sub" style="margin-top:34px">Designed in Verilog · verified by simulation</div>
        <div style="margin-top:60px;font:700 30px {SANS};letter-spacing:.14em;color:{ACCENT}">TEAM PROTOCOLX</div></div>
        {cpu_icon()}</div>""", brand=False)
    one = "".join(f'<div class="cy"><div class="b" style="background:{STAGE[s]}">{s}</div></div>' for s in ["IF", "ID", "EX", "MEM", "WB"])
    idle = "".join(f'<div class="cy"><div class="b idle">{s}</div></div>' for s in ["IF", "ID", "EX", "MEM", "WB"])
    problem = page(f"""<div class="frame"><div class="kicker">The problem</div>
        <h2>A simple processor finishes one instruction<br>before it starts the next</h2>
        <div class="row"><div class="lab">Instruction 1</div>{one}</div>
        <div class="row"><div class="lab">Instruction 2</div>{idle}<div class="w">waits…</div></div>
        <div class="sub" style="margin-top:60px">Most of the hardware sits idle each cycle → low throughput.</div>
        <div class="tag">Concept illustration</div></div>""",
                   f""".row{{display:flex;align-items:center;gap:14px;margin-top:90px}} .lab{{width:250px;font:600 30px {SANS}}}
        .b{{width:140px;height:96px;border-radius:14px;display:flex;align-items:center;justify-content:center;font:800 30px {SANS};color:#0b1120}}
        .idle{{background:#131d33;color:{DIM};border:2px dashed #2a3a5a}} .w{{font:italic 28px {SANS};color:{MUTED};margin-left:20px}}""")
    obj_items = [("Design", "a five-stage RV32I pipeline with hazard handling"),
                 ("Implement", "it as modular, synthesizable Verilog"),
                 ("Verify", "it with self-checking testbenches and waveforms")]
    objective = page(f"""<div class="frame"><div class="kicker">Project objective</div><h2>What we set out to do</h2>
        {''.join(f'<div class="o"><div class="n">{i}</div><div><b>{a}</b> {esc(b)}</div></div>' for i, (a, b) in enumerate(obj_items, 1))}</div>""",
                     f""".o{{display:flex;align-items:center;gap:36px;margin-top:96px;font:400 40px {SANS};color:{MUTED}}}
        .o b{{color:{TEXT}}} .n{{width:84px;height:84px;border-radius:50%;border:3px solid {ACCENT};color:{ACCENT};
        display:flex;align-items:center;justify-content:center;font:800 38px {SANS};flex:none}}""")
    # Test results: lines copied from the real log.
    names = re.findall(r">>> \d+\. Running (.*?)\.\.\.", run_log_cache[0])
    rows = "".join(f'<div class="l"><span class="ok">✔</span> <span class="nm">{esc(n)}</span><span class="sm">{esc(s.strip())}</span></div>'
                   for n, s in zip(names, lf["summaries"]))
    term = page(f"""<div class="frame"><div class="kicker">Simulation · Icarus Verilog</div><h2>Full test suite: {lf['passed']} checks, {lf['failed']} failures</h2>
        <div class="t"><div class="bar"><i></i><i></i><i></i><span>$ make test</span></div>{rows}
        <div class="l cpi">{esc(f"instructions = {lf['instr']} | cycles = {lf['cycles']} | stalls = {lf['stalls']} | branch flushes = {lf['flushes']}")}</div>
        <div class="l fin">ALL VERIFICATION SUITES COMPLETED SUCCESSFULLY</div></div>
        <div class="src">simulation/simulation_results.log</div></div>""",
                f""".t{{margin-top:30px;background:#05080f;border:1px solid {BORDER};border-radius:14px;padding:0 0 22px;font:23px/1.95 {MONO}}}
        .bar{{background:#111827;padding:12px 20px;margin-bottom:12px;border-radius:14px 14px 0 0;color:{MUTED}}}
        .bar i{{display:inline-block;width:14px;height:14px;border-radius:50%;background:#374151;margin-right:8px}} .bar span{{margin-left:16px}}
        .l{{padding:0 30px;display:flex;gap:14px}} .ok{{color:{OK}}} .nm{{color:{TEXT};flex:1}} .sm{{color:{OK}}}
        .cpi{{color:{ACCENT};margin-top:10px}} .fin{{color:{OK};font-weight:700}}""")
    done = ["5-stage RV32I pipeline: IF · ID · EX · MEM · WB", "4 pipeline registers carrying data + control",
            "EX/MEM and MEM/WB forwarding", "1-cycle load-use stall · flush on taken branch",
            f"{lf['suites']} self-checking testbenches · {lf['passed']}/{lf['passed']+lf['failed']} checks pass",
            "Synthesizes with Yosys (Xilinx 7-series mapping)"]
    wip = ["Byte / half-word load alignment unit: tested alone, not yet integrated",
           "Larger benchmark programs and baseline (single-cycle) comparison",
           "FPGA place & route: maximum frequency (Fmax)"]
    status = page(f"""<div class="frame"><div class="kicker">Phase I status</div><h2>What works today, and what is next</h2>
        <div class="cols"><div class="c"><div class="h ok">Implemented & verified</div>{''.join(f'<div class="i"><span class="ok">✔</span>{esc(d)}</div>' for d in done)}</div>
        <div class="c"><div class="h wip">Work in progress</div>{''.join(f'<div class="i"><span class="wip">◐</span>{esc(d)}</div>' for d in wip)}</div></div>
        <div class="kpis"><div class="k"><b>{lf['cpi']}</b>measured CPI<small>{lf['instr']} instr · {lf['cycles']} cycles · incl. fill</small></div>
        <div class="k"><b>{lf['cpi_ss']}</b>steady-state CPI<small>excl. 4-cycle pipeline fill</small></div>
        <div class="k"><b>{sy['luts']:,}</b>LUTs<small>Yosys estimate, not Vivado</small></div>
        <div class="k"><b>{sy['ffs']:,}</b>flip-flops<small>Yosys estimate</small></div></div>
        <div class="src">tb_riscv_subset.v · synth/utilization.txt</div></div>""",
                  f""".cols{{display:flex;gap:50px;margin-top:34px}} .c{{flex:1;background:{PANEL};border:1px solid {BORDER};border-radius:16px;padding:26px 32px}}
        .h{{font:700 28px {SANS};margin-bottom:14px}} .i{{font:400 24px/1.4 {SANS};margin:12px 0;display:flex;gap:16px;color:{TEXT}}}
        .ok{{color:{OK}}} .wip{{color:{WARN}}}
        .kpis{{display:flex;gap:28px;margin-top:30px}} .k{{flex:1;background:{PANEL};border:1px solid {BORDER};border-radius:16px;padding:20px 26px;font:500 22px {SANS};color:{MUTED}}}
        .k b{{display:block;font:800 52px {SANS};color:{ACCENT}}} .k small{{display:block;font:400 17px {SANS};color:{DIM};margin-top:6px}}""")
    team = ["Shagun Vishnoi", "Archit Mamodiya", "Aditya Raj", "Naveen Kumar"]
    closing = page(f"""<div class="frame" style="display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center">
        <div class="kicker">Thank you</div><h1 style="font-size:78px">ProtocolX</h1>
        <div class="sub" style="margin-top:14px">5-Stage Pipelined RISC-V Processor · Phase I</div>
        <div style="margin-top:56px;font:600 34px {SANS};color:{TEXT}">{' · '.join(team)}</div>
        <div style="margin-top:56px;font:400 26px {MONO};color:{ACCENT}">github.com/naveendhaterwal/protocolx-riscv-pipelined-processor</div></div>""", brand=False)
    return {"shagun_01_title": title, "shagun_02_problem": problem, "shagun_03_objective": objective,
            "archit_01_seq_vs_pipe": concept_gantt(), "archit_02_stage_flow": stage_flow(),
            "aditya_13_test_results": term, "naveen_09_status": status, "naveen_10_closing": closing}


run_log_cache = [""]
_orig_run_log = run_log


def run_log():  # noqa: F811 - cache the single real run used by all slides
    if not run_log_cache[0]:
        run_log_cache[0] = _orig_run_log()
    return run_log_cache[0]


def scene_lower_thirds():
    people = [("shagun", "Shagun Vishnoi", "IEEE Report & Documentation"),
              ("archit", "Archit Mamodiya", "Literature Review & Research"),
              ("aditya", "Aditya Raj", "Pipeline Design & Verification"),
              ("naveen", "Naveen Kumar", "Project Lead & RTL Developer")]
    css = f"""html,body{{background:transparent!important;background-image:none!important}}
      .lt{{position:absolute;left:90px;bottom:90px;background:rgba(11,17,32,.92);border:1px solid {BORDER};
      border-left:6px solid {ACCENT};border-radius:12px;padding:20px 34px}}
      .lt b{{display:block;font:700 40px {SANS}}} .lt span{{font:400 24px {SANS};color:{MUTED}}}"""
    out = {f"lower_third_{k}": page(f'<div class="lt"><b>{n}</b><span>{r}</span></div>', css, brand=False) for k, n, r in people}
    return out, set(out)


# ----------------------------------------------------------------------------
# Rendering
# ----------------------------------------------------------------------------
def render(scenes, transparent=()):
    from playwright.sync_api import sync_playwright
    os.makedirs(OUT, exist_ok=True)
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": 1920, "height": 1080})
        for name, doc in scenes.items():
            pg.set_content(doc, wait_until="load")
            pg.screenshot(path=os.path.join(OUT, name + ".png"), omit_background=name in transparent)
            print("rendered", name)
        b.close()


BUILDERS = [scene_waveforms, scene_architecture, scene_code, scene_slides, scene_lower_thirds]

if __name__ == "__main__":
    flt = sys.argv[1] if len(sys.argv) > 1 else ""
    scenes, transparent = {}, set()
    for fn in BUILDERS:
        res = fn()
        if isinstance(res, tuple):
            res, tr = res
            transparent |= tr
        scenes.update(res)
    scenes = {k: v for k, v in scenes.items() if flt in k}
    render(scenes, transparent)
