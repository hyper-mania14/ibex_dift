# nexys_a7.xdc  –  Nexys A7-100T (xc7a100tcsg324-1)
# Corrected: removed duplicate IOSTANDARD for LED[12/13],
#            fixed AN pins (must not reuse SEG pins),
#            added SW[1] constraint needed by dift_nexys_top.sv

# -----------------------------------------------------------------------
# Clock
# -----------------------------------------------------------------------
set_property PACKAGE_PIN E3  [get_ports CLK100MHZ]
set_property IOSTANDARD LVCMOS33 [get_ports CLK100MHZ]
create_clock -period 10.000 -name sys_clk [get_ports CLK100MHZ]

# -----------------------------------------------------------------------
# Reset (active-low pushbutton CPU_RESETN)
# -----------------------------------------------------------------------
set_property PACKAGE_PIN C12 [get_ports CPU_RESETN]
set_property IOSTANDARD LVCMOS33 [get_ports CPU_RESETN]

# -----------------------------------------------------------------------
# LEDs  (16-bit)
# -----------------------------------------------------------------------
set_property PACKAGE_PIN H17 [get_ports {LED[0]}];  set_property IOSTANDARD LVCMOS33 [get_ports {LED[0]}]
set_property PACKAGE_PIN K15 [get_ports {LED[1]}];  set_property IOSTANDARD LVCMOS33 [get_ports {LED[1]}]
set_property PACKAGE_PIN J13 [get_ports {LED[2]}];  set_property IOSTANDARD LVCMOS33 [get_ports {LED[2]}]
set_property PACKAGE_PIN N14 [get_ports {LED[3]}];  set_property IOSTANDARD LVCMOS33 [get_ports {LED[3]}]
set_property PACKAGE_PIN R18 [get_ports {LED[4]}];  set_property IOSTANDARD LVCMOS33 [get_ports {LED[4]}]
set_property PACKAGE_PIN V17 [get_ports {LED[5]}];  set_property IOSTANDARD LVCMOS33 [get_ports {LED[5]}]
set_property PACKAGE_PIN U17 [get_ports {LED[6]}];  set_property IOSTANDARD LVCMOS33 [get_ports {LED[6]}]
set_property PACKAGE_PIN U16 [get_ports {LED[7]}];  set_property IOSTANDARD LVCMOS33 [get_ports {LED[7]}]
set_property PACKAGE_PIN V16 [get_ports {LED[8]}];  set_property IOSTANDARD LVCMOS33 [get_ports {LED[8]}]
set_property PACKAGE_PIN T15 [get_ports {LED[9]}];  set_property IOSTANDARD LVCMOS33 [get_ports {LED[9]}]
set_property PACKAGE_PIN U14 [get_ports {LED[10]}]; set_property IOSTANDARD LVCMOS33 [get_ports {LED[10]}]
set_property PACKAGE_PIN T16 [get_ports {LED[11]}]; set_property IOSTANDARD LVCMOS33 [get_ports {LED[11]}]
set_property PACKAGE_PIN V15 [get_ports {LED[12]}]; set_property IOSTANDARD LVCMOS33 [get_ports {LED[12]}]
set_property PACKAGE_PIN V14 [get_ports {LED[13]}]; set_property IOSTANDARD LVCMOS33 [get_ports {LED[13]}]
set_property PACKAGE_PIN V12 [get_ports {LED[14]}]; set_property IOSTANDARD LVCMOS33 [get_ports {LED[14]}]
set_property PACKAGE_PIN V11 [get_ports {LED[15]}]; set_property IOSTANDARD LVCMOS33 [get_ports {LED[15]}]

# -----------------------------------------------------------------------
# Switches  (only SW[0] and SW[1] used by dift_nexys_top)
# -----------------------------------------------------------------------
set_property PACKAGE_PIN J15 [get_ports {SW[0]}];   set_property IOSTANDARD LVCMOS33 [get_ports {SW[0]}]
set_property PACKAGE_PIN L16 [get_ports {SW[1]}];   set_property IOSTANDARD LVCMOS33 [get_ports {SW[1]}]

