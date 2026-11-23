# bench_matmul.s - multiply two 8x8 integer matrices, C = A * B, with a
# SHIFT-AND-ADD multiply (RV32I has no multiply instruction).
#   A[i][j] = i + j,   B[i][j] = i + 2j,   checksum = sum of all C[i][j] = 40320
# Exercises: nested loops, address arithmetic, loads, data-dependent branches.
# (x30 = t5 and x31 = t6 are reserved for the result address, so we avoid them.)
    li   x30, 0xFFC               # TOHOST = last RAM word
    li   s0, 0x100                # A
    li   s1, 0x200                # B
    li   s2, 0x300                # C
    li   s6, 8                    # N
    li   s3, 0                    # i
initi:
    li   s4, 0                    # j
initj:
    slli t0, s3, 3
    add  t0, t0, s4
    slli t0, t0, 2                # byte offset of [i][j] = (i*8 + j) * 4
    add  t1, s3, s4
    add  t2, s0, t0
    sw   t1, 0(t2)                # A[i][j] = i + j
    slli t3, s4, 1
    add  t3, s3, t3
    add  t2, s1, t0
    sw   t3, 0(t2)                # B[i][j] = i + 2j
    addi s4, s4, 1
    blt  s4, s6, initj
    addi s3, s3, 1
    blt  s3, s6, initi
    li   s3, 0
    li   a0, 0                    # checksum
mi:
    li   s4, 0
mj:
    li   s5, 0                    # k
    li   a1, 0                    # C[i][j] accumulator
mk:
    slli t0, s3, 3
    add  t0, t0, s5
    slli t0, t0, 2
    add  t0, s0, t0
    lw   t1, 0(t0)                # A[i][k]  (multiplicand)
    slli t2, s5, 3
    add  t2, t2, s4
    slli t2, t2, 2
    add  t2, s1, t2
    lw   t3, 0(t2)                # B[k][j]  (multiplier)
    li   t4, 0                    # product
mulloop:
    beqz t3, muldone              # multiplier used up?
    andi a2, t3, 1
    beqz a2, noadd                # lowest bit 0: nothing to add
    add  t4, t4, t1
noadd:
    slli t1, t1, 1                # multiplicand * 2
    srli t3, t3, 1                # next multiplier bit
    j    mulloop
muldone:
    add  a1, a1, t4
    addi s5, s5, 1
    blt  s5, s6, mk
    slli t0, s3, 3
    add  t0, t0, s4
    slli t0, t0, 2
    add  t0, s2, t0
    sw   a1, 0(t0)                # C[i][j]
    add  a0, a0, a1
    addi s4, s4, 1
    blt  s4, s6, mj
    addi s3, s3, 1
    blt  s3, s6, mi
    li   t0, 40320
    bne  a0, t0, fail
    li   t0, 1
    sw   t0, 0(x30)
done: j done
fail:
    li   t0, 2
    sw   t0, 0(x30)
    j    done
