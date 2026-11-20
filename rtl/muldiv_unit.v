// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       muldiv_unit.v
// Description: RV32M extension - multiply, divide and remainder (Phase II).
//
//   funct3 | instruction | result
//   -------+-------------+-------------------------------------------------
//    000   | MUL         | low 32 bits of  rs1 * rs2
//    001   | MULH        | high 32 bits, signed   * signed
//    010   | MULHSU      | high 32 bits, signed   * unsigned
//    011   | MULHU       | high 32 bits, unsigned * unsigned
//    100   | DIV         | signed   rs1 / rs2   (rounds toward zero)
//    101   | DIVU        | unsigned rs1 / rs2
//    110   | REM         | signed   rs1 % rs2   (sign follows rs1)
//    111   | REMU        | unsigned rs1 % rs2
//
// Special cases fixed by the RISC-V spec (no exception is raised):
//   divide by zero : DIV/DIVU -> all ones (-1),  REM/REMU -> rs1
//   overflow       : DIV(-2^31, -1) -> -2^31,    REM(-2^31, -1) -> 0
//
// Design choice: this unit is purely combinational (one cycle). It is the
// simplest correct design, but a 32-bit divider is a long chain of logic, so it
// lowers the maximum clock speed. A faster design would compute the divide over
// ~32 cycles and stall the pipeline meanwhile (see docs/LEARNING_GUIDE.md).
// =============================================================================

`timescale 1ns / 1ps

module muldiv_unit (
    input  wire [2:0]  funct3,
    input  wire [31:0] a,        // rs1
    input  wire [31:0] b,        // rs2
    output reg  [31:0] result
);
    // Multiply: extend both operands to 64 bits (sign- or zero-extended), then
    // one 64x64 multiply gives the right 64-bit product for every variant.
    wire        a_signed = (funct3 == 3'b001) || (funct3 == 3'b010);   // MULH, MULHSU
    wire        b_signed = (funct3 == 3'b001);                          // MULH only
    wire [63:0] a_ext    = {{32{a_signed & a[31]}}, a};
    wire [63:0] b_ext    = {{32{b_signed & b[31]}}, b};
    wire [63:0] product  = a_ext * b_ext;

    // Divide: work on absolute values, then fix the signs.
    wire        a_neg    = a[31];
    wire        b_neg    = b[31];
    wire [31:0] a_abs    = a_neg ? (~a + 32'd1) : a;
    wire [31:0] b_abs    = b_neg ? (~b + 32'd1) : b;
    wire [31:0] q_unsigned = (b == 32'd0) ? 32'hFFFFFFFF : (a / b);
    wire [31:0] r_unsigned = (b == 32'd0) ? a            : (a % b);
    wire [31:0] q_abs    = (b == 32'd0) ? 32'hFFFFFFFF : (a_abs / b_abs);
    wire [31:0] r_abs    = (b == 32'd0) ? a_abs        : (a_abs % b_abs);
    // Quotient is negative when exactly one operand is negative; remainder takes
    // the sign of the dividend (rs1). Division by zero bypasses the sign fix.
    wire [31:0] q_signed = (b == 32'd0)         ? 32'hFFFFFFFF :
                           (a_neg ^ b_neg)      ? (~q_abs + 32'd1) : q_abs;
    wire [31:0] r_signed = (b == 32'd0)         ? a :
                           a_neg                ? (~r_abs + 32'd1) : r_abs;
    // Note: DIV(-2^31, -1): |a| = 2^31, |b| = 1, q_abs = 2^31, signs equal so the
    // result is 2^31 = 0x80000000 = -2^31, exactly what the spec requires. REM -> 0.

    always @(*) begin
        case (funct3)
            3'b000:  result = product[31:0];    // MUL
            3'b001,                             // MULH
            3'b010,                             // MULHSU
            3'b011:  result = product[63:32];   // MULHU
            3'b100:  result = q_signed;         // DIV
            3'b101:  result = q_unsigned;       // DIVU
            3'b110:  result = r_signed;         // REM
            default: result = r_unsigned;       // REMU
        endcase
    end
endmodule
