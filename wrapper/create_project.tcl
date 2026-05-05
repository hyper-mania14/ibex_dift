# create_project.tcl
# for DIFT-enabled Ibex on Nexys A7-100T (xc7a100tcsg324-1)

# -----------------------------------------------------------------------
# 0. Resolve paths relative to this script
# -----------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize "$script_dir/.."]

# -----------------------------------------------------------------------
# 1. Clean previous project (avoid cache issues)
# -----------------------------------------------------------------------
if {[file exists "$root_dir/vivado_proj"]} {
  file delete -force -- "$root_dir/vivado_proj"
}

# -----------------------------------------------------------------------
# 2. Create project
# -----------------------------------------------------------------------
create_project dift_ibex "$root_dir/vivado_proj" -part xc7a100tcsg324-1 -force

set_property simulator_language  Mixed        [current_project]
set_property target_language     Verilog [current_project]
set_property source_mgmt_mode    None   [current_project]
set_property XPM_LIBRARIES       {XPM_MEMORY} [current_project]

# -----------------------------------------------------------------------
# 3. Set DIFT define globally BEFORE adding any source files
# -----------------------------------------------------------------------
set_property verilog_define "DIFT=1" [current_fileset]

# -----------------------------------------------------------------------
# 4. Add RTL source files
# -----------------------------------------------------------------------
set rtl_files [list \
  "$root_dir/rtl/ibex_pkg.sv" \
  "$root_dir/rtl/ibex_alu.sv" \
  "$root_dir/rtl/ibex_branch_predict.sv" \
  "$root_dir/rtl/ibex_compressed_decoder.sv" \
  "$root_dir/rtl/ibex_controller.sv" \
  "$root_dir/rtl/ibex_core.sv" \
  "$root_dir/rtl/ibex_counter.sv" \
  "$root_dir/rtl/ibex_cs_registers.sv" \
  "$root_dir/rtl/ibex_csr.sv" \
  "$root_dir/rtl/ibex_decoder.sv" \
  "$root_dir/rtl/ibex_dift_logic.sv" \
  "$root_dir/rtl/ibex_dift_mem.sv" \
  "$root_dir/rtl/ibex_dift_tmu.sv" \
  "$root_dir/rtl/ibex_ex_block.sv" \
  "$root_dir/rtl/ibex_fetch_fifo.sv" \
  "$root_dir/rtl/ibex_id_stage.sv" \
  "$root_dir/rtl/ibex_if_stage.sv" \
  "$root_dir/rtl/ibex_load_store_unit.sv" \
  "$root_dir/rtl/ibex_multdiv_fast.sv" \
  "$root_dir/rtl/ibex_multdiv_slow.sv" \
  "$root_dir/rtl/ibex_pmp.sv" \
  "$root_dir/rtl/ibex_prefetch_buffer.sv" \
  "$root_dir/rtl/ibex_register_file_fpga.sv" \
  "$root_dir/rtl/ibex_register_file_fpga_tag.sv" \
  "$root_dir/rtl/ibex_sram.sv" \
  "$root_dir/rtl/ibex_wb_stage.sv" \
]
add_files -norecurse $rtl_files
proc enable_files {files} {
  foreach f $files {
    set fobj [get_files -quiet -all $f]
    if {$fobj ne ""} {
      set_property IS_ENABLED 1 $fobj
      set_property USED_IN {synthesis implementation simulation} $fobj
    } else {
      puts "WARNING: file not found in project: $f"
    }
  }
}
enable_files $rtl_files

# -----------------------------------------------------------------------
# 5. Add wrapper files
# -----------------------------------------------------------------------
set wrapper_files [list \
  "$root_dir/wrapper/dift_nexys_top.sv" \
  "$root_dir/wrapper/seven_seg_driver.sv" \
]
add_files -norecurse $wrapper_files
enable_files $wrapper_files

