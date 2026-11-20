# =============================================================================
# trap_test.s - Phase II test for CSRs, exceptions, interrupts and GPIO.
# Assemble:  python3 tools/rvasm.py testbench/programs/trap_test.s
# Run with tb_programs.v (it drives GPIO_IN = 0xCAFE1234 and raises ext_irq
# while GPIO_OUT == 0xE1).
#
# Register use:  x31 = current test number, x30 = TOHOST address
#   handler counters:  s0 = exceptions seen, s1 = timer interrupts, s2 = external interrupts
#                      s3 = last mcause, s4 = last mepc
#   the handler only uses a6 / a7 as scratch, so the main code avoids them.
#   (Not t5/t6: in ABI names t5 = x30 and t6 = x31, our TOHOST and test-number registers!)
# =============================================================================
    li   x30, 0x800000F0
    li   s0, 0
    li   s1, 0
    li   s2, 0
    la   t0, handler
    csrw mtvec, t0                 # all traps go to "handler"

# ---- test 2: ECALL -> mcause 11, mepc = address of the ecall
    li   x31, 2
ecall_site:
    ecall
    li   t0, 1
    bne  s0, t0, fail              # handler ran exactly once
    li   t0, 11
    bne  s3, t0, fail              # cause = environment call
    la   t0, ecall_site
    bne  s4, t0, fail              # mepc pointed at the ecall

# ---- test 3: EBREAK -> mcause 3
    li   x31, 3
    ebreak
    li   t0, 3
    bne  s3, t0, fail
    li   t0, 2
    bne  s0, t0, fail

# ---- test 4: illegal instruction -> mcause 2, and it must NOT execute
    li   x31, 4
    li   a0, 0
    .word 0xFFFFFFFF               # not a valid RISC-V instruction
    li   t0, 2
    bne  s3, t0, fail
    li   t0, 3
    bne  s0, t0, fail

# ---- test 5: an instruction right after ECALL must run exactly once
    li   x31, 5
    li   a1, 0
    ecall
    addi a1, a1, 1
    li   t0, 1
    bne  a1, t0, fail

# ---- test 6: GPIO in / out
    li   x31, 6
    li   a2, 0x80000000            # GPIO base
    lw   a3, 4(a2)                 # GPIO_IN
    li   t0, 0xCAFE1234
    bne  a3, t0, fail
    li   t0, 0x5A
    sw   t0, 0(a2)                 # GPIO_OUT = 0x5A
    lw   a3, 0(a2)
    bne  a3, t0, fail

# ---- test 7: timer interrupt
    li   x31, 7
    li   a2, 0x80000010            # timer base: +0 mtime, +8 mtimecmp
    lw   a3, 0(a2)                 # mtime (low)
    addi a3, a3, 60                # fire ~60 cycles from now
    sw   x0, 12(a2)                # mtimecmp high = 0
    sw   a3, 8(a2)                 # mtimecmp low
    li   t0, 0x80
    csrs mie, t0                   # enable timer interrupt (MTIE)
    csrsi mstatus, 8               # global interrupt enable (MIE)
    li   a4, 0
    li   a5, 0
wait_timer:
    addi a4, a4, 1                 # two counters in lockstep: if the interrupted
    addi a5, a5, 1                 # instruction ran twice, they would differ
    beqz s1, wait_timer
    bne  a4, a5, fail              # precise interrupt: nothing executed twice
    li   t0, 0x80000007
    bne  s3, t0, fail              # cause = machine timer interrupt
    csrr t0, mstatus
    andi t0, t0, 8
    beqz t0, fail                  # MRET re-enabled interrupts (MIE = 1 again)
    li   t0, 1
    bne  s1, t0, fail              # exactly one timer interrupt (handler cleared it)

# ---- test 8: external interrupt (testbench raises ext_irq while GPIO_OUT = 0xE1)
    li   x31, 8
    li   t0, 0x800
    csrs mie, t0                   # enable external interrupt (MEIE)
    li   a2, 0x80000000
    li   t0, 0xE1
    sw   t0, 0(a2)                 # ask the testbench for an interrupt
wait_ext:
    beqz s2, wait_ext
    li   t0, 0x8000000B
    bne  s3, t0, fail              # cause = machine external interrupt

# ---- test 9: interrupts off -> a pending timer must NOT interrupt
    li   x31, 9
    csrci mstatus, 8               # MIE = 0
    li   a2, 0x80000010
    sw   x0, 12(a2)
    sw   x0, 8(a2)                 # mtimecmp = 0 -> timer pending right now
    li   a5, 50
spin:
    addi a5, a5, -1
    bnez a5, spin
    li   t0, 1
    bne  s1, t0, fail              # still only one timer interrupt
    csrr t0, mip
    andi t0, t0, 0x80
    beqz t0, fail                  # but mip shows it is pending

pass:
    li   t0, 1
    sw   t0, 0(x30)
done:
    j    done
fail:
    sw   x31, 0(x30)
    j    done

# =============================================================================
# Trap handler
# =============================================================================
handler:
    csrr s3, mcause
    csrr s4, mepc
    csrr a6, mstatus
    andi a6, a6, 8
    bnez a6, fail                  # inside a handler MIE must be 0
    blt  s3, x0, interrupt         # mcause bit 31 = 1 -> interrupt
    # --- exception: skip the faulting instruction (mepc + 4)
    addi s0, s0, 1
    addi a6, s4, 4
    csrw mepc, a6
    mret
interrupt:
    li   a6, 0x80000007
    bne  s3, a6, ext_int
    # --- timer: push mtimecmp far away to clear the interrupt
    li   a6, 0x80000010
    li   a7, -1
    sw   a7, 12(a6)
    sw   a7, 8(a6)
    addi s1, s1, 1
    mret                           # mepc unchanged: re-run the interrupted instruction
ext_int:
    li   a6, 0x80000000
    sw   x0, 0(a6)                 # GPIO_OUT = 0 -> testbench drops ext_irq
    addi s2, s2, 1
    mret
