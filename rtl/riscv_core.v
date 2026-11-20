// =============================================================================
// Project:    ProtocolX RISC-V 5-Stage Pipelined Processor
// File:       riscv_core.v
// Description: Top-Level 5-Stage Pipelined RV32IM Processor Core.
//              Integrates IF, ID, EX, MEM, and WB stages with hazard detection,
//              data forwarding, and pipeline registers.
//
//   Phase I : RV32I pipeline, forwarding, load-use stall, branch flush.
//   Phase II: (search the file for "Phase II")
//     - 2-bit dynamic branch prediction in IF (branch_predictor_2bit, Aditya)
//     - RV32M multiply / divide (muldiv_unit)
//     - byte / half-word loads and stores (mem_align_unit by Shagun + store_align_unit)
//     - memory-mapped GPIO (gpio_unit, Ritik) and machine timer (timer_unit)
//     - CSRs, ECALL / EBREAK / MRET, illegal-instruction trap, timer and
//       external interrupts (csr_unit)
//     - hardware cycle / retired-instruction counters (perf_counter, Archit)
//     - a "valid" bit in every pipeline register, so bubbles are never counted
//       as instructions and are never interrupted
//
// Developers:  Naveen Kumar (2401020041) - Project Lead & Primary RTL Developer
//              Aditya Raj   (2401010032) - Technical Lead, Pipeline Design & Verification
// =============================================================================

`timescale 1ns / 1ps
`include "riscv_defines.vh"

