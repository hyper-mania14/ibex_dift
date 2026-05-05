// =============================================================================
// Ibex DIFT Testbench 
// =============================================================================
`ifndef DIFT
  `define DIFT
`endif
`timescale 1ns/1ps

module ibex_core_tb;

  import ibex_pkg::*;

  // =========================================================================
  // Clock and reset
  // =========================================================================
  localparam CLK_PERIOD = 10;          // 100 MHz
  logic clk, rst_n;

  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // =========================================================================
  // Memory parameters
  // =========================================================================
  localparam MEM_DEPTH  = 512;         // 512 words instruction memory
  localparam DMEM_DEPTH = 64;          // 64 words data memory
  localparam BOOT_ADDR  = 32'h1000_0000;
  localparam DMEM_BASE  = 32'h0001_0000;
  localparam int BOOT_WORD = 32;       // BOOT_ADDR + 0x80 => word index 32

  // =========================================================================
  // DUT signals
  // =========================================================================
  logic        instr_req;
  logic        instr_gnt;
  logic        instr_rvalid;
  logic [31:0] instr_addr;
  logic [31:0] instr_rdata;
  logic        instr_err;

  logic        data_req;
  logic        data_gnt;
  logic        data_rvalid;
  logic        data_we;
  logic [3:0]  data_be;
  logic [31:0] data_addr;
  logic [31:0] data_wdata;
  logic [31:0] data_rdata;
  logic        data_err;

  logic        dummy_instr_id;
  logic        dummy_instr_wb;
  logic [4:0]  rf_raddr_a, rf_raddr_b, rf_waddr_wb;
  logic        rf_we_wb;
  logic [31:0] rf_wdata_wb_ecc;
  logic [31:0] rf_rdata_a_ecc, rf_rdata_b_ecc;

  logic [IC_NUM_WAYS-1:0]  ic_tag_req;
  logic                    ic_tag_write;
  logic [IC_INDEX_W-1:0]   ic_tag_addr;
  logic [IC_TAG_SIZE-1:0]  ic_tag_wdata;
  logic [IC_TAG_SIZE-1:0]  ic_tag_rdata [IC_NUM_WAYS];
  logic [IC_NUM_WAYS-1:0]  ic_data_req;
  logic                    ic_data_write;
  logic [IC_INDEX_W-1:0]   ic_data_addr;
  logic [IC_LINE_SIZE-1:0] ic_data_wdata;
  logic [IC_LINE_SIZE-1:0] ic_data_rdata [IC_NUM_WAYS];
  logic                    ic_scr_key_valid;
  logic                    ic_scr_key_req;

  logic        irq_software, irq_timer, irq_external, irq_nm;
  logic [14:0] irq_fast;
  logic        irq_pending;
  logic        debug_req;
  crash_dump_t crash_dump;
  logic        double_fault;
  ibex_mubi_t  fetch_enable;
  logic        alert_minor, alert_major_int, alert_major_bus;
  ibex_mubi_t  core_busy;

  // DIFT signals
  logic        data_rdata_tag;
  logic        data_wdata_tag;
  logic        dift_exception;

  // =========================================================================
  // Instruction memory (holds machine code)
  // =========================================================================
  logic [31:0] instr_mem [0:MEM_DEPTH-1];

  assign instr_gnt    = 1'b1;
  assign instr_err    = 1'b0;

  // NOP: addi x0, x0, 0
  localparam logic [31:0] NOP = 32'h0000_0013;

  assign instr_rdata = (instr_addr >= 32'h1000_0000) ?
                     instr_mem[(instr_addr - 32'h1000_0000) >> 2] : NOP;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) instr_rvalid <= 1'b0;
    else        instr_rvalid <= instr_req;
  end

  // =========================================================================
  // Data memory + Tag RAM (1 bit per word)
  // =========================================================================
  logic [31:0] data_mem  [0:DMEM_DEPTH-1];
  logic        tag_mem   [0:DMEM_DEPTH-1];

  logic [$clog2(DMEM_DEPTH)-1:0] dmem_idx;
  assign dmem_idx = (data_addr - DMEM_BASE) >> 2;

  assign data_gnt = 1'b1;
  assign data_err = 1'b0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_rvalid    <= 1'b0;
      data_rdata     <= 32'h0;
      data_rdata_tag <= 1'b0;
    end else begin
      data_rvalid <= data_req;
      if (data_req) begin
        if (data_we) begin
          data_mem[dmem_idx] <= data_wdata;
          tag_mem[dmem_idx]  <= data_wdata_tag;
        end
        data_rdata     <= data_mem[dmem_idx];
        data_rdata_tag <= tag_mem[dmem_idx];
      end
    end
  end

  // =========================================================================
  // Simple external register file (no ECC)
  // =========================================================================
  logic [31:0] reg_file [0:31];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 32; i++) reg_file[i] <= 32'h0;
    end else if (rf_we_wb && rf_waddr_wb != 5'd0) begin
      reg_file[rf_waddr_wb] <= rf_wdata_wb_ecc;
    end
  end
  assign rf_rdata_a_ecc = reg_file[rf_raddr_a];
  assign rf_rdata_b_ecc = reg_file[rf_raddr_b];

  // =========================================================================
  // DUT instantiation
  // =========================================================================
  ibex_core #(
    .PMPEnable        (1'b0),
    .MHPMCounterNum   (0),
    .RV32M            (RV32MFast),
    .RV32B            (RV32BNone),
    .WritebackStage   (1'b0),
    .BranchTargetALU  (1'b0),
    .ICache           (1'b0),
    .BranchPredictor  (1'b0),
    .DbgTriggerEn     (1'b0),
    .SecureIbex       (1'b0),
    .DummyInstructions(1'b0),
    .RegFileECC       (1'b0),
    .MemECC           (1'b0),
    .ResetAll         (1'b0)
  ) dut (
    .clk_i (clk),
    .rst_ni(rst_n),

    .hart_id_i  (32'h0),
    .boot_addr_i(BOOT_ADDR),

    .instr_req_o    (instr_req),
    .instr_gnt_i    (instr_gnt),
    .instr_rvalid_i (instr_rvalid),
    .instr_addr_o   (instr_addr),
    .instr_rdata_i  (instr_rdata),
    .instr_err_i    (instr_err),

    .data_req_o    (data_req),
    .data_gnt_i    (data_gnt),
    .data_rvalid_i (data_rvalid),
    .data_we_o     (data_we),
    .data_be_o     (data_be),
    .data_addr_o   (data_addr),
    .data_wdata_o  (data_wdata),
    .data_rdata_i  (data_rdata),
    .data_err_i    (data_err),

    .dummy_instr_id_o (dummy_instr_id),
    .dummy_instr_wb_o (dummy_instr_wb),
    .rf_raddr_a_o     (rf_raddr_a),
    .rf_raddr_b_o     (rf_raddr_b),
    .rf_waddr_wb_o    (rf_waddr_wb),
    .rf_we_wb_o       (rf_we_wb),
    .rf_wdata_wb_ecc_o(rf_wdata_wb_ecc),
    .rf_rdata_a_ecc_i (rf_rdata_a_ecc),
    .rf_rdata_b_ecc_i (rf_rdata_b_ecc),

    .ic_tag_req_o      (ic_tag_req),
    .ic_tag_write_o    (ic_tag_write),
    .ic_tag_addr_o     (ic_tag_addr),
    .ic_tag_wdata_o    (ic_tag_wdata),
    .ic_tag_rdata_i    ('{default:'0}),
    .ic_data_req_o     (ic_data_req),
    .ic_data_write_o   (ic_data_write),
    .ic_data_addr_o    (ic_data_addr),
    .ic_data_wdata_o   (ic_data_wdata),
    .ic_data_rdata_i   ('{default:'0}),
    .ic_scr_key_valid_i(1'b1),
    .ic_scr_key_req_o  (ic_scr_key_req),

    .irq_software_i(1'b0),
    .irq_timer_i   (1'b0),
    .irq_external_i(1'b0),
    .irq_fast_i    (15'b0),
    .irq_nm_i      (1'b0),
    .irq_pending_o (irq_pending),

    .debug_req_i      (1'b0),
    .crash_dump_o     (crash_dump),
    .double_fault_seen_o(double_fault),

    .fetch_enable_i       (IbexMuBiOn),
    .alert_minor_o        (alert_minor),
    .alert_major_internal_o(alert_major_int),
    .alert_major_bus_o    (alert_major_bus),
    .core_busy_o          (core_busy),

    .data_rdata_tag_i (data_rdata_tag),
    .data_wdata_tag_o (data_wdata_tag),
    .dift_exception_o (dift_exception)
  );

  // =========================================================================
  // Test state
  // =========================================================================
  int  test_num;
  int  pass_count, fail_count;
  logic exception_seen;

  task automatic pass(input string msg);
    $display("[PASS] Test %0d: %s", test_num, msg);
    pass_count++;
  endtask

  task automatic fail(input string msg);
    $display("[FAIL] Test %0d: %s", test_num, msg);
    fail_count++;
  endtask

  task automatic wait_cycles(input int n);
    repeat(n) @(posedge clk);
  endtask

  // Reset the core and all memories (instruction memory preserved)
  task automatic do_reset();
    rst_n = 0;
    for (int i = 0; i < DMEM_DEPTH; i++) data_mem[i]  = 32'h0;
    for (int i = 0; i < DMEM_DEPTH; i++) tag_mem[i]   = 1'b0;
    for (int i = 0; i < 32;         i++) reg_file[i]  = 32'h0;
    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
    @(posedge clk);
  endtask

  // =========================================================================
  // Instruction encoding functions (for building test programs more easily)
  // =========================================================================
  function automatic logic [31:0] rtype(
    input logic [6:0] funct7, input logic [4:0] rs2, rs1, rd,
    input logic [2:0] funct3, input logic [6:0] opcode);
    return {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] itype(
    input logic [11:0] imm, input logic [4:0] rs1, rd,
    input logic [2:0] funct3, input logic [6:0] opcode);
    return {imm, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] stype(
    input logic [11:0] imm, input logic [4:0] rs2, rs1,
    input logic [2:0] funct3);
    return {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'h23};
  endfunction

  function automatic logic [31:0] utype(
    input logic [19:0] imm20, input logic [4:0] rd, input logic [6:0] opcode);
    return {imm20, rd, opcode};
  endfunction

  function automatic logic [31:0] csrrw(
    input logic [11:0] csr, input logic [4:0] rs1, rd);
    return {csr, rs1, 3'b001, rd, 7'h73};
  endfunction

  function automatic logic [31:0] csrrs(
    input logic [11:0] csr, input logic [4:0] rs1, rd);
    return {csr, rs1, 3'b010, rd, 7'h73};
  endfunction

  function automatic logic [31:0] csrrc(
    input logic [11:0] csr, input logic [4:0] rs1, rd);
    return {csr, rs1, 3'b011, rd, 7'h73};
  endfunction

  function automatic logic [31:0] csrrwi(
    input logic [11:0] csr, input logic [4:0] uimm, rd);
    return {csr, uimm, 3'b101, rd, 7'h73};
  endfunction

  function automatic logic [31:0] addi(input logic [4:0] rd, rs1, input logic [11:0] imm);
    return itype(imm, rs1, rd, 3'b000, 7'h13);
  endfunction
  function automatic logic [31:0] add(input logic [4:0] rd, rs1, rs2);
    return rtype(7'h00, rs2, rs1, rd, 3'b000, 7'h33);
  endfunction

  function automatic logic [31:0] mul(input logic [4:0] rd, rs1, rs2);
    return rtype(7'h01, rs2, rs1, rd, 3'b000, 7'h33);
  endfunction

  function automatic logic [31:0] div(input logic [4:0] rd, rs1, rs2);
    return rtype(7'h01, rs2, rs1, rd, 3'b100, 7'h33);
  endfunction

  function automatic logic [31:0] rem(input logic [4:0] rd, rs1, rs2);
    return rtype(7'h01, rs2, rs1, rd, 3'b110, 7'h33);
  endfunction
  function automatic logic [31:0] or_insn(input logic [4:0] rd, rs1, rs2);
    return rtype(7'h00, rs2, rs1, rd, 3'b110, 7'h33);
  endfunction
  function automatic logic [31:0] and_insn(input logic [4:0] rd, rs1, rs2);
    return rtype(7'h00, rs2, rs1, rd, 3'b111, 7'h33);
  endfunction
  function automatic logic [31:0] xor_insn(input logic [4:0] rd, rs1, rs2);
    return rtype(7'h00, rs2, rs1, rd, 3'b100, 7'h33);
  endfunction
  function automatic logic [31:0] slli(input logic [4:0] rd, rs1, input logic [4:0] shamt);
    return itype({7'b0000000, shamt}, rs1, rd, 3'b001, 7'h13);
  endfunction
  function automatic logic [31:0] srli(input logic [4:0] rd, rs1, input logic [4:0] shamt);
    return itype({7'b0000000, shamt}, rs1, rd, 3'b101, 7'h13);
  endfunction
  function automatic logic [31:0] slt(input logic [4:0] rd, rs1, rs2);
    return rtype(7'h00, rs2, rs1, rd, 3'b010, 7'h33);
  endfunction
  function automatic logic [31:0] lw(input logic [4:0] rd, rs1, input logic [11:0] imm);
    return itype(imm, rs1, rd, 3'b010, 7'h03);
  endfunction
  function automatic logic [31:0] sw(input logic [4:0] rs2, rs1, input logic [11:0] imm);
    return stype(imm, rs2, rs1, 3'b010);
  endfunction
  function automatic logic [31:0] lui(input logic [4:0] rd, input logic [19:0] imm);
    return utype(imm, rd, 7'h37);
  endfunction
  function automatic logic [31:0] jalr(input logic [4:0] rd, rs1, input logic [11:0] imm);
    return itype(imm, rs1, rd, 3'b000, 7'h67);
  endfunction
  function automatic logic [31:0] beq(input logic [4:0] rs1, rs2, input logic [12:0] imm);
    return {imm[12], imm[10:5], rs2, rs1, 3'b000, imm[4:1], imm[11], 7'h63};
  endfunction

  localparam logic [31:0] ECALL = 32'h0000_0073;

  // =========================================================================
  // TPR/TCR values and CSR addresses
  // =========================================================================
  localparam logic [11:0] CSR_MTVEC   = 12'h305;
  localparam logic [11:0] CSR_TCR     = 12'h7C2;
  localparam logic [11:0] CSR_TPR     = 12'h7C3;

  // =========================================================================
  // Utility: load a program starting at instruction memory word address 0
  // =========================================================================
  int pc_wr;
  task automatic load_insn(input logic [31:0] insn);
    instr_mem[pc_wr++] = insn;
  endtask

  task automatic run_program(input int max_cycles = 200);
    exception_seen = 1'b0;
    repeat(max_cycles) begin
      @(posedge clk);
      if (dift_exception) exception_seen = 1'b1;
    end
  endtask

  // =========================================================================
  // Startup routine that programs TPR/TCR and then runs the test body
  // =========================================================================
  localparam int HANDLER_IDX = 10'h100; // word index 256

  task automatic build_preamble(input logic [31:0] tpr_val, tcr_val);
    // Set mtvec to BOOT_ADDR + 0x400 (handler index * 4)
    load_insn(lui(5'd5, 20'h10000));          // t0 = 0x1000_0000
    load_insn(addi(5'd5, 5'd5, 12'h400));     // t0 = 0x1000_0400
    load_insn(csrrw(CSR_MTVEC, 5'd5, 5'd0));

    // Program TPR
    begin
      automatic logic [31:0] tv;
      tv = tpr_val;
      if (tv[11]) tv[31:12] = tv[31:12] + 20'h1;
      if (tv[31:12] != 0)
        load_insn(lui(5'd5, tv[31:12]));
      else
        load_insn(addi(5'd5, 5'd0, 12'h0));
      if (tpr_val[11:0] != 0)
        load_insn(addi(5'd5, 5'd5, tpr_val[11:0]));
      load_insn(csrrw(CSR_TPR, 5'd5, 5'd0));
    end

    // Program TCR
    begin
      automatic logic [31:0] tv;
      tv = tcr_val;
      if (tv[11]) tv[31:12] = tv[31:12] + 20'h1;
      if (tv[31:12] != 0)
        load_insn(lui(5'd6, tv[31:12]));
      else
        load_insn(addi(5'd6, 5'd0, 12'h0));
      if (tcr_val[11:0] != 0)
        load_insn(addi(5'd6, 5'd6, tcr_val[11:0]));
      load_insn(csrrw(CSR_TCR, 5'd6, 5'd0));
    end
  endtask

  task automatic build_handler();
    int idx = HANDLER_IDX;
    instr_mem[idx++] = lui(5'd31, 20'hDEADB);
    instr_mem[idx++] = addi(5'd31, 5'd0, 12'hABC);
    instr_mem[idx++] = 32'hFE000CE3; // beq x0,x0,-8
  endtask

  // =========================================================================
  // Helpers for policy encoding
  // =========================================================================
  function automatic logic [31:0] tpr_mode_only(
    input int low, input int high, input logic [1:0] mode);
    logic [31:0] v;
    v = 32'h0;
    v[low +: 2] = mode;
    return v;
  endfunction

  function automatic logic [31:0] tpr_with_ls_en(
    input logic [31:0] base, input logic en_addr, input logic en_data, input logic en_dest);
    logic [31:0] v;
    v = base;
    v[LOADSTORE_EN_SOURCE_ADDR] = en_addr;
    v[LOADSTORE_EN_SOURCE]      = en_data;
    v[LOADSTORE_EN_DEST_ADDR]   = en_dest;
    return v;
  endfunction

  function automatic logic expected_tag(input logic [1:0] mode, input logic a, b);
    logic res;
    begin
      unique case (mode)
        ALU_MODE_OLD:   res = 1'b0;
        ALU_MODE_AND:   res = a & b;
        ALU_MODE_OR:    res = a | b;
        ALU_MODE_CLEAR: res = 1'b0;
        default:        res = 1'b0;
      endcase
      return res;
    end
  endfunction

  // =========================================================================
  // Test 1-4: TPR propagation modes (integer, logical, shift, comparison)
  // =========================================================================
  task automatic test_integer_modes;
    logic [1:0] mode;
    logic exp_tag;
    for (int m = 0; m < 4; m++) begin
      mode = m[1:0];
      test_num++;

      pc_wr = BOOT_WORD;
      build_handler();
      build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
      load_insn(lui(5'd10, 20'h00010));
      load_insn(lw(5'd12, 5'd10, 12'h0));
      load_insn(lw(5'd13, 5'd10, 12'h4));
      build_preamble(tpr_mode_only(INTEGER_LOW, INTEGER_HIGH, mode), 32'h0);
      load_insn(add(5'd14, 5'd12, 5'd13));
      load_insn(ECALL);

      do_reset();
      tag_mem[0] = 1'b1; data_mem[0] = 32'd1;
      tag_mem[1] = 1'b0; data_mem[1] = 32'd2;
      run_program(150);

      exp_tag = expected_tag(mode, 1'b1, 1'b0);
      if (dut.tag_register_file_i.rf_reg[14][0] === exp_tag)
        pass("TPR INTEGER mode propagation");
      else
        fail("TPR INTEGER mode propagation");
    end
  endtask

  task automatic test_logical_modes;
    logic [1:0] mode;
    logic exp_tag;
    for (int m = 0; m < 4; m++) begin
      mode = m[1:0];
      test_num++;

      pc_wr = BOOT_WORD;
      build_handler();
      build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
      load_insn(lui(5'd10, 20'h00010));
      load_insn(lw(5'd12, 5'd10, 12'h0));
      load_insn(lw(5'd13, 5'd10, 12'h4));
      build_preamble(tpr_mode_only(LOGICAL_LOW, LOGICAL_HIGH, mode), 32'h0);
      load_insn(or_insn(5'd14, 5'd12, 5'd13));
      load_insn(ECALL);

      do_reset();
      tag_mem[0] = 1'b1; data_mem[0] = 32'd3;
      tag_mem[1] = 1'b0; data_mem[1] = 32'd4;
      run_program(150);

      exp_tag = expected_tag(mode, 1'b1, 1'b0);
      if (dut.tag_register_file_i.rf_reg[14][0] === exp_tag)
        pass("TPR LOGICAL mode propagation");
      else
        fail("TPR LOGICAL mode propagation");
    end
  endtask

  task automatic test_shift_modes;
    logic [1:0] mode;
    logic exp_tag;
    for (int m = 0; m < 4; m++) begin
      mode = m[1:0];
      test_num++;

      pc_wr = BOOT_WORD;
      build_handler();
      build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
      load_insn(lui(5'd10, 20'h00010));
      load_insn(lw(5'd12, 5'd10, 12'h0));
      build_preamble(tpr_mode_only(SHIFT_LOW, SHIFT_HIGH, mode), 32'h0);
      load_insn(slli(5'd14, 5'd12, 5'd1));
      load_insn(ECALL);

      do_reset();
      tag_mem[0] = 1'b1; data_mem[0] = 32'd5;
      run_program(150);

      exp_tag = expected_tag(mode, 1'b1, 1'b0);
      if (dut.tag_register_file_i.rf_reg[14][0] === exp_tag)
        pass("TPR SHIFT mode propagation");
      else
        fail("TPR SHIFT mode propagation");
    end
  endtask

  task automatic test_compare_modes;
    logic [1:0] mode;
    logic exp_tag;
    for (int m = 0; m < 4; m++) begin
      mode = m[1:0];
      test_num++;

      pc_wr = BOOT_WORD;
      build_handler();
      build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
      load_insn(lui(5'd10, 20'h00010));
      load_insn(lw(5'd12, 5'd10, 12'h0));
      load_insn(lw(5'd13, 5'd10, 12'h4));
      build_preamble(tpr_mode_only(COMPARISON_LOW, COMPARISON_HIGH, mode), 32'h0);
      load_insn(slt(5'd14, 5'd12, 5'd13));
      load_insn(ECALL);

      do_reset();
      tag_mem[0] = 1'b1; data_mem[0] = 32'd1;
      tag_mem[1] = 1'b0; data_mem[1] = 32'd2;
      run_program(150);

      exp_tag = expected_tag(mode, 1'b1, 1'b0);
      if (dut.tag_register_file_i.rf_reg[14][0] === exp_tag)
        pass("TPR COMPARISON mode propagation");
      else
        fail("TPR COMPARISON mode propagation");
    end
  endtask

  // =========================================================================
  // Test 5: TPR jump mode propagation (JALR writes rd)
  // =========================================================================
  task automatic test_jump_modes;
    logic [1:0] mode;
    logic exp_tag;
    int ecall_idx;
    for (int m = 0; m < 4; m++) begin
      mode = m[1:0];
      test_num++;

      pc_wr = BOOT_WORD;
      build_handler();
      build_preamble(
        tpr_with_ls_en(
          tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR) |
          tpr_mode_only(JUMP_LOW, JUMP_HIGH, mode),
          1'b1, 1'b1, 1'b0
        ),
        32'h0
      );
      load_insn(lui(5'd10, 20'h00010));
      load_insn(lw(5'd12, 5'd10, 12'h0));
      load_insn(jalr(5'd14, 5'd12, 12'h0));
      load_insn(ECALL);
      ecall_idx = pc_wr - 1;

      do_reset();
      tag_mem[0] = 1'b1; data_mem[0] = BOOT_ADDR + (ecall_idx * 4); // jump target
      run_program(150);

      // Ibex JALR writes rd with PC+4 in cycle 2 (PC tag path); PC is clean here.
      exp_tag = expected_tag(mode, 1'b0, 1'b0);
      if (dut.tag_register_file_i.rf_reg[14][0] === exp_tag)
        pass("TPR JUMP mode propagation");
      else
        fail("TPR JUMP mode propagation");
    end
  endtask

  // =========================================================================
  // Test 6: Load propagation modes (TPR LOADSTORE)
  // =========================================================================
  task automatic test_load_modes;
    logic [1:0] mode;
    logic exp_tag;
    for (int m = 0; m < 4; m++) begin
      mode = m[1:0];
      test_num++;

      pc_wr = BOOT_WORD;
      build_handler();
      build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, mode), 1'b1, 1'b1, 1'b0), 32'h0);
      load_insn(lui(5'd10, 20'h00010));
      load_insn(lw(5'd12, 5'd10, 12'h0));
      load_insn(ECALL);

      do_reset();
      tag_mem[0] = 1'b1; data_mem[0] = 32'd9;
      run_program(150);

      exp_tag = expected_tag(mode, 1'b0, 1'b1);
      if (dut.tag_register_file_i.rf_reg[12][0] === exp_tag)
        pass("TPR LOADSTORE mode propagation (load)");
      else
        fail("TPR LOADSTORE mode propagation (load)");
    end
  endtask

  // =========================================================================
  // Test 7: Store propagates tag to shadow RAM
  // =========================================================================
  task automatic test_store_propagation;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b1), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(sw(5'd12, 5'd10, 12'h4));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'hDEAD_BEEF;
    tag_mem[1] = 1'b0; data_mem[1] = 32'h0;
    run_program(150);

    if (tag_mem[1] === 1'b1)
      pass("Store tag propagation to shadow RAM");
    else
      fail("Store tag propagation to shadow RAM");
  endtask

  // =========================================================================
  // Test 8-13: TCR checks (integer, logical, shift, comparison, branch, jump)
  // =========================================================================
  task automatic test_tcr_integer_checks;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(INTEGER_LOW, INTEGER_HIGH, ALU_MODE_OR), (32'h1 << INTEGER_CHECK_S1));
    load_insn(add(5'd14, 5'd12, 5'd13));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd1;
    tag_mem[1] = 1'b0; data_mem[1] = 32'd2;
    run_program(150);

    if (exception_seen)
      pass("TCR INTEGER_CHECK_S1 exception");
    else
      fail("TCR INTEGER_CHECK_S1 exception");
  endtask

  task automatic test_tcr_integer_checks_s2;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(INTEGER_LOW, INTEGER_HIGH, ALU_MODE_OR), (32'h1 << INTEGER_CHECK_S2));
    load_insn(add(5'd14, 5'd12, 5'd13));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b0; data_mem[0] = 32'd1;
    tag_mem[1] = 1'b1; data_mem[1] = 32'd2;
    run_program(150);

    if (exception_seen)
      pass("TCR INTEGER_CHECK_S2 exception");
    else
      fail("TCR INTEGER_CHECK_S2 exception");
  endtask

  task automatic test_tcr_integer_checks_d;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(INTEGER_LOW, INTEGER_HIGH, ALU_MODE_OR), (32'h1 << INTEGER_CHECK_D));
    load_insn(add(5'd14, 5'd12, 5'd13));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd1;
    tag_mem[1] = 1'b0; data_mem[1] = 32'd2;
    run_program(150);

    if (exception_seen)
      pass("TCR INTEGER_CHECK_D exception");
    else
      fail("TCR INTEGER_CHECK_D exception");
  endtask

  task automatic test_tcr_logical_checks;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(LOGICAL_LOW, LOGICAL_HIGH, ALU_MODE_OR), (32'h1 << LOGICAL_CHECK_D));
    load_insn(and_insn(5'd14, 5'd12, 5'd13));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd3;
    tag_mem[1] = 1'b0; data_mem[1] = 32'd4;
    run_program(150);

    if (exception_seen)
      pass("TCR LOGICAL_CHECK_D exception");
    else
      fail("TCR LOGICAL_CHECK_D exception");
  endtask

  task automatic test_tcr_logical_checks_s1;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(LOGICAL_LOW, LOGICAL_HIGH, ALU_MODE_OR), (32'h1 << LOGICAL_CHECK_S1));
    load_insn(xor_insn(5'd14, 5'd12, 5'd13));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd3;
    tag_mem[1] = 1'b0; data_mem[1] = 32'd4;
    run_program(150);

    if (exception_seen)
      pass("TCR LOGICAL_CHECK_S1 exception");
    else
      fail("TCR LOGICAL_CHECK_S1 exception");
  endtask

  task automatic test_tcr_logical_checks_s2;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(LOGICAL_LOW, LOGICAL_HIGH, ALU_MODE_OR), (32'h1 << LOGICAL_CHECK_S2));
    load_insn(xor_insn(5'd14, 5'd12, 5'd13));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b0; data_mem[0] = 32'd3;
    tag_mem[1] = 1'b1; data_mem[1] = 32'd4;
    run_program(150);

    if (exception_seen)
      pass("TCR LOGICAL_CHECK_S2 exception");
    else
      fail("TCR LOGICAL_CHECK_S2 exception");
  endtask

  task automatic test_tcr_shift_checks;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    build_preamble(tpr_mode_only(SHIFT_LOW, SHIFT_HIGH, ALU_MODE_OR), (32'h1 << SHIFT_CHECK_S1));
    load_insn(srli(5'd14, 5'd12, 5'd1));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd5;
    run_program(150);

    if (exception_seen)
      pass("TCR SHIFT_CHECK_S1 exception");
    else
      fail("TCR SHIFT_CHECK_S1 exception");
  endtask

  task automatic test_tcr_shift_checks_s2;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(SHIFT_LOW, SHIFT_HIGH, ALU_MODE_OR), (32'h1 << SHIFT_CHECK_S2));
    load_insn(rtype(7'h00, 5'd13, 5'd12, 5'd14, 3'b001, 7'h33)); // sll x14, x12, x13
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b0; data_mem[0] = 32'd1;
    tag_mem[1] = 1'b1; data_mem[1] = 32'd1;
    run_program(150);

    if (exception_seen)
      pass("TCR SHIFT_CHECK_S2 exception");
    else
      fail("TCR SHIFT_CHECK_S2 exception");
  endtask

  task automatic test_tcr_shift_checks_d;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    build_preamble(tpr_mode_only(SHIFT_LOW, SHIFT_HIGH, ALU_MODE_OR), (32'h1 << SHIFT_CHECK_D));
    load_insn(slli(5'd14, 5'd12, 5'd1));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd1;
    run_program(150);

    if (exception_seen)
      pass("TCR SHIFT_CHECK_D exception");
    else
      fail("TCR SHIFT_CHECK_D exception");
  endtask

  task automatic test_tcr_compare_checks;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(COMPARISON_LOW, COMPARISON_HIGH, ALU_MODE_OR), (32'h1 << COMPARISON_CHECK_D));
    load_insn(slt(5'd14, 5'd12, 5'd13));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd1;
    tag_mem[1] = 1'b0; data_mem[1] = 32'd2;
    run_program(150);

    if (exception_seen)
      pass("TCR COMPARISON_CHECK_D exception");
    else
      fail("TCR COMPARISON_CHECK_D exception");
  endtask

  task automatic test_tcr_compare_checks_s1;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(COMPARISON_LOW, COMPARISON_HIGH, ALU_MODE_OR), (32'h1 << COMPARISON_CHECK_S1));
    load_insn(slt(5'd14, 5'd12, 5'd13));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd1;
    tag_mem[1] = 1'b0; data_mem[1] = 32'd2;
    run_program(150);

    if (exception_seen)
      pass("TCR COMPARISON_CHECK_S1 exception");
    else
      fail("TCR COMPARISON_CHECK_S1 exception");
  endtask

  task automatic test_tcr_compare_checks_s2;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(COMPARISON_LOW, COMPARISON_HIGH, ALU_MODE_OR), (32'h1 << COMPARISON_CHECK_S2));
    load_insn(slt(5'd14, 5'd12, 5'd13));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b0; data_mem[0] = 32'd1;
    tag_mem[1] = 1'b1; data_mem[1] = 32'd2;
    run_program(150);

    if (exception_seen)
      pass("TCR COMPARISON_CHECK_S2 exception");
    else
      fail("TCR COMPARISON_CHECK_S2 exception");
  endtask

  task automatic test_tcr_branch_checks;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(BRANCH_LOW, BRANCH_HIGH, ALU_MODE_OR), (32'h1 << BRANCH_CHECK_S1));
    load_insn(beq(5'd12, 5'd13, 13'h004));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd1;
    tag_mem[1] = 1'b0; data_mem[1] = 32'd1;
    run_program(150);

    if (exception_seen)
      pass("TCR BRANCH_CHECK_S1 exception");
    else
      fail("TCR BRANCH_CHECK_S1 exception");
  endtask

  task automatic test_tcr_branch_checks_s2;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(BRANCH_LOW, BRANCH_HIGH, ALU_MODE_OR), (32'h1 << BRANCH_CHECK_S2));
    load_insn(beq(5'd12, 5'd13, 13'h004));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b0; data_mem[0] = 32'd1;
    tag_mem[1] = 1'b1; data_mem[1] = 32'd1;
    run_program(150);

    if (exception_seen)
      pass("TCR BRANCH_CHECK_S2 exception");
    else
      fail("TCR BRANCH_CHECK_S2 exception");
  endtask

  task automatic test_tcr_branch_checks_not_taken;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(BRANCH_LOW, BRANCH_HIGH, ALU_MODE_OR), (32'h1 << BRANCH_CHECK_S1));
    load_insn(beq(5'd12, 5'd13, 13'h004));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd1;
    tag_mem[1] = 1'b0; data_mem[1] = 32'd2;
    run_program(150);

    if (exception_seen)
      pass("TCR BRANCH_CHECK_S1 exception (not taken)");
    else
      fail("TCR BRANCH_CHECK_S1 exception (not taken)");
  endtask

  task automatic test_tcr_jump_checks;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    build_preamble(tpr_mode_only(JUMP_LOW, JUMP_HIGH, ALU_MODE_OR), (32'h1 << JUMP_CHECK_S1));
    load_insn(jalr(5'd14, 5'd12, 12'h0));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = BOOT_ADDR + 32'h80;
    run_program(150);

    if (exception_seen)
      pass("TCR JUMP_CHECK_S1 exception");
    else
      fail("TCR JUMP_CHECK_S1 exception");
  endtask

  task automatic test_tcr_jump_checks_d;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    build_preamble(tpr_mode_only(JUMP_LOW, JUMP_HIGH, ALU_MODE_OR), (32'h1 << JUMP_CHECK_D));
    load_insn(jalr(5'd14, 5'd12, 12'h0));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = BOOT_ADDR + 32'h80;
    run_program(150);

    if (exception_seen)
      pass("TCR JUMP_CHECK_D exception");
    else
      fail("TCR JUMP_CHECK_D exception");
  endtask

  task automatic test_execute_pc_violation_jalr;
    int ecall_idx;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(
      tpr_with_ls_en(
        tpr_mode_only(JUMP_LOW, JUMP_HIGH, ALU_MODE_OR) |
        tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR),
        1'b1, 1'b1, 1'b0
      ),
      (32'h1 << EXECUTE_PC)
    );
    load_insn(lui(5'd11, 20'h00010));
    load_insn(lw(5'd10, 5'd11, 12'h0));
    load_insn(jalr(5'd0, 5'd10, 12'h0));
    load_insn(addi(5'd1, 5'd0, 12'd1));
    load_insn(ECALL);
    ecall_idx = pc_wr - 1;

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = BOOT_ADDR + (ecall_idx * 4);
    run_program(200);

    if (exception_seen)
      pass("EXECUTE_PC violation after tainted jalr");
    else
      fail("EXECUTE_PC violation after tainted jalr");
  endtask

  // =========================================================================
  // Test 14-15: TCR load/store checks
  // =========================================================================
  task automatic test_tcr_store_checks;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b1), (32'h1 << LOADSTORE_CHECK_S));
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(sw(5'd12, 5'd10, 12'h4));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd11;
    run_program(150);

    if (exception_seen)
      pass("TCR LOADSTORE_CHECK_S exception (store data)");
    else
      fail("TCR LOADSTORE_CHECK_S exception (store data)");
  endtask

  task automatic test_tcr_store_addr_checks;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b1), (32'h1 << LOADSTORE_CHECK_DA));
    load_insn(lui(5'd11, 20'h00010));
    load_insn(lw(5'd10, 5'd11, 12'h0));
    load_insn(lw(5'd12, 5'd11, 12'h4));
    load_insn(sw(5'd12, 5'd10, 12'h0));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = DMEM_BASE; // taint base register via load
    tag_mem[1] = 1'b0; data_mem[1] = 32'd11;
    run_program(150);

    if (exception_seen)
      pass("TCR LOADSTORE_CHECK_DA exception (store address)");
    else
      fail("TCR LOADSTORE_CHECK_DA exception (store address)");
  endtask

  task automatic test_tcr_load_checks;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), (32'h1 << LOADSTORE_CHECK_D));
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd12;
    run_program(150);

    if (exception_seen)
      pass("TCR LOADSTORE_CHECK_D exception (load dest)");
    else
      fail("TCR LOADSTORE_CHECK_D exception (load dest)");
  endtask

  task automatic test_tcr_load_addr_checks;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), (32'h1 << LOADSTORE_CHECK_SA));
    load_insn(lui(5'd11, 20'h00010));
    load_insn(lw(5'd10, 5'd11, 12'h0));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = DMEM_BASE; // taint base register
    run_program(150);

    if (exception_seen)
      pass("TCR LOADSTORE_CHECK_SA exception (load address)");
    else
      fail("TCR LOADSTORE_CHECK_SA exception (load address)");
  endtask

  // =========================================================================
  // CSR instruction path tests
  // =========================================================================
  task automatic test_csr_paths;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(32'h0, 32'h0);

    // TPR: csrrwi -> csrrs -> csrrc -> read
    load_insn(csrrwi(CSR_TPR, 5'h15, 5'd0));
    load_insn(addi(5'd5, 5'd0, 12'h00A));
    load_insn(csrrs(CSR_TPR, 5'd5, 5'd0));
    load_insn(addi(5'd6, 5'd0, 12'h005));
    load_insn(csrrc(CSR_TPR, 5'd6, 5'd0));
    load_insn(csrrs(CSR_TPR, 5'd0, 5'd7));

    // TCR: csrrw -> csrrc -> read
    load_insn(addi(5'd5, 5'd0, 12'h03F));
    load_insn(csrrw(CSR_TCR, 5'd5, 5'd0));
    load_insn(addi(5'd6, 5'd0, 12'h005));
    load_insn(csrrc(CSR_TCR, 5'd6, 5'd0));
    load_insn(csrrs(CSR_TCR, 5'd0, 5'd8));
    load_insn(ECALL);

    do_reset();
    run_program(200);

    if (reg_file[7] == 32'h0000_001A && reg_file[8] == 32'h0000_003A)
      pass("CSR paths: csrrw/csrrs/csrrc/csrrwi readback");
    else
      fail("CSR paths: csrrw/csrrs/csrrc/csrrwi readback");
  endtask

  // =========================================================================
  // M-extension tests (mul/div/rem)
  // =========================================================================
  task automatic test_m_op_modes;
    logic [1:0] mode;
    logic exp_tag;
    for (int m = 0; m < 4; m++) begin
      mode = m[1:0];
      test_num++;

      pc_wr = BOOT_WORD;
      build_handler();
      build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
      load_insn(lui(5'd10, 20'h00010));
      load_insn(lw(5'd12, 5'd10, 12'h0));
      load_insn(lw(5'd13, 5'd10, 12'h4));
      build_preamble(tpr_mode_only(INTEGER_LOW, INTEGER_HIGH, mode), 32'h0);
      load_insn(mul(5'd14, 5'd12, 5'd13));
      load_insn(ECALL);

      do_reset();
      tag_mem[0] = 1'b1; data_mem[0] = 32'd3;
      tag_mem[1] = 1'b0; data_mem[1] = 32'd2;
      run_program(200);

      exp_tag = expected_tag(mode, 1'b1, 1'b0);
      if (dut.tag_register_file_i.rf_reg[14][0] === exp_tag)
        pass("M-extension MUL tag propagation");
      else
        fail("M-extension MUL tag propagation");
    end
  endtask

  task automatic test_m_op_or_cases;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(INTEGER_LOW, INTEGER_HIGH, ALU_MODE_OR), 32'h0);
    load_insn(div(5'd14, 5'd12, 5'd13));
    load_insn(rem(5'd15, 5'd12, 5'd13));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd9;
    tag_mem[1] = 1'b0; data_mem[1] = 32'd3;
    run_program(300);

    if (dut.tag_register_file_i.rf_reg[14][0] === 1'b1 && dut.tag_register_file_i.rf_reg[15][0] === 1'b1)
      pass("M-extension DIV/REM OR propagation");
    else
      fail("M-extension DIV/REM OR propagation");
  endtask

  task automatic test_m_op_checks;
    test_num++;

    pc_wr = BOOT_WORD;
    build_handler();
    build_preamble(tpr_with_ls_en(tpr_mode_only(LOADSTORE_LOW, LOADSTORE_HIGH, ALU_MODE_OR), 1'b1, 1'b1, 1'b0), 32'h0);
    load_insn(lui(5'd10, 20'h00010));
    load_insn(lw(5'd12, 5'd10, 12'h0));
    load_insn(lw(5'd13, 5'd10, 12'h4));
    build_preamble(tpr_mode_only(INTEGER_LOW, INTEGER_HIGH, ALU_MODE_OR), (32'h1 << INTEGER_CHECK_D));
    load_insn(mul(5'd14, 5'd12, 5'd13));
    load_insn(ECALL);

    do_reset();
    tag_mem[0] = 1'b1; data_mem[0] = 32'd6;
    tag_mem[1] = 1'b0; data_mem[1] = 32'd2;
    run_program(200);

    if (exception_seen)
      pass("M-extension INTEGER_CHECK_D exception");
    else
      fail("M-extension INTEGER_CHECK_D exception");
  endtask

  // =========================================================================
  // MAIN
  // =========================================================================
  integer f_log;

  initial begin
    $timeformat(-9, 1, "ns", 8);

    f_log = $fopen("dift_tb_exhaustive_results.log", "w");
    $fdisplay(f_log, "D-Ibex DIFT Exhaustive Testbench Results");
    $fdisplay(f_log, "========================================");

    pass_count = 0;
    fail_count = 0;
    test_num   = 0;

    for (int i = 0; i < MEM_DEPTH; i++) instr_mem[i] = NOP;

    rst_n = 0;
    @(posedge clk); @(posedge clk);

    test_integer_modes();
    test_logical_modes();
    test_shift_modes();
    test_compare_modes();
    test_jump_modes();
    test_load_modes();
    test_store_propagation();
    test_tcr_integer_checks();
    test_tcr_integer_checks_s2();
    test_tcr_integer_checks_d();
    test_tcr_logical_checks();
    test_tcr_logical_checks_s1();
    test_tcr_logical_checks_s2();
    test_tcr_shift_checks();
    test_tcr_shift_checks_s2();
    test_tcr_shift_checks_d();
    test_tcr_compare_checks();
    test_tcr_compare_checks_s1();
    test_tcr_compare_checks_s2();
    test_tcr_branch_checks();
    test_tcr_branch_checks_s2();
    test_tcr_branch_checks_not_taken();
    test_tcr_jump_checks();
    test_tcr_jump_checks_d();
    test_execute_pc_violation_jalr();
    test_tcr_store_checks();
    test_tcr_store_addr_checks();
    test_tcr_load_checks();
    test_tcr_load_addr_checks();
    test_csr_paths();
    test_m_op_modes();
    test_m_op_or_cases();
    test_m_op_checks();

    $display("");
    $display("===== DIFT Exhaustive Testbench Complete =====");
    $display("  PASSED: %0d / %0d", pass_count, pass_count+fail_count);
    $display("  FAILED: %0d / %0d", fail_count, pass_count+fail_count);

    $fdisplay(f_log, "PASSED: %0d  FAILED: %0d", pass_count, fail_count);
    $fclose(f_log);

    if (fail_count == 0)
      $display("ALL TESTS PASSED");
    else
      $display("SOME TESTS FAILED — review output above");

    $finish;
  end

  // =========================================================================
  // Timeout watchdog
  // =========================================================================
  initial begin
    #500000;
    $display("[TIMEOUT] Simulation exceeded 500us — possible infinite loop");
    $finish;
  end

  // =========================================================================
  // Waveform dump (Vivado xsim compatible)
  // =========================================================================
  initial begin
    $dumpfile("dift_tb1.vcd");
    $dumpvars(1, ibex_core_tb);
  end

endmodule
