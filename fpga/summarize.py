#!/usr/bin/env python3
"""
Reads fpga/results/*.nextpnr.log (from fpga/run_fmax.sh) and
docs/figures/benchmark_results.csv, and prints Markdown tables:
  1. Fmax, resources and where the critical path is, for each configuration
  2. Execution time of each benchmark = cycles / Fmax
Run from the repo root:  python3 fpga/summarize.py
"""
import csv
import os
import re
from collections import Counter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RES = os.path.join(ROOT, "fpga", "results")
CONFIGS = [("pipeline_rv32im", "Pipeline (5-stage), RV32IM"),
           ("single_cycle_rv32im", "Single-cycle, RV32IM"),
           ("pipeline_rv32i", "Pipeline (5-stage), M removed*"),
           ("single_cycle_rv32i", "Single-cycle, M removed*")]
MODULES = ["u_muldiv", "u_alu", "u_hazard_unit", "u_csr_unit", "u_branch_predictor", "u_imem", "u_dmem",
           "u_reg_file", "u_regs", "u_control_unit", "u_control", "u_execution_unit", "u_exec", "u_timer",
           "u_gpio", "u_mem_align", "u_ld", "u_st", "u_store_align", "u_imm_gen", "u_imm"]


def parse(name):
    log = open(os.path.join(RES, name + ".nextpnr.log")).read()
    fmax = re.findall(r"Max frequency for clock '[^']*': ([\d.]+) MHz", log)
    util = {k: int(v) for k, v in re.findall(r"Info:\s+(TRELLIS_COMB|TRELLIS_FF|MULT18X18D|TRELLIS_RAMW):\s+(\d+)/", log)}
    crit = log.split("Critical path report for clock")[1] if "Critical path report for clock" in log else ""
    crit = crit.split("Critical path report")[0]
    hits = Counter()
    for m in MODULES:
        hits[m] = len(re.findall(r"\b" + m + r"\b", crit))
    delay = re.findall(r"Info:\s+\S+\s+[\d.]+\s+([\d.]+)\s", crit)
    where = ", ".join(m.replace("u_", "") for m, c in hits.most_common(3) if c)
    return dict(fmax=float(fmax[-1]) if fmax else None, util=util, where=where or "-",
                crit_ns=float(delay[-1]) if delay else None)


def main():
    data = {}
    print("| Configuration | Fmax (MHz) | Critical path through | LUT4 | Flip-flops | DSP (18x18) |")
    print("|---|---|---|---|---|---|")
    for key, label in CONFIGS:
        p = os.path.join(RES, key + ".nextpnr.log")
        if not os.path.exists(p):
            print(f"| {label} | (not run) | | | | |")
            continue
        d = parse(key)
        if d["fmax"] is None:
            print(f"| {label} | (no Fmax in log: run not finished or failed) | | | | |")
            continue
        data[key] = d
        u = d["util"]
        print(f"| {label} | **{d['fmax']:.1f}** | {d['where']} | {u.get('TRELLIS_COMB', 0):,} | "
              f"{u.get('TRELLIS_FF', 0):,} | {u.get('MULT18X18D', 0)} |")
    print("\n\\* M removed = multiply/divide unit replaced by a stub (fpga/muldiv_stub.v) to measure the rest of each core.\n")

    csvp = os.path.join(ROOT, "docs", "figures", "benchmark_results.csv")
    if not (os.path.exists(csvp) and {"pipeline_rv32im", "single_cycle_rv32im"} <= data.keys()):
        return
    rows = list(csv.DictReader(open(csvp)))
    cyc = {(r["benchmark"], r["design"]): int(r["cycles"]) for r in rows}
    benches = sorted({r["benchmark"] for r in rows})
    for suffix, title in (("rv32im", "full RV32IM cores"), ("rv32i", "cores without the M unit (benchmarks that use MUL excluded)")):
        sc, pl = data.get("single_cycle_" + suffix), data.get("pipeline_" + suffix)
        if not (sc and pl):
            continue
        print(f"Execution time, {title}: time = cycles / Fmax\n")
        print("| Benchmark | Single-cycle | Pipeline + predictor | Speed-up |")
        print("|---|---|---|---|")
        for b in benches:
            if suffix == "rv32i" and b == "matmul":
                continue
            t_sc = cyc[(b, "single-cycle")] / sc["fmax"]
            t_pl = cyc[(b, "pipeline + 2-bit predictor")] / pl["fmax"]
            print(f"| {b} | {t_sc:,.1f} µs | {t_pl:,.1f} µs | **{t_sc / t_pl:.2f}×** |")
        print()


if __name__ == "__main__":
    main()
