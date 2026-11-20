# bench_sort.s - bubble sort of 32 pseudo-random words, then check the order and the sum.
# Exercises: data-dependent branches (hard to predict), loads/stores.   Expected sum = 17008
    li   x30, 0x800000F0
    li   s0, 0x100                # array base
    li   s1, 32                   # N
    li   t1, 7                    # seed
    mv   t0, s0
    mv   t2, s1
init:                             # x = (5x + 1) mod 1024
    slli t3, t1, 2
    add  t1, t3, t1
    addi t1, t1, 1
    andi t1, t1, 1023
    sw   t1, 0(t0)
    addi t0, t0, 4
    addi t2, t2, -1
    bnez t2, init
    addi s2, s1, -1               # i = N-1 passes
outer:
    mv   t0, s0
    mv   t2, s2
inner:
    lw   t3, 0(t0)
    lw   t4, 4(t0)
    ble  t3, t4, noswap           # already in order?
    sw   t4, 0(t0)                # swap
    sw   t3, 4(t0)
noswap:
    addi t0, t0, 4
    addi t2, t2, -1
    bnez t2, inner
    addi s2, s2, -1
    bnez s2, outer
    mv   t0, s0                   # check: ascending order and same sum
    addi t2, s1, -1
    lw   a0, 0(t0)
check:
    lw   t3, 0(t0)
    lw   t4, 4(t0)
    bgt  t3, t4, fail
    add  a0, a0, t4
    addi t0, t0, 4
    addi t2, t2, -1
    bnez t2, check
    li   t3, 17008
    bne  a0, t3, fail
    li   t0, 1
    sw   t0, 0(x30)
done: j done
fail:
    li   t0, 2
    sw   t0, 0(x30)
    j    done