# -----------------------------------------------------------------------
# 6. Add Ibex primitive files
#    These come from the lowRISC Ibex repo (rtl/prim/).
# -----------------------------------------------------------------------
set prim_files [list \
  "$root_dir/rtl/prim/prim_assert.sv" \
  "$root_dir/rtl/prim/prim_assert_sec_cm.svh" \
  "$root_dir/rtl/prim/prim_assert_standard_macros.svh" \
  "$root_dir/rtl/prim/prim_buf.sv" \
  "$root_dir/rtl/prim/prim_flop.sv" \
  "$root_dir/rtl/prim/prim_clock_gating.sv" \
  "$root_dir/rtl/prim/prim_flop_macros.sv" \
  "$root_dir/rtl/prim/prim_mubi_pkg.sv" \

]
add_files -norecurse $prim_files
enable_files $prim_files

set all_src_files [get_files -of_objects [get_filesets sources_1]]
set_property IS_ENABLED 1 $all_src_files
set_property USED_IN {synthesis implementation simulation} $all_src_files

# -----------------------------------------------------------------------
# 7. Mark .svh files as headers
# -----------------------------------------------------------------------
foreach f [get_files -filter {FILE_TYPE == SystemVerilog}] {
  if {[string match "*.svh" $f]} {
    set_property FILE_TYPE {Verilog Header} [get_files $f]
  }
}

# -----------------------------------------------------------------------
# 8. Set include path 
# -----------------------------------------------------------------------
set_property include_dirs [list \
  "$root_dir/rtl" \
  "$root_dir/rtl/prim" \
  "$root_dir/wrapper" \
] [current_fileset]
# -----------------------------------------------------------------------
# 9. Add memory initialisation file and pick test code
#      cp mem/attack_test.mem  mem/test_program.mem   (to test DIFT exception)
#      cp mem/normal_test.mem  mem/test_program.mem   (to test clean execution)
# -----------------------------------------------------------------------
add_files -norecurse "$root_dir/mem/test_program.mem"

# -----------------------------------------------------------------------
# 10. Add constraints
# -----------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse "$root_dir/constraints/nexys_a7.xdc"


# -----------------------------------------------------------------------
# 11. Set top module
# -----------------------------------------------------------------------
set_property top dift_nexys_top [current_fileset]
update_compile_order -fileset sources_1

# -----------------------------------------------------------------------
# 12. Synthesis settings
#     - Flatten hierarchy to "none" so signal names remain readable in reports
#     - Use default strategy for Artix-7
# -----------------------------------------------------------------------
set_property strategy              "Vivado Synthesis Defaults" [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none    [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS true [get_runs synth_1]

# Bypass the pin requirement checks
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]


# -----------------------------------------------------------------------
# 13. Run synthesis
# -----------------------------------------------------------------------
puts "INFO: Launching synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
  error "ERROR: Synthesis failed. Check vivado_proj/dift_ibex.runs/synth_1/*.log"
}
puts "INFO: Synthesis complete."

# -----------------------------------------------------------------------
# 14. Implementation settings
#     and add timing-driven placement
# -----------------------------------------------------------------------
set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]

# -----------------------------------------------------------------------
# 15. Run implementation through bitstream generation
# -----------------------------------------------------------------------
puts "INFO: Launching implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
  error "ERROR: Implementation failed. Check vivado_proj/dift_ibex.runs/impl_1/*.log"
}
puts "INFO: Implementation complete."

# -----------------------------------------------------------------------
# 16. Open implemented design and generate reports
# -----------------------------------------------------------------------
open_run impl_1 -name impl_1

report_timing_summary \
  -max_paths 10 \
  -report_unconstrained \
  -file "$root_dir/vivado_proj/timing_report.txt"

report_utilization \
  -file "$root_dir/vivado_proj/util_report.txt"

report_drc \
  -file "$root_dir/vivado_proj/drc_report.txt"

puts "INFO: Reports written to $root_dir/vivado_proj/"
puts "INFO: Bitstream: $root_dir/vivado_proj/dift_ibex.runs/impl_1/dift_nexys_top.bit"
puts ""
puts "DONE. Next step: program the Nexys A7 using Vivado Hardware Manager."
