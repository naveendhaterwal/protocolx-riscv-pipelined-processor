| Configuration | Fmax (MHz) | Critical path through | LUT4 | Flip-flops | DSP (18x18) |
|---|---|---|---|---|---|
| Pipeline (5-stage), RV32IM | **5.5** | muldiv, execution_unit | 14,964 | 2,022 | 4 |
| Single-cycle, RV32IM | **4.9** | muldiv, exec, dmem | 14,252 | 962 | 4 |
| Pipeline (5-stage), M removed* | **62.4** | dmem | 6,865 | 2,022 | 0 |
| Single-cycle, M removed* | **30.4** | dmem | 6,336 | 962 | 0 |

\* M removed = multiply/divide unit replaced by a stub (fpga/muldiv_stub.v) to measure the rest of each core.

Execution time, full RV32IM cores: time = cycles / Fmax

| Benchmark | Single-cycle | Pipeline + predictor | Speed-up |
|---|---|---|---|
| fib | 32.4 µs | 30.8 µs | **1.05×** |
| matmul | 1,748.6 µs | 1,711.9 µs | **1.02×** |
| sort | 804.3 µs | 904.6 µs | **0.89×** |
| sum | 132.4 µs | 133.9 µs | **0.99×** |

Execution time, cores without the M unit (benchmarks that use MUL excluded): time = cycles / Fmax

| Benchmark | Single-cycle | Pipeline + predictor | Speed-up |
|---|---|---|---|
| fib | 5.3 µs | 2.7 µs | **1.95×** |
| sort | 130.5 µs | 79.0 µs | **1.65×** |
| sum | 21.5 µs | 11.7 µs | **1.84×** |

