// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

//Register file for fpga implementation, with tag storage for DIFT. 
//This is a simple dual-port RAM with synchronous write and asynchronous read, implemented as a behavioral array to allow Vivado to infer RAM32M primitives. 
//The register file is initialized to zero on power-up, meaning all registers start untainted.

module ibex_register_file_fpga_tag #(
    parameter bit                   RV32E             = 0,
    parameter int unsigned          DataWidth         = 1,
    parameter bit                   DummyInstructions = 0,
    parameter logic [DataWidth-1:0] WordZeroVal       = '0
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic                 test_en_i,
  input  logic                 dummy_instr_id_i,
  input  logic                 dummy_instr_wb_i,
  input  logic [          4:0] raddr_a_i,
  output logic [DataWidth-1:0] rdata_a_o,
  input  logic [          4:0] raddr_b_i,
  output logic [DataWidth-1:0] rdata_b_o,
  input  logic [          4:0] waddr_a_i,
  input  logic [DataWidth-1:0] wdata_a_i,
  input  logic                 we_a_i
);

  localparam int ADDR_WIDTH = RV32E ? 4 : 5;
  localparam int NUM_WORDS  = 2 ** ADDR_WIDTH;

  logic [DataWidth-1:0] mem [NUM_WORDS];

  // R0 always reads as zero; all other addresses read directly from RAM
  assign rdata_a_o = (raddr_a_i == '0) ? WordZeroVal : mem[raddr_a_i];
  assign rdata_b_o = (raddr_b_i == '0) ? WordZeroVal : mem[raddr_b_i];

  // Write enable: suppress writes to R0
  logic we;
  assign we = (waddr_a_i == '0) ? 1'b0 : we_a_i;

  // always (not always_ff) so Vivado infers RAM32M primitives correctly
  always @(posedge clk_i) begin : sync_write
    if (we) begin
      mem[waddr_a_i] <= wdata_a_i;
    end
  end

  // Initialise RAM to zero (tags start clean = untainted)
  initial begin
    for (int k = 0; k < NUM_WORDS; k++) begin
      mem[k] = WordZeroVal;
    end
  end

  // Unused signal tie-offs to suppress lint warnings
  logic unused_rst_ni;
  logic unused_test_en;
  logic unused_dummy_instr;
  assign unused_rst_ni      = rst_ni;
  assign unused_test_en     = test_en_i;
  assign unused_dummy_instr = dummy_instr_id_i ^ dummy_instr_wb_i;

endmodule