# -----------------------------------------------------------------------
# 7-Segment Display – cathode segments SEG[6:0]
# Nexys A7 segment pinout: CA=T10 CB=R10 CC=K16 CD=K13 CE=P15 CF=T11 CG=L18
# -----------------------------------------------------------------------
set_property PACKAGE_PIN T10 [get_ports {SEG[0]}]; set_property IOSTANDARD LVCMOS33 [get_ports {SEG[0]}]
set_property PACKAGE_PIN R10 [get_ports {SEG[1]}]; set_property IOSTANDARD LVCMOS33 [get_ports {SEG[1]}]
set_property PACKAGE_PIN K16 [get_ports {SEG[2]}]; set_property IOSTANDARD LVCMOS33 [get_ports {SEG[2]}]
set_property PACKAGE_PIN K13 [get_ports {SEG[3]}]; set_property IOSTANDARD LVCMOS33 [get_ports {SEG[3]}]
set_property PACKAGE_PIN P15 [get_ports {SEG[4]}]; set_property IOSTANDARD LVCMOS33 [get_ports {SEG[4]}]
set_property PACKAGE_PIN T11 [get_ports {SEG[5]}]; set_property IOSTANDARD LVCMOS33 [get_ports {SEG[5]}]
set_property PACKAGE_PIN L18 [get_ports {SEG[6]}]; set_property IOSTANDARD LVCMOS33 [get_ports {SEG[6]}]

# -----------------------------------------------------------------------
# 7-Segment Display – anode enables AN[7:0]  (active-low)
# Nexys A7 anode pinout: AN0=J17 AN1=J18 AN2=T9 AN3=J14
#                        AN4=P14 AN5=T14 AN6=K2 AN7=U13
# -----------------------------------------------------------------------
set_property PACKAGE_PIN J17 [get_ports {AN[0]}];  set_property IOSTANDARD LVCMOS33 [get_ports {AN[0]}]
set_property PACKAGE_PIN J18 [get_ports {AN[1]}];  set_property IOSTANDARD LVCMOS33 [get_ports {AN[1]}]
set_property PACKAGE_PIN T9  [get_ports {AN[2]}];  set_property IOSTANDARD LVCMOS33 [get_ports {AN[2]}]
set_property PACKAGE_PIN J14 [get_ports {AN[3]}];  set_property IOSTANDARD LVCMOS33 [get_ports {AN[3]}]
set_property PACKAGE_PIN P14 [get_ports {AN[4]}];  set_property IOSTANDARD LVCMOS33 [get_ports {AN[4]}]
set_property PACKAGE_PIN T14 [get_ports {AN[5]}];  set_property IOSTANDARD LVCMOS33 [get_ports {AN[5]}]
set_property PACKAGE_PIN K2  [get_ports {AN[6]}];  set_property IOSTANDARD LVCMOS33 [get_ports {AN[6]}]
set_property PACKAGE_PIN U13 [get_ports {AN[7]}];  set_property IOSTANDARD LVCMOS33 [get_ports {AN[7]}]

# -----------------------------------------------------------------------
# UART TX (tie-off in this design, but pin must be driven)
# -----------------------------------------------------------------------
set_property PACKAGE_PIN D4  [get_ports UART_TXD_IN]
set_property IOSTANDARD LVCMOS33 [get_ports UART_TXD_IN]

# -----------------------------------------------------------------------
# Bitstream / Config
# -----------------------------------------------------------------------
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 3.3             [current_design]
set_property CFGBVS VCCO                   [current_design]

# -----------------------------------------------------------------------
# Timing exceptions
# Input/output delays are relative to sys_clk.
# Switches and LEDs are not timing-critical; false-path them.
# -----------------------------------------------------------------------
set_false_path -from [get_ports {SW[*]}]
set_false_path -to   [get_ports {LED[*]}]
set_false_path -to   [get_ports {SEG[*]}]
set_false_path -to   [get_ports {AN[*]}]
set_false_path -to   [get_ports UART_TXD_IN]
set_false_path -from [get_ports CPU_RESETN]
