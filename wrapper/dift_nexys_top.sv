// dift_nexys_top.sv
// Top-level wrapper for DIFT-enabled Ibex on Nexys A7-100T.

module dift_nexys_top (
  input  logic        CLK100MHZ,
  input  logic        CPU_RESETN,       // active-low on Nexys A7
  input  logic [15:0] SW,               // SW[0]=clear exception, SW[1]=inject tainted pointer
  output logic [15:0] LED,
  output logic [ 6:0] SEG,             // 7-segment cathodes (active-low)
  output logic [ 7:0] AN,              // 7-segment anodes   (active-low)
  output logic        UART_TXD_IN      // UART TX (tied high – unused)
);

  import ibex_pkg::*;

  // -----------------------------------------------------------------------
  // Clock and reset
  // -----------------------------------------------------------------------
  logic clk, rst_n;
  assign clk   = CLK100MHZ;
  assign rst_n = CPU_RESETN;           // active-low, pass straight through

  // -----------------------------------------------------------------------
  // Memory parameters
  // -----------------------------------------------------------------------
  localparam int MEM_WORDS  = 8192;    // 32 KB instruction memory
  localparam int DMEM_WORDS = 2048;    // 8  KB data memory
  localparam logic [31:0] BOOT_ADDR = 32'h0000_0000;
  localparam logic [31:0] DMEM_BASE = 32'h0001_0000;

  
  // -----------------------------------------------------------------------
  // Instruction memory (BRAM ROM via XPM)
  // -----------------------------------------------------------------------
  logic        instr_req, instr_gnt, instr_err, instr_rvalid;
  logic [31:0] instr_addr, instr_rdata;

  localparam int IMEM_ADDR_W = $clog2(MEM_WORDS);
  logic [IMEM_ADDR_W-1:0] imem_addr;
  assign imem_addr = instr_addr[14:2];

  assign instr_gnt = 1'b1;
  assign instr_err = 1'b0;

  xpm_memory_sprom #(
    .ADDR_WIDTH_A       (IMEM_ADDR_W),
    .MEMORY_SIZE        (MEM_WORDS * 32),
    .MEMORY_PRIMITIVE   ("block"),
    .MEMORY_INIT_FILE   ("test_program.mem"),
    .MEMORY_INIT_PARAM  (""),
    .READ_DATA_WIDTH_A  (32),
    .READ_LATENCY_A     (1)
  ) u_imem (
    .clka  (clk),
    .ena   (instr_req),
    .addra (imem_addr),
    .douta (instr_rdata),
    .rsta  (1'b0),
    .regcea(1'b1)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) instr_rvalid <= 1'b0;
    else        instr_rvalid <= instr_req;
  end
  // -----------------------------------------------------------------------
  // Data memory + DIFT shadow tag RAM
  // -----------------------------------------------------------------------
  (* ram_style = "distributed" *) logic  tag_mem [0:DMEM_WORDS-1]; 

  logic        data_req, data_gnt, data_rvalid, data_we, data_err;
  logic [ 3:0] data_be;
  logic [31:0] data_addr, data_wdata, data_rdata;
  logic        data_rdata_tag, data_wdata_tag;

  logic [$clog2(DMEM_WORDS)-1:0] dmem_idx;
  assign dmem_idx = (data_addr - DMEM_BASE) >> 2;

  assign data_gnt = 1'b1;
  assign data_err = 1'b0;
  
  logic dmem_init_done;
  logic [31:0] dmem_dout;
  logic [31:0] dmem_dina;
  logic [ 3:0] dmem_wea;
  logic        dmem_ena;
  ibex_mubi_t fetch_enable;
  assign fetch_enable = dmem_init_done ? IbexMuBiOn : IbexMuBiOff;
  
  // BRAM data memory via XPM (single-port RAM with byte write)
  always_comb begin
    if (!dmem_init_done) begin
      dmem_ena  = 1'b1;
      dmem_wea  = 4'hF;
      dmem_dina = SW[1] ? 32'h0001_0008 : 32'h0000_002A;
    end else begin
      dmem_ena  = data_req;
      dmem_wea  = data_we ? data_be : 4'h0;
      dmem_dina = data_wdata;
    end
  end

  xpm_memory_spram #(
    .ADDR_WIDTH_A       ($clog2(DMEM_WORDS)),
    .MEMORY_SIZE        (DMEM_WORDS * 32),
    .MEMORY_PRIMITIVE   ("block"),
    .READ_DATA_WIDTH_A  (32),
    .WRITE_DATA_WIDTH_A (32),
    .BYTE_WRITE_WIDTH_A (8),
    .READ_LATENCY_A     (1)
  ) u_dmem (
    .clka  (clk),
    .ena   (dmem_ena),
    .wea   (dmem_wea),
    .addra (dmem_idx),
    .dina  (dmem_dina),
    .douta (dmem_dout),
    .rsta  (1'b0),
    .regcea(1'b1)
  );

  always_ff @(posedge clk) begin
    data_rdata <= dmem_dout;
    if (!dmem_init_done) begin
      tag_mem[0] <= SW[1];
    end else if (data_req && data_we) begin
      tag_mem[dmem_idx] <= data_wdata_tag;
    end
    if (data_req) begin
      data_rdata_tag <= tag_mem[dmem_idx];
    end
  end

  // rvalid can be reset independently without affecting BRAM inference
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_rvalid    <= 1'b0;
      dmem_init_done <= 1'b0;
    end else begin
      data_rvalid    <= data_req;
      dmem_init_done <= 1'b1;
    end
  end
  
  // -----------------------------------------------------------------------
  // External register file (RegFileECC=0, so ECC word = plain 32-bit data)
  // -----------------------------------------------------------------------
  (* ram_style = "distributed" *) logic [31:0] reg_file [0:31];
  logic [ 4:0] rf_raddr_a, rf_raddr_b, rf_waddr_wb;
  logic        rf_we_wb;
  logic [31:0] rf_wdata_wb_ecc, rf_rdata_a_ecc, rf_rdata_b_ecc;
  logic        dummy_instr_id, dummy_instr_wb;
  initial begin
    for (int i = 0; i < 32; i++) reg_file[i] = 32'h0;
  end

  // REMOVED hardware reset loop to allow LUTRAM inference
  always_ff @(posedge clk) begin
    if (rf_we_wb && rf_waddr_wb != 5'd0) begin
      reg_file[rf_waddr_wb] <= rf_wdata_wb_ecc;
    end
  end

  assign rf_rdata_a_ecc = (rf_raddr_a == 5'd0) ? 32'h0 : reg_file[rf_raddr_a];
  assign rf_rdata_b_ecc = (rf_raddr_b == 5'd0) ? 32'h0 : reg_file[rf_raddr_b];
  // -----------------------------------------------------------------------
  // DIFT exception capture and display
  // -----------------------------------------------------------------------
  logic       dift_exception;
  logic       exception_sticky;
  logic [7:0] exception_count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      exception_sticky <= 1'b0;
      exception_count  <= 8'h0;
    end else begin
      if (dift_exception) begin
        exception_sticky <= 1'b1;
        if (exception_count != 8'hFF)
          exception_count <= exception_count + 8'h1;
      end
      if (SW[0]) begin           // SW[0] = manual clear
        exception_sticky <= 1'b0;
        exception_count  <= 8'h0;
      end
    end
  end

  // LED mapping
  assign LED[0]    = exception_sticky;   // DIFT exception ever seen
  assign LED[1]    = dift_exception;     // DIFT exception this cycle
  assign LED[7:2]  = 6'b0;              // unused
  assign LED[15:8] = exception_count;   // count of exceptions

  // 7-segment: display exception_count as 8 hex digits
  seven_seg_driver u_seg (
    .clk_i   (clk),
    .rst_ni  (rst_n),
    .value_i ({24'b0, exception_count}),
    .seg_o   (SEG),
    .an_o    (AN)
  );

  // UART TX tied high (not used)
  assign UART_TXD_IN = 1'b1;

  // -----------------------------------------------------------------------
  // ICache stub signals (ICache=0, so these are all tieoffs)
  // -----------------------------------------------------------------------
  logic [IC_NUM_WAYS-1:0]  ic_tag_req,  ic_data_req;
  logic                    ic_tag_write, ic_data_write, ic_scr_key_req;
  logic [IC_INDEX_W-1:0]   ic_tag_addr, ic_data_addr;
  logic [IC_TAG_SIZE-1:0]  ic_tag_wdata;
  logic [IC_LINE_SIZE-1:0] ic_data_wdata;

  // Suppress unused warnings for ICache stub outputs
  logic unused_icache;
  assign unused_icache = ^{ic_tag_req, ic_data_req, ic_tag_write, ic_data_write,
                            ic_scr_key_req, ic_tag_addr, ic_data_addr,
                            ic_tag_wdata, ic_data_wdata};

  // Unused core outputs
  logic        irq_pending_unused;
  crash_dump_t crash_dump_unused;
  logic        double_fault_unused;
  ibex_mubi_t  core_busy_unused;
  logic        alert_minor_unused, alert_major_int_unused, alert_major_bus_unused;

  // -----------------------------------------------------------------------
  // Ibex core
  // -----------------------------------------------------------------------
  ibex_core #(
    .PMPEnable         (1'b0),
    .PMPGranularity    (0),
    .PMPNumRegions     (4),
    .MHPMCounterNum    (0),
    .MHPMCounterWidth  (40),
    .RV32E             (1'b0),
    .RV32M             (RV32MFast),
    .RV32B             (RV32BNone),
    .RV32ZC            (RV32ZcaZcbZcmp),
    .BranchTargetALU   (1'b0),
    .WritebackStage    (1'b0),
    .ICache            (1'b0),
    .ICacheECC         (1'b0),
    .BranchPredictor   (1'b0),
    .DbgTriggerEn      (1'b0),
    .DbgHwBreakNum     (1),
    .ResetAll          (1'b0),
    .SecureIbex        (1'b0),
    .DummyInstructions (1'b0),
    .RegFileECC        (1'b0),
    .RegFileDataWidth  (32),
    .MemECC            (1'b0),
    .MemDataWidth      (32),
    .DmBaseAddr        (32'h1A11_0000),
    .DmAddrMask        (32'h0000_0FFF),
    .DmHaltAddr        (32'h1A11_0800),
    .DmExceptionAddr   (32'h1A11_0808)
  ) u_ibex_core (
    .clk_i  (clk),
    .rst_ni (rst_n),

    .hart_id_i   (32'h0),
    .boot_addr_i (BOOT_ADDR),

    // Instruction memory interface
    .instr_req_o    (instr_req),
    .instr_gnt_i    (instr_gnt),
    .instr_rvalid_i (instr_rvalid),
    .instr_addr_o   (instr_addr),
    .instr_rdata_i  (instr_rdata),
    .instr_err_i    (instr_err),

    // Data memory interface
    .data_req_o    (data_req),
    .data_gnt_i    (data_gnt),
    .data_rvalid_i (data_rvalid),
    .data_we_o     (data_we),
    .data_be_o     (data_be),
    .data_addr_o   (data_addr),
    .data_wdata_o  (data_wdata),
    .data_rdata_i  (data_rdata),
    .data_err_i    (data_err),

    // External register file interface (RegFileECC=0: ECC word = plain word)
    .dummy_instr_id_o  (dummy_instr_id),
    .dummy_instr_wb_o  (dummy_instr_wb),
    .rf_raddr_a_o      (rf_raddr_a),
    .rf_raddr_b_o      (rf_raddr_b),
    .rf_waddr_wb_o     (rf_waddr_wb),
    .rf_we_wb_o        (rf_we_wb),
    .rf_wdata_wb_ecc_o (rf_wdata_wb_ecc),
    .rf_rdata_a_ecc_i  (rf_rdata_a_ecc),
    .rf_rdata_b_ecc_i  (rf_rdata_b_ecc),

    // ICache RAM interface (all tieoff; ICache=0)
    .ic_tag_req_o      (ic_tag_req),
    .ic_tag_write_o    (ic_tag_write),
    .ic_tag_addr_o     (ic_tag_addr),
    .ic_tag_wdata_o    (ic_tag_wdata),
    .ic_tag_rdata_i    ('{default: '0}),
    .ic_data_req_o     (ic_data_req),
    .ic_data_write_o   (ic_data_write),
    .ic_data_addr_o    (ic_data_addr),
    .ic_data_wdata_o   (ic_data_wdata),
    .ic_data_rdata_i   ('{default: '0}),
    .ic_scr_key_valid_i(1'b1),
    .ic_scr_key_req_o  (ic_scr_key_req),

    // Interrupts (all disabled)
    .irq_software_i (1'b0),
    .irq_timer_i    (1'b0),
    .irq_external_i (1'b0),
    .irq_fast_i     (15'b0),
    .irq_nm_i       (1'b0),
    .irq_pending_o  (irq_pending_unused),

    // Debug (disabled)
    .debug_req_i         (1'b0),
    .crash_dump_o        (crash_dump_unused),
    .double_fault_seen_o (double_fault_unused),

    // CPU control
    .fetch_enable_i         (fetch_enable),
    .alert_minor_o          (alert_minor_unused),
    .alert_major_internal_o (alert_major_int_unused),
    .alert_major_bus_o      (alert_major_bus_unused),
    .core_busy_o            (core_busy_unused),

    // DIFT tag memory interface
    .data_rdata_tag_i (data_rdata_tag),
    .data_wdata_tag_o (data_wdata_tag),
    .dift_exception_o (dift_exception)
  );

endmodule
