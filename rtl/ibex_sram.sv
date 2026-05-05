//This is a simple behavioral model of an SRAM, used for FPGA implementation. 
//It does not model timing or other physical characteristics of an actual SRAM, but it provides a simple way to implement the memory for the register file and data memory on an FPGA. 
//The memory is initialized to zero on power-up=all memory locations start untainted.

module ibex_sram
  #(
    parameter ADDR_WIDTH = 11,
    parameter DATA_WIDTH = 32,
    parameter NUM_WORDS  = 1024
  )(
    // Clock and Reset
    input  logic                    clk,

    input  logic                    en_i,
    input  logic [ADDR_WIDTH-1:0]   addr_i,
    input  logic [DATA_WIDTH-1:0]   wdata_i,
    output logic [DATA_WIDTH-1:0]   rdata_o,
    input  logic                    we_i,
    input  logic [DATA_WIDTH/8-1:0] be_i
  );

  localparam words = NUM_WORDS/(DATA_WIDTH/8);

  logic [DATA_WIDTH/8-1:0][7:0] mem[words];
  logic [DATA_WIDTH/8-1:0][7:0] wdata;
  logic [ADDR_WIDTH-1-$clog2(DATA_WIDTH/8):0] addr;

  integer i;


  assign addr = addr_i[ADDR_WIDTH-1:$clog2(DATA_WIDTH/8)];


  always @(posedge clk)
  begin
    if (en_i && we_i)
    begin
      for (i = 0; i < DATA_WIDTH/8; i++) begin
        if (be_i[i])
          mem[addr][i] <= wdata[i];
      end
    end

    rdata_o <= mem[addr];
  end

  genvar w;
  generate for(w = 0; w < DATA_WIDTH/8; w++)
    begin
      assign wdata[w] = wdata_i[(w+1)*8-1:w*8];
    end
  endgenerate

endmodule