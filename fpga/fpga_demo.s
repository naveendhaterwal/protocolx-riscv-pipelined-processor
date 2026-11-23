# =============================================================================
# fpga_demo.s - demo program for fpga/fpga_top.v: an endless loop whose results
# show up on the LEDs (low 16 bits of every value written back).
# It deliberately uses EVERY instruction the core supports at least once.
# That matters for synthesis: if the program never used e.g. SRA or BGEU, the
# tools could prove that hardware is never needed and delete it, and our
# Fmax / area numbers would describe a smaller CPU than the one we built.
# Assemble:  python3 scripts/rvasm.py fpga/fpga_demo.s
# =============================================================================
    li    s3, 0x100               # scratch RAM
    li    a0, 1
main:
    # --- register-register ALU
    add   a1, a0, a0
    sub   a2, a1, a0
    and   a3, a1, a0
    or    a4, a1, a0
    xor   a5, a1, a0
    sll   a6, a0, a2
    srl   a7, a1, a0
    sra   t2, a1, a0
    slt   t3, a0, a1
    sltu  t4, a0, a1
    # --- register-immediate ALU
    addi  t0, a0, 7
    slti  t3, a0, 100
    sltiu t4, a0, 100
    xori  a5, a5, 0x55
    ori   a4, a4, 3
    andi  a3, a3, 0xFF
    slli  a6, a6, 2
    srli  a7, a7, 1
    srai  t2, t2, 3
    lui   t5, 0x12345
    auipc t6, 0
    # --- memory (one load is used immediately: a load-use stall)
    sw    a1, 0(s3)
    sw    a2, 4(s3)
    lw    t3, 0(s3)
    add   a0, a0, t3
    lw    t4, 4(s3)
    # --- every branch type, then a function call (jal) and return (jalr)
    beq   a0, x0, skip
    bne   a0, x0, b1
b1: blt   a0, x0, skip
    bge   a0, x0, b2
b2: bltu  a0, a1, b3
b3: bgeu  a0, a1, skip
    call  mix                     # jal ra, mix
skip:
    add   a0, a0, a5
    add   a0, a0, a7
    add   a0, a0, t4
    andi  a0, a0, 0x3FF
    ori   a0, a0, 1               # never zero, so the values keep changing
    j     main

mix:                              # tiny function: a0 = a0 xor (a0 >> 3)
    srli  t0, a0, 3
    xor   a0, a0, t0
    ret                           # jalr x0, 0(ra)
