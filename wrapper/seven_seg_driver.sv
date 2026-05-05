// seven_seg_driver.sv
// Multiplexed 8-digit 7-segment display driver for Nexys A7

module seven_seg_driver (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [31:0] value_i,
  output logic [ 6:0] seg_o,   // cathode segments [6:0] = {g,f,e,d,c,b,a}
  output logic [ 7:0] an_o     // active-low anode select
);

  // Divide 100 MHz clock to ~1 kHz refresh rate for multiplexing the 8 digits.
  // Use 17-bit counter -> rolls over every 131 072 cycles (~762 Hz)
  logic [16:0] clk_div;
  logic [ 2:0] digit_sel;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      clk_div   <= '0;
      digit_sel <= '0;
    end else begin
      clk_div <= clk_div + 1'b1;
      if (clk_div == 17'd99_999) begin
        clk_div   <= '0;
        digit_sel <= digit_sel + 1'b1;
      end
    end
  end

  // Select the correct nibble
  logic [3:0] nibble;
  always_comb begin
    case (digit_sel)
      3'd0: nibble = value_i[ 3: 0];
      3'd1: nibble = value_i[ 7: 4];
      3'd2: nibble = value_i[11: 8];
      3'd3: nibble = value_i[15:12];
      3'd4: nibble = value_i[19:16];
      3'd5: nibble = value_i[23:20];
      3'd6: nibble = value_i[27:24];
      3'd7: nibble = value_i[31:28];
      default: nibble = 4'h0;
    endcase
  end

  // Active-low anode select
  always_comb begin
    an_o = 8'hFF;
    an_o[digit_sel] = 1'b0;
  end

  // 7-segment decode (active-low cathodes, segments: gfedcba)
  always_comb begin
    case (nibble)
      4'h0: seg_o = 7'b100_0000; // 0
      4'h1: seg_o = 7'b111_1001; // 1
      4'h2: seg_o = 7'b010_0100; // 2
      4'h3: seg_o = 7'b011_0000; // 3
      4'h4: seg_o = 7'b001_1001; // 4
      4'h5: seg_o = 7'b001_0010; // 5
      4'h6: seg_o = 7'b000_0010; // 6
      4'h7: seg_o = 7'b111_1000; // 7
      4'h8: seg_o = 7'b000_0000; // 8
      4'h9: seg_o = 7'b001_0000; // 9
      4'hA: seg_o = 7'b000_1000; // A
      4'hB: seg_o = 7'b000_0011; // b
      4'hC: seg_o = 7'b100_0110; // C
      4'hD: seg_o = 7'b010_0001; // d
      4'hE: seg_o = 7'b000_0110; // E
      4'hF: seg_o = 7'b000_1110; // F
      default: seg_o = 7'b111_1111; // blank
    endcase
  end

endmodule
