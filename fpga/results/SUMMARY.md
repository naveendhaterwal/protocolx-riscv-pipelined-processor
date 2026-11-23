| Design | Fmax (MHz) | Critical path through | LUT4 | Flip-flops |
|---|---|---|---|---|
| 5-stage pipeline | **67.8** | dmem | 5,100 | 1,541 |
| Single-cycle baseline | **38.8** | dmem | 5,161 | 722 |

Clock speed-up from pipelining: **1.75x** (67.8 MHz vs 38.8 MHz).

Execution time = cycles / Fmax (single-cycle cycles = N, pipeline cycles measured):

| Benchmark | Single-cycle | Pipeline | Speed-up |
|---|---|---|---|
| fib | 4.1 µs | 3.3 µs | **1.26x** |
| matmul | 560.5 µs | 432.8 µs | **1.30x** |
| sort | 102.4 µs | 91.9 µs | **1.12x** |
| sum | 16.9 µs | 14.4 µs | **1.17x** |
