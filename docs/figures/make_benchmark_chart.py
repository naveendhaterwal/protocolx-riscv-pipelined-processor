#!/usr/bin/env python3
"""
Runs tools/run_benchmarks.sh (real simulations) and draws docs/figures/benchmark_cpi.png
plus docs/figures/benchmark_results.csv (cycles, CPI and IPC for every design).
Run from the repo root:  python3 docs/figures/make_benchmark_chart.py
"""
import csv
import os
import re
import subprocess

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
out = subprocess.run(["bash", "tools/run_benchmarks.sh"], cwd=ROOT, check=True,
                     capture_output=True, text=True).stdout
rows = []
for line in out.splitlines():
    m = re.match(r"(bench_\w+)\s*\|\s*(\d+) cyc, CPI ([\d.]+)\s*\|\s*(\d+) cyc, CPI ([\d.]+)\s*\|\s*(\d+) cyc, CPI ([\d.]+)", line)
    if m:
        name = m.group(1).replace("bench_", "")
        rows.append((name, int(m.group(2)), float(m.group(3)), int(m.group(4)), float(m.group(5)),
                     int(m.group(6)), float(m.group(7))))
if not rows:
    raise SystemExit("no benchmark results parsed:\n" + out)

here = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(here, "benchmark_results.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["benchmark", "design", "cycles", "CPI", "IPC"])
    for name, c0, p0, c1, p1, c2, p2 in rows:
        for design, c, p in (("single-cycle", c0, p0), ("pipeline, no predictor", c1, p1),
                             ("pipeline + 2-bit predictor", c2, p2)):
            w.writerow([name, design, c, f"{p:.3f}", f"{1 / p:.3f}"])

names = [r[0] for r in rows]
x = range(len(rows))
bw = 0.26
fig, ax = plt.subplots(figsize=(9, 4.2), dpi=160)
series = [("Single-cycle (baseline)", [r[2] for r in rows], "#94a3b8"),
          ("Pipeline, no predictor", [r[4] for r in rows], "#f59e0b"),
          ("Pipeline + 2-bit predictor", [r[6] for r in rows], "#0284c7")]
for i, (label, vals, col) in enumerate(series):
    bars = ax.bar([xi + (i - 1) * bw for xi in x], vals, bw, label=label, color=col)
    for b, v in zip(bars, vals):
        ax.text(b.get_x() + b.get_width() / 2, v + 0.02, f"{v:.2f}", ha="center", va="bottom", fontsize=8)
ax.set_xticks(list(x))
ax.set_xticklabels(names)
ax.set_ylabel("CPI (cycles per instruction)")
ax.set_ylim(0, max(r[4] for r in rows) * 1.2)
ax.axhline(1.0, color="#475569", lw=0.8, ls="--")
ax.set_title("Measured CPI per benchmark (hardware counters, Icarus Verilog)")
ax.spines[["top", "right"]].set_visible(False)
ax.legend(frameon=False, fontsize=8, loc="upper left")
fig.tight_layout()
fig.savefig(os.path.join(here, "benchmark_cpi.png"))
print("wrote benchmark_cpi.png and benchmark_results.csv")
