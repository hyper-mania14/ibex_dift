# ibex_dift
This project adds Dynamic Information Flow Tracking (DIFT) to the 3-stage Ibex core from lowRISC. DIFT attaches a 1-bit tag to data and control flow and enforces policies that prevent illegal writes or control transfers when tags indicate tainted data.

## What is DIFT?
Dynamic Information Flow Tracking tags data as it moves through the system. Tags propagate with computation and memory traffic. Policies then check whether tainted data is allowed to reach a sink (e.g., store address, control-flow target). If a policy is violated, the core raises a DIFT exception.

## High-level DIFT flow
- Tags exist in three places: register file (1-bit tag per register), data memory shadow RAM (1-bit tag per word), and PC tag tracking in fetch.
- Two CSRs control behavior:
	- TPR (Tag Propagation Register): selects tag propagation mode per instruction class.
	- TCR (Tag Control Register): enables check bits per instruction class.
- The Tag Management Unit (TMU) decodes the current instruction and TPR/TCR to produce:
	- propagation mode (AND/OR/CLEAR/OLD)
	- check enables for source, destination, and PC
- The EX stage computes the new tag and checks for violations.
- The LSU writes/reads tag bits in parallel with data and reports tag violations on load/store.
- The controller treats tag violations as exceptions and flushes the pipeline.

## Implementation details
- Tag propagation modes are defined in `ibex_pkg.sv` as `ALU_MODE_OLD`, `ALU_MODE_AND`, `ALU_MODE_OR`, `ALU_MODE_CLEAR`.
- TCR bit mapping and TPR field layout are defined in `ibex_pkg.sv`.
- `ibex_dift_tmu.sv` decodes instruction opcode/funct fields to choose check bits and propagation modes.
- `ibex_dift_logic.sv` applies propagation and raises ALU-stage taint violations.
- `ibex_dift_mem.sv` implements the 1-bit tag shadow memory (used in sim model; FPGA top uses a local tag RAM).
- PC tagging is tracked in IF stage and checked on tainted control flow.
- Exceptions are aggregated in the controller and exposed as `dift_exception_o`.

## Where DIFT is enabled
DIFT is guarded by the `DIFT` macro in the RTL. In this repo, it is defined in the testbench and also in [rtl/ibex_if_stage.sv](rtl/ibex_if_stage.sv). You can also define it globally in your tool flow (e.g., compile define) to enable DIFT across the design.

## Files modified/added for DIFT
Core RTL and pipeline integration:
- [rtl/ibex_core.sv](rtl/ibex_core.sv): top-level wiring, tag ports, exception aggregation.
- [rtl/ibex_if_stage.sv](rtl/ibex_if_stage.sv): PC tag tracking and branch target tag selection.
- [rtl/ibex_id_stage.sv](rtl/ibex_id_stage.sv): tag read/forward, TPR/TCR usage, operand tag selection.
- [rtl/ibex_ex_block.sv](rtl/ibex_ex_block.sv): ALU tag propagation and EX-stage taint checks.
- [rtl/ibex_load_store_unit.sv](rtl/ibex_load_store_unit.sv): tag memory read/write and load/store checks.
- [rtl/ibex_wb_stage.sv](rtl/ibex_wb_stage.sv): tag writeback and forwarding.
- [rtl/ibex_controller.sv](rtl/ibex_controller.sv): exception integration for DIFT violations.
- [rtl/ibex_cs_registers.sv](rtl/ibex_cs_registers.sv): TPR/TCR CSRs.
- [rtl/ibex_pkg.sv](rtl/ibex_pkg.sv): tag modes and policy bit definitions.

New DIFT modules:
- [rtl/ibex_dift_logic.sv](rtl/ibex_dift_logic.sv): tag propagation and ALU-stage checks.
- [rtl/ibex_dift_tmu.sv](rtl/ibex_dift_tmu.sv): TPR/TCR decode for checks and modes.
- [rtl/ibex_dift_mem.sv](rtl/ibex_dift_mem.sv): tag shadow memory model.
- [rtl/ibex_register_file_fpga_tag.sv](rtl/ibex_register_file_fpga_tag.sv): tag register file for FPGA.

FPGA wrapper and IO:
- [wrapper/dift_nexys_top.sv](wrapper/dift_nexys_top.sv): Nexys A7 top-level with tag RAM and exception LEDs.
- [wrapper/seven_seg_driver.sv](wrapper/seven_seg_driver.sv): exception counter display.

Tests and programs:
- [sim/ibex_core_tb.sv](sim/ibex_core_tb.sv): exhaustive DIFT testbench.
- [mem/normal_test.mem](mem/normal_test.mem): clean flow sanity test.
- [mem/attack_test.mem](mem/attack_test.mem): tainted pointer store (should raise exception).
- [mem/test_program.mem](mem/test_program.mem): program loaded by the Nexys top (currently same content as normal_test).

## Tests done (simulation)
The testbench in [sim/ibex_core_tb.sv](sim/ibex_core_tb.sv) runs an exhaustive suite that covers:
- TPR propagation modes for integer, logical, shift, comparison, and jump operations.
- Load propagation modes and store tag propagation to shadow memory.
- TCR checks for source/destination tags across integer/logical/shift/comparison, branch, and jump instructions.
- Load/store address and data checks (`LOADSTORE_CHECK_S`, `LOADSTORE_CHECK_D`, `LOADSTORE_CHECK_DA`, `LOADSTORE_CHECK_SA`).
- Execute-PC taint check for tainted control-flow.
- CSR access paths for TPR/TCR.
- M-extension (mul/div/rem) propagation and checks.

The testbench logs results to `dift_tb_exhaustive_results.log` and prints a pass/fail summary to the console.

## Synthesis results
Utilization (synth) and timing (routed) from Vivado reports:

- Target device/board: Nexys A7-100T (xc7a100tcsg324-1)
- Tool/version: Vivado v2025.2
- Clock period: 10.000 ns (100.000 MHz)
- Slack (WNS): -4.601 ns (setup, sys_clk)
- Total Negative Slack (TNS): -3857.581 ns
- LUTs: 5794 (Slice LUTs)
- FDREs: 2321
- Slice Registers: 3039
- IOBs (Bonded): 36
- BRAM: 2.5 tiles (2x RAMB36 + 1x RAMB18)
- DSP: 1 (DSP48E1)
