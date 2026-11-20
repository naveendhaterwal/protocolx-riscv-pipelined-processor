# =============================================================================
# fpga_demo.s - demo program for fpga/fpga_top.v (a Basys-3-style board):
#   * LEDs[7:0]  = a counter advanced by the TIMER INTERRUPT
#   * LEDs[15:8] = result of a small calculation on the switch value
# It deliberately uses EVERY instruction type the core supports at least once.
# That matters for synthesis: if the program never used e.g. DIV or MRET, the
# tools could prove that hardware is never needed and delete it, and our
# Fmax / area numbers would describe a smaller CPU than the one we built.
# Assemble:  python3 tools/rvasm.py fpga/fpga_demo.s
# =============================================================================
    la    t0, handler
    csrw  mtvec, t0
    li    s0, 0x80000000          # GPIO base (+0 LEDs, +4 switches)
    li    s1, 0x80000010          # timer base (+0 mtime, +8 mtimecmp)
    li    s2, 0                   # interrupt counter
    li    s3, 0x100               # scratch RAM
    lw    t1, 0(s1)
    addi  t1, t1, 200
    sw    x0, 12(s1)
    sw    t1, 8(s1)               # first timer interrupt in 200 cycles
    li    t0, 0x880
    csrs  mie, t0                 # timer + external interrupt enable
    csrsi mstatus, 8              # global interrupt enable
    ecall                         # one exception, handled below
    ebreak
main:
    lw    a0, 4(s0)               # switches
    andi  a0, a0, 0xFF
    ori   a0, a0, 1               # never zero
    # --- ALU, register and immediate forms
    add   a1, a0, s2
    sub   a2, a1, a0
    and   a3, a1, a0
    or    a4, a1, a0
    xor   a5, a1, a0
    sll   a6, a0, a2
    srl   a7, a1, a0
    sra   t2, a1, a0
    slt   t3, a0, a1
    sltu  t4, a0, a1
    slti  t3, a0, 100
    sltiu t4, a0, 100
    xori  a5, a5, 0x55
    slli  a6, a6, 2
    srli  a7, a7, 1
    srai  t2, t2, 3
    lui   t5, 0x12345
    auipc t6, 0
    # --- RV32M
    mul    a1, a0, a0
    mulh   a2, a1, a0
    mulhsu a3, a1, a0
    mulhu  a4, a1, a0
    div    a5, a1, a0
    divu   a6, a1, a0
    rem    a7, a1, a0
    remu   t2, a1, a0
    # --- loads and stores of every size
    sw    a1, 0(s3)
    sh    a2, 4(s3)
    sb    a3, 6(s3)
    lw    t3, 0(s3)
    lh    t4, 4(s3)
    lhu   t5, 4(s3)
    lb    t6, 6(s3)
    lbu   t1, 6(s3)
    # --- every branch type, plus a function call (jal / jalr)
    beq   a0, x0, skip
    bne   a0, x0, b1
b1: blt   a0, x0, skip
    bge   a0, x0, b2
b2: bltu  a0, a1, b3
b3: bgeu  a0, a1, skip
    call  mix                     # jal ra, mix
skip:
    csrr  t0, minstret
    csrrw t1, mscratch, t0
    csrrc t1, mscratch, t0
    csrrwi t1, mscratch, 5
    csrrci t1, mscratch, 1
    add   a0, a0, t3
    add   a0, a0, t4
    add   a0, a0, t5
    add   a0, a0, t6
    add   a0, a0, t1
    add   a0, a0, a5
    add   a0, a0, a7
    andi  a0, a0, 0xFF
    slli  a0, a0, 8
    andi  t0, s2, 0xFF
    or    a0, a0, t0
    sw    a0, 0(s0)               # LEDs = {calculation, interrupt counter}
    .word 0x0ff0000f              # fence (no-op in this core)
    j     main

mix:                              # tiny function: a0 = a0 xor (a0 >> 3)
    srli  t0, a0, 3
    xor   a0, a0, t0
    ret                           # jalr x0, 0(ra)

handler:
    csrr  t0, mcause
    blt   t0, x0, irq             # interrupt?
    csrr  t0, mepc                # exception (ecall / ebreak): skip it
    addi  t0, t0, 4
    csrw  mepc, t0
    mret
irq:
    addi  s2, s2, 1               # count timer ticks
    lw    t0, 0(s1)
    addi  t0, t0, 500             # next tick in 500 cycles
    sw    x0, 12(s1)
    sw    t0, 8(s1)
    mret
