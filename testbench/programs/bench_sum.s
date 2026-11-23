# bench_sum.s - fill an array of 64 words (0, 3, 6, ...) and add them up.
# Exercises: loads, stores, load-use stalls, a backward branch loop.   Expected sum = 6048
    li   x30, 0xFFC               # TOHOST = last RAM word
    li   s0, 0x100                # array base address
    li   s1, 64                   # N
    mv   t0, s0
    li   t1, 0
init:
    sw   t1, 0(t0)
    addi t1, t1, 3
    addi t0, t0, 4
    addi s1, s1, -1
    bnez s1, init
    mv   t0, s0
    li   s1, 64
    li   a0, 0
sum:
    lw   t2, 0(t0)
    add  a0, a0, t2               # uses the loaded value immediately -> 1-cycle stall
    addi t0, t0, 4
    addi s1, s1, -1
    bnez s1, sum
    li   t3, 6048
    bne  a0, t3, fail
    li   t0, 1
    sw   t0, 0(x30)
done: j done
fail:
    li   t0, 2
    sw   t0, 0(x30)
    j    done
