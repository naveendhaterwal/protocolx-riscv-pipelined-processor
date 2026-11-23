#!/usr/bin/env python3
"""
Reads fpga/results/*.nextpnr.log (from scripts/run_fmax.sh) and
docs/figures/benchmark_results.csv (from scripts/run_benchmarks.sh) and prints
two Markdown tables:
  1. Fmax, resources and where the critical path is, for each design
  2. Execution time of each benchmark = cycles / Fmax, and the speed-up
Also writes fpga/results/SUMMARY.md.
Run from anywhere:  python3 scripts/summarize_fmax.py
"""
import csv
import os
import re
from collections import Counter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RES = os.path.join(ROOT, "fpga", "results")
CONFIGS = [("pipeline", "5-stage pipeline"), ("single_cycle", "Single-cycle baseline")]
MODULES = ["u_alu", "u_execution_unit", "u_exec", "u_hazard_unit", "u_dmem", "u_imem", "u_reg_file",
           "u_regs", "u_control_unit", "u_control", "u_imm_gen", "u_imm"]


def parse(name):
    log = open(os.path.join(RES, name + ".nextpnr.log")).read()
    fmax = re.findall(r"Max frequency for clock '[^']*': ([\d.]+) MHz", log)
    util = {k: int(v) for k, v in re.findall(r"Info:\s+(TRELLIS_COMB|TRELLIS_FF|MULT18X18D|TRELLIS_RAMW):\s+(\d+)/", log)}
    crit = log.split("Critical path report for clock")[1] if "Critical path report for clock" in log else ""
    crit = crit.split("Critical path report")[0]
    hits = Counter({m: len(re.findall(r"\b" + m + r"\b", crit)) for m in MODULES})
    where = ", ".join(m.replace("u_", "") for m, c in hits.most_common(3) if c)
    return dict(fmax=float(fmax[-1]) if fmax else None, util=util, where=where or "-")


def main():
    out, data = [], {}
    out.append("| Design | Fmax (MHz) | Critical path through | LUT4 | Flip-flops |")
    out.append("|---|---|---|---|---|")
    for key, label in CONFIGS:
        if not os.path.exists(os.path.join(RES, key + ".nextpnr.log")):
            out.append(f"| {label} | (not run) | | | |")
            continue
        d = parse(key)
        if d["fmax"] is None:
            out.append(f"| {label} | (no Fmax in log: run failed) | | | |")
            continue
        data[key] = d
        u = d["util"]
        out.append(f"| {label} | **{d['fmax']:.1f}** | {d['where']} | {u.get('TRELLIS_COMB', 0):,} | {u.get('TRELLIS_FF', 0):,} |")

    csvp = os.path.join(ROOT, "docs", "figures", "benchmark_results.csv")
    if os.path.exists(csvp) and {"pipeline", "single_cycle"} <= data.keys():
        f_p, f_s = data["pipeline"]["fmax"], data["single_cycle"]["fmax"]
        out.append(f"\nClock speed-up from pipelining: **{f_p / f_s:.2f}x** ({f_p:.1f} MHz vs {f_s:.1f} MHz).\n")
        out.append("Execution time = cycles / Fmax (single-cycle cycles = N, pipeline cycles measured):\n")
        out.append("| Benchmark | Single-cycle | Pipeline | Speed-up |")
        out.append("|---|---|---|---|")
        for r in sorted(csv.DictReader(open(csvp)), key=lambda r: r["benchmark"]):
            t_s = int(r["instructions"]) / f_s
            t_p = int(r["pipeline_cycles"]) / f_p
            out.append(f"| {r['benchmark']} | {t_s:,.1f} µs | {t_p:,.1f} µs | **{t_s / t_p:.2f}x** |")
    text = "\n".join(out)
    print(text)
    open(os.path.join(RES, "SUMMARY.md"), "w").write(text + "\n")


if __name__ == "__main__":
    main()
