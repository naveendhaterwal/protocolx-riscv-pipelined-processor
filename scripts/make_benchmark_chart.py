#!/usr/bin/env python3
"""
Runs scripts/run_benchmarks.sh (real simulations) and draws docs/figures/benchmark_cpi.png:
for every benchmark, the pipeline's CPI split into where the cycles go:
    1.00        useful work (one cycle per instruction, the single-cycle CPI)
  + fill        4 cycles to fill the pipeline at the start
  + load-use    1 stall cycle per load-use hazard
  + flushes     2 wasted cycles per taken branch / jump
CPI = (N + 4 + stalls + 2 * flushes) / N.
Run from anywhere:  python3 scripts/make_benchmark_chart.py
"""
import csv
import os
import subprocess

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
subprocess.run(["bash", "scripts/run_benchmarks.sh"], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
rows = list(csv.DictReader(open(os.path.join(ROOT, "docs", "figures", "benchmark_results.csv"))))
if not rows:
    raise SystemExit("no benchmark results")

names = [r["benchmark"] for r in rows]
N = [int(r["instructions"]) for r in rows]
fill = [4 / n for n in N]
stall = [int(r["stalls"]) / n for r, n in zip(rows, N)]
flush = [2 * int(r["flushes"]) / n for r, n in zip(rows, N)]
cpi = [float(r["cpi"]) for r in rows]

fig, ax = plt.subplots(figsize=(9, 4.4), dpi=160)
x = range(len(rows))
parts = [("Useful work (1.00 = single-cycle CPI)", [1.0] * len(rows), "#94a3b8"),
         ("Pipeline fill (4 cycles)", fill, "#a78bfa"),
         ("Load-use stalls (1 cycle each)", stall, "#f59e0b"),
         ("Branch / jump flushes (2 cycles each)", flush, "#0284c7")]
bottom = [0.0] * len(rows)
for label, vals, col in parts:
    ax.bar(x, vals, 0.55, bottom=bottom, label=label, color=col)
    bottom = [b + v for b, v in zip(bottom, vals)]
for xi, c in zip(x, cpi):
    ax.text(xi, c + 0.02, f"CPI {c:.2f}", ha="center", va="bottom", fontsize=9, fontweight="bold")
ax.set_xticks(list(x))
ax.set_xticklabels([f"{n}\n({k:,} instr.)" for n, k in zip(names, N)])
ax.set_ylabel("Cycles per instruction (CPI)")
ax.set_ylim(0, max(cpi) * 1.22)
ax.set_title("Where the pipeline's cycles go (measured; single-cycle core is CPI 1.00)")
ax.spines[["top", "right"]].set_visible(False)
ax.legend(frameon=False, fontsize=8, loc="upper left")
fig.tight_layout()
out = os.path.join(ROOT, "docs", "figures", "benchmark_cpi.png")
fig.savefig(out)
print("wrote", out)