module riscv_core #(
    parameter IMEM_DEPTH        = 1024,
    parameter DMEM_DEPTH        = 1024,
    parameter INIT_FILE         = "",
    parameter BRANCH_PREDICTION = 1     // Phase II: 1 = 2-bit predictor, 0 = always "not taken"
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // Phase II: outside world
    input  wire [`XLEN-1:0]          gpio_in,     // e.g. switches
    output wire [`XLEN-1:0]          gpio_out,    // e.g. LEDs
    input  wire                      ext_irq,     // external interrupt request

    // Probe signals for verification / monitoring
    output wire [`XLEN-1:0]          current_pc,
    output wire [`XLEN-1:0]          current_instr,
    output wire [`XLEN-1:0]          wb_data_out,
    output wire [`REG_ADDR_WIDTH-1:0] wb_rd_out,
    output wire                      wb_reg_write_out
);

    // =========================================================================
    // 1. INSTRUCTION FETCH (IF) STAGE
    // =========================================================================
    reg  [`XLEN-1:0] pc_reg;
    wire [`XLEN-1:0] pc_next;
    wire [`XLEN-1:0] pc_plus4;
    wire [`XLEN-1:0] instruction_raw;

    // Hazard control wires
    wire pc_write;
    wire if_id_write;
    wire if_id_flush;
    wire id_ex_flush;

    // Redirect from EX: "the PC we fetched was wrong, go here instead"
    wire             redirect_ex;
    wire [`XLEN-1:0] redirect_pc_ex;

    assign pc_plus4 = pc_reg + 32'd4;

    // ---- Phase II: branch prediction -------------------------------------------
    // The instruction arrives from instruction memory in this same cycle, so we
    // can already see if it is a branch and compute its target (PC + B-immediate).
    // The 2-bit predictor then says "taken" or "not taken". If "taken", we fetch
    // from the target next cycle instead of PC + 4. EX checks the guess later.
    wire             is_branch_if  = (instruction_raw[6:0] == `OPCODE_BRANCH);
    wire [`XLEN-1:0] imm_b_if      = {{20{instruction_raw[31]}}, instruction_raw[7],
                                      instruction_raw[30:25], instruction_raw[11:8], 1'b0};
    wire [`XLEN-1:0] pred_target_if = pc_reg + imm_b_if;
    wire             bp_says_taken;
    wire             pred_taken_if = (BRANCH_PREDICTION != 0) && is_branch_if && bp_says_taken;

    // Priority: a correction from EX always wins over a guess made in IF.
    assign pc_next = redirect_ex   ? redirect_pc_ex :
                     pred_taken_if ? pred_target_if :
                                     pc_plus4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_reg <= {`XLEN{1'b0}};
        end else if (pc_write) begin
            pc_reg <= pc_next;
        end
    end

    // Instruction Memory Instance
    instruction_memory #(
        .MEM_DEPTH(IMEM_DEPTH),
        .INIT_FILE(INIT_FILE)
    ) u_imem (
        .address(pc_reg),
        .instruction(instruction_raw)
    );

    // =========================================================================
    // PIPELINE REGISTER: IF / ID
    // =========================================================================
    wire [`XLEN-1:0] pc_id;
    wire [`XLEN-1:0] pc_plus4_id;
    wire [`XLEN-1:0] instr_id;
    wire             pred_taken_id;
    wire             valid_id;

    pipe_if_id u_pipe_if_id (
        .clk(clk),
        .rst_n(rst_n),
        .enable(if_id_write),
        .flush(if_id_flush),
        .pc_in(pc_reg),
        .pc_plus4_in(pc_plus4),
        .instruction_in(instruction_raw),
        .pred_taken_in(pred_taken_if),
        .pc_out(pc_id),
        .pc_plus4_out(pc_plus4_id),
        .instruction_out(instr_id),
        .pred_taken_out(pred_taken_id),
        .valid_out(valid_id)
    );

    // =========================================================================
    // 2. INSTRUCTION DECODE (ID) STAGE
    // =========================================================================
    wire [6:0] opcode_id   = instr_id[6:0];
    wire [2:0] funct3_id   = instr_id[14:12];
    wire [6:0] funct7_id   = instr_id[31:25];
    wire [4:0] rd_id       = instr_id[11:7];
    wire [4:0] rs1_id      = instr_id[19:15];
    wire [4:0] rs2_id      = instr_id[24:20];

    // Control Unit signals
    wire       ctrl_reg_write_id;
    wire [1:0] ctrl_mem_to_reg_id;
    wire       ctrl_mem_read_id;
    wire       ctrl_mem_write_id;
    wire       ctrl_alu_src_id;
    wire       ctrl_alu_src_a_id;
    wire       ctrl_branch_id;
    wire       ctrl_jump_id;
    wire       ctrl_is_jalr_id;
    wire [3:0] ctrl_alu_op_id;
    wire       ctrl_muldiv_id, ctrl_is_csr_id, ctrl_is_ecall_id;     // Phase II
    wire       ctrl_is_ebreak_id, ctrl_is_mret_id, ctrl_illegal_id;  // Phase II

    control_unit u_control_unit (
        .opcode(opcode_id),
        .funct3(funct3_id),
        .funct7(funct7_id),
        .funct12(instr_id[31:20]),
        .reg_write(ctrl_reg_write_id),
        .mem_to_reg(ctrl_mem_to_reg_id),
        .mem_read(ctrl_mem_read_id),
        .mem_write(ctrl_mem_write_id),
        .alu_src(ctrl_alu_src_id),
        .alu_src_a(ctrl_alu_src_a_id),
        .branch(ctrl_branch_id),
        .jump(ctrl_jump_id),
        .is_jalr(ctrl_is_jalr_id),
        .alu_op(ctrl_alu_op_id),
        .muldiv(ctrl_muldiv_id),
        .is_csr(ctrl_is_csr_id),
        .is_ecall(ctrl_is_ecall_id),
        .is_ebreak(ctrl_is_ebreak_id),
        .is_mret(ctrl_is_mret_id),
        .illegal(ctrl_illegal_id)
    );

    // Register File
    wire [`XLEN-1:0] reg_read_data1_id;
    wire [`XLEN-1:0] reg_read_data2_id;
    wire [`XLEN-1:0] wb_data;
    wire [`REG_ADDR_WIDTH-1:0] rd_wb;
    wire             reg_write_wb;

    reg_file u_reg_file (
        .clk(clk),
        .rst_n(rst_n),
        .reg_write(reg_write_wb),
        .read_addr1(rs1_id),
        .read_addr2(rs2_id),
        .write_addr(rd_wb),
        .write_data(wb_data),
        .read_data1(reg_read_data1_id),
        .read_data2(reg_read_data2_id)
    );

    // Immediate Generator
    wire [`XLEN-1:0] imm_id;
    imm_gen u_imm_gen (
        .instruction(instr_id),
        .immediate(imm_id)
    );

    // =========================================================================
    // PIPELINE REGISTER: ID / EX
    // =========================================================================
    wire        reg_write_ex;
    wire [1:0]  mem_to_reg_ex;
    wire        mem_read_ex;
    wire        mem_write_ex;
    wire        alu_src_ex;
    wire        alu_src_a_ex;
    wire        branch_ex;
    wire        jump_ex;
    wire        is_jalr_ex;
    wire [3:0]  alu_op_ex;
    wire        valid_ex, pred_taken_ex, muldiv_ex, is_csr_ex;        // Phase II
    wire        is_ecall_ex, is_ebreak_ex, is_mret_ex, illegal_ex;    // Phase II
    wire [`XLEN-1:0] pc_ex;
    wire [`XLEN-1:0] pc_plus4_ex;
    wire [`XLEN-1:0] read_data1_ex;
    wire [`XLEN-1:0] read_data2_ex;
    wire [`XLEN-1:0] imm_ex;
    wire [2:0]       funct3_ex;
    wire [6:0]       funct7_ex;
    wire [4:0]       rd_ex;
    wire [4:0]       rs1_ex;
    wire [4:0]       rs2_ex;

    pipe_id_ex u_pipe_id_ex (
        .clk(clk),
        .rst_n(rst_n),
        .flush(id_ex_flush),

        .reg_write_in(ctrl_reg_write_id),
        .mem_to_reg_in(ctrl_mem_to_reg_id),
        .mem_read_in(ctrl_mem_read_id),
        .mem_write_in(ctrl_mem_write_id),
        .alu_src_in(ctrl_alu_src_id),
        .alu_src_a_in(ctrl_alu_src_a_id),
        .branch_in(ctrl_branch_id),
        .jump_in(ctrl_jump_id),
        .is_jalr_in(ctrl_is_jalr_id),
        .alu_op_in(ctrl_alu_op_id),
        .valid_in(valid_id),
        .pred_taken_in(pred_taken_id),
        .muldiv_in(ctrl_muldiv_id),
        .is_csr_in(ctrl_is_csr_id),
        .is_ecall_in(ctrl_is_ecall_id),
        .is_ebreak_in(ctrl_is_ebreak_id),
        .is_mret_in(ctrl_is_mret_id),
        .illegal_in(ctrl_illegal_id),

        .pc_in(pc_id),
        .pc_plus4_in(pc_plus4_id),
        .read_data1_in(reg_read_data1_id),
        .read_data2_in(reg_read_data2_id),
        .immediate_in(imm_id),
        .funct3_in(funct3_id),
        .funct7_in(funct7_id),
        .rd_in(rd_id),
        .rs1_in(rs1_id),
        .rs2_in(rs2_id),

        .reg_write_out(reg_write_ex),
        .mem_to_reg_out(mem_to_reg_ex),
        .mem_read_out(mem_read_ex),
        .mem_write_out(mem_write_ex),
        .alu_src_out(alu_src_ex),
        .alu_src_a_out(alu_src_a_ex),
        .branch_out(branch_ex),
        .jump_out(jump_ex),
        .is_jalr_out(is_jalr_ex),
        .alu_op_out(alu_op_ex),
        .valid_out(valid_ex),
        .pred_taken_out(pred_taken_ex),
        .muldiv_out(muldiv_ex),
        .is_csr_out(is_csr_ex),
        .is_ecall_out(is_ecall_ex),
        .is_ebreak_out(is_ebreak_ex),
        .is_mret_out(is_mret_ex),
        .illegal_out(illegal_ex),

        .pc_out(pc_ex),
        .pc_plus4_out(pc_plus4_ex),
        .read_data1_out(read_data1_ex),
        .read_data2_out(read_data2_ex),
        .immediate_out(imm_ex),
        .funct3_out(funct3_ex),
        .funct7_out(funct7_ex),
        .rd_out(rd_ex),
        .rs1_out(rs1_ex),
        .rs2_out(rs2_ex)
    );

    // =========================================================================
    // 3. EXECUTION (EX) STAGE & FORWARDING
    // =========================================================================
    wire [1:0] forward_a;
    wire [1:0] forward_b;
    wire [`XLEN-1:0] exec_result_ex;
    wire [`XLEN-1:0] operand_a_ex;
    wire [`XLEN-1:0] write_data_mem_ex;
    wire             branch_cond_ex;
    wire [`XLEN-1:0] target_pc_ex;

    // From EX/MEM stage
    wire [`XLEN-1:0] alu_result_mem;
    wire [`REG_ADDR_WIDTH-1:0] rd_mem;
    wire reg_write_mem;

    execution_unit u_execution_unit (
        .pc(pc_ex),
        .read_data1(read_data1_ex),
        .read_data2(read_data2_ex),
        .immediate(imm_ex),
        .funct3(funct3_ex),
        .alu_op(alu_op_ex),
        .alu_src(alu_src_ex),
        .alu_src_a(alu_src_a_ex),
        .muldiv(muldiv_ex),
        .is_jalr(is_jalr_ex),
        .forward_a(forward_a),
        .forward_b(forward_b),
        .forward_data_mem(alu_result_mem),
        .forward_data_wb(wb_data),
        .result(exec_result_ex),
        .operand_a(operand_a_ex),
        .write_data_mem(write_data_mem_ex),
        .branch_cond(branch_cond_ex),
        .target_pc(target_pc_ex)
    );

    // ---- Phase II: CSRs and traps ---------------------------------------------
    wire [63:0]      cycle_count, inst_count;
    wire [`XLEN-1:0] csr_rdata_ex, trap_vector, return_pc;
    wire             trap_ex, mret_ex;
    wire             timer_irq;

    csr_unit u_csr_unit (
        .clk(clk),
        .rst_n(rst_n),
        .valid(valid_ex),
        .pc(pc_ex),
        .is_csr(is_csr_ex),
        .funct3(funct3_ex),
        .csr_addr(imm_ex[11:0]),
        .rs1_value(operand_a_ex),
        .zimm(rs1_ex),
        .is_ecall(is_ecall_ex),
        .is_ebreak(is_ebreak_ex),
        .is_mret(is_mret_ex),
        .illegal(illegal_ex),
        .timer_irq(timer_irq),
        .ext_irq(ext_irq),
        .cycle_count(cycle_count),
        .inst_count(inst_count),
        .csr_rdata(csr_rdata_ex),
        .trap(trap_ex),
        .mret(mret_ex),
        .trap_vector(trap_vector),
        .return_pc(return_pc)
    );

    // Value this instruction produces for rd (CSR instructions return the old CSR)
    wire [`XLEN-1:0] result_ex = is_csr_ex ? csr_rdata_ex : exec_result_ex;

    // ---- Phase II: check the IF guess and decide where the PC must go ------------
    wire actual_taken_ex = branch_ex & branch_cond_ex;
    wire mispredict_ex   = branch_ex & (actual_taken_ex != pred_taken_ex);
    wire branch_taken_ex = actual_taken_ex | jump_ex;   // debug: branch/jump in EX is taken (used by testbenches)

    assign redirect_ex    = trap_ex | mret_ex | (valid_ex & (jump_ex | mispredict_ex));
    assign redirect_pc_ex = trap_ex         ? trap_vector  :   // go to the trap handler
                            mret_ex         ? return_pc    :   // return from the handler
                            jump_ex         ? target_pc_ex :   // JAL / JALR
                            actual_taken_ex ? target_pc_ex :   // branch taken, but we guessed not taken
                                              pc_plus4_ex;     // branch not taken, but we guessed taken

    // Train the predictor with the real outcome of every branch that executes
    branch_predictor_2bit u_branch_predictor (
        .clk(clk),
        .rst_n(rst_n),
        .pc_if(pc_reg),
        .pc_ex(pc_ex),
        .is_branch_ex(valid_ex & branch_ex & ~trap_ex),
        .actual_taken_ex(actual_taken_ex),
        .predict_taken(bp_says_taken)
    );

    // =========================================================================
    // PIPELINE REGISTER: EX / MEM
    // =========================================================================
    wire [1:0] mem_to_reg_mem;
    wire       mem_read_mem;
    wire       mem_write_mem;
    wire       valid_mem;
    wire [2:0] funct3_mem;
    wire [`XLEN-1:0] pc_plus4_mem;
    wire [`XLEN-1:0] write_data_mem;

    pipe_ex_mem u_pipe_ex_mem (
        .clk(clk),
        .rst_n(rst_n),
        .flush(trap_ex),                  // Phase II: a trapped instruction must not complete
        .reg_write_in(reg_write_ex),
        .mem_to_reg_in(mem_to_reg_ex),
        .mem_read_in(mem_read_ex),
        .mem_write_in(mem_write_ex),
        .valid_in(valid_ex),
        .funct3_in(funct3_ex),
        .pc_plus4_in(pc_plus4_ex),
        .alu_result_in(result_ex),
        .write_data_in(write_data_mem_ex),
        .rd_in(rd_ex),
        .reg_write_out(reg_write_mem),
        .mem_to_reg_out(mem_to_reg_mem),
        .mem_read_out(mem_read_mem),
        .mem_write_out(mem_write_mem),
        .valid_out(valid_mem),
        .funct3_out(funct3_mem),
        .pc_plus4_out(pc_plus4_mem),
        .alu_result_out(alu_result_mem),
        .write_data_out(write_data_mem),
        .rd_out(rd_mem)
    );

    // =========================================================================
    // 4. MEMORY ACCESS (MEM) STAGE
    // =========================================================================
    // Phase II memory map: address bit 31 = 0 -> data RAM, 1 -> devices (GPIO, timer)
    wire is_io_mem = alu_result_mem[31];

    // Stores: put SB / SH data in the right byte lane and pick the byte enables
    wire [`XLEN-1:0] store_data_mem;
    wire [3:0]       store_byte_en;
    store_align_unit u_store_align (
        .funct3(funct3_mem),
        .byte_offset(alu_result_mem[1:0]),
        .store_data(write_data_mem),
        .write_data(store_data_mem),
        .byte_en(store_byte_en)
    );

    wire [`XLEN-1:0] mem_word_mem;
    data_memory #(
        .MEM_DEPTH(DMEM_DEPTH)
    ) u_dmem (
        .clk(clk),
        .byte_en((mem_write_mem && !is_io_mem) ? store_byte_en : 4'b0000),
        .address(alu_result_mem),
        .write_data(store_data_mem),
        .read_data(mem_word_mem)
    );

    // Loads: pick the byte / half-word and sign- or zero-extend it (Shagun's unit)
    wire [`XLEN-1:0] mem_load_data;
    mem_align_unit u_mem_align (
        .funct3(funct3_mem),
        .byte_offset(alu_result_mem[1:0]),
        .raw_data_in(mem_word_mem),
        .aligned_data(mem_load_data)
    );

    // Devices: GPIO and machine timer (each returns 0 when not addressed)
    wire [`XLEN-1:0] gpio_rdata, timer_rdata;
    gpio_unit u_gpio (
        .clk(clk),
        .rst_n(rst_n),
        .mem_write(mem_write_mem),
        .addr(alu_result_mem),
        .write_data(write_data_mem),
        .gpio_in(gpio_in),
        .gpio_out(gpio_out),
        .read_data(gpio_rdata)
    );

    timer_unit u_timer (
        .clk(clk),
        .rst_n(rst_n),
        .mem_write(mem_write_mem),
        .addr(alu_result_mem),
        .write_data(write_data_mem),
        .read_data(timer_rdata),
        .timer_irq(timer_irq)
    );

    wire [`XLEN-1:0] load_data_mem = is_io_mem ? (gpio_rdata | timer_rdata) : mem_load_data;

    // =========================================================================
    // PIPELINE REGISTER: MEM / WB
    // =========================================================================
    wire [1:0]       mem_to_reg_wb;
    wire             valid_wb;
    wire [`XLEN-1:0] pc_plus4_wb;
    wire [`XLEN-1:0] mem_read_data_wb;
    wire [`XLEN-1:0] alu_result_wb;

    pipe_mem_wb u_pipe_mem_wb (
        .clk(clk),
        .rst_n(rst_n),
        .reg_write_in(reg_write_mem),
        .mem_to_reg_in(mem_to_reg_mem),
        .valid_in(valid_mem),
        .pc_plus4_in(pc_plus4_mem),
        .read_data_in(load_data_mem),
        .alu_result_in(alu_result_mem),
        .rd_in(rd_mem),
        .reg_write_out(reg_write_wb),
        .mem_to_reg_out(mem_to_reg_wb),
        .valid_out(valid_wb),
        .pc_plus4_out(pc_plus4_wb),
        .read_data_out(mem_read_data_wb),
        .alu_result_out(alu_result_wb),
        .rd_out(rd_wb)
    );

    // =========================================================================
    // 5. WRITE-BACK (WB) STAGE
    // =========================================================================
    assign wb_data = (mem_to_reg_wb == 2'b01) ? mem_read_data_wb :
                     (mem_to_reg_wb == 2'b10) ? pc_plus4_wb      :
                     alu_result_wb;

    // Phase II: an instruction "retires" (is finished) when a valid one leaves WB
    perf_counter u_perf_counter (
        .clk(clk),
        .rst_n(rst_n),
        .inst_retired(valid_wb),
        .cycle_count(cycle_count),
        .inst_count(inst_count)
    );

    // Verification probe outputs
    assign current_pc       = pc_reg;
    assign current_instr    = instruction_raw;
    assign wb_data_out      = wb_data;
    assign wb_rd_out        = rd_wb;
    assign wb_reg_write_out = reg_write_wb;

    // =========================================================================
    // HAZARD DETECTION & FORWARDING UNIT
    // =========================================================================
    // "branch_taken_ex" here means: EX is changing the PC for ANY reason
    // (mispredicted branch, jump, trap or MRET). The two instructions behind it
    // are on the wrong path and get flushed. jump_ex is already part of redirect_ex.
    hazard_unit u_hazard_unit (
        .rs1_id(rs1_id),
        .rs2_id(rs2_id),
        .rd_ex(rd_ex),
        .mem_read_ex(mem_read_ex),
        .rs1_ex(rs1_ex),
        .rs2_ex(rs2_ex),
        .rd_mem(rd_mem),
        .reg_write_mem(reg_write_mem),
        .rd_wb(rd_wb),
        .reg_write_wb(reg_write_wb),
        .branch_taken_ex(redirect_ex),
        .jump_ex(1'b0),
        .pc_write(pc_write),
        .if_id_write(if_id_write),
        .if_id_flush(if_id_flush),
        .id_ex_flush(id_ex_flush),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

endmodule
