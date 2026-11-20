# bench_matmul.s - multiply two 8x8 integer matrices with MUL, C = A * B.
#   A[i][j] = i + j,   B[i][j] = i - 2j,   checksum = sum of all C[i][j] = -9856
# Exercises: RV32M multiply, nested loops, address arithmetic, loads.
    li   x30, 0x800000F0
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
    sub  t3, s3, t3
    add  t2, s1, t0
    sw   t3, 0(t2)                # B[i][j] = i - 2j
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
    lw   t1, 0(t0)                # A[i][k]
    slli t2, s5, 3
    add  t2, t2, s4
    slli t2, t2, 2
    add  t2, s1, t2
    lw   t3, 0(t2)                # B[k][j]
    mul  t4, t1, t3
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
    li   t0, -9856
    bne  a0, t0, fail
    li   t0, 1
    sw   t0, 0(x30)
done: j done
fail:
    li   t0, 2
    sw   t0, 0(x30)
    j    done
