# bench_fib.s - 30th Fibonacci number, iteratively.   Expected 832040
# Exercises: tight loop of dependent ALU instructions (forwarding every cycle).
    li   x30, 0x800000F0
    li   a0, 0                    # fib(0)
    li   a1, 1                    # fib(1)
    li   s1, 30
loop:
    add  t0, a0, a1
    mv   a0, a1
    mv   a1, t0
    addi s1, s1, -1
    bnez s1, loop
    li   t1, 832040
    bne  a0, t1, fail
    li   t0, 1
    sw   t0, 0(x30)
done: j done
fail:
    li   t0, 2
    sw   t0, 0(x30)
    j    done
