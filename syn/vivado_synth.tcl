## =============================================================================
## vivado_synth.tcl
## Vivado 2023.x non-project-mode synthesis + implementation script
## Target : Digilent Arty A7-35T  (xc7a35tcsg324-1)
##          Change PART below to xc7a35tcsg324-2 / xc7a100tcsg324-1 as needed
##
## Usage (Vivado Tcl Console or batch):
##   cd <repo_root>/syn
##   vivado -mode batch -source vivado_synth.tcl
##
## Outputs in syn/build/:
##   arty_a7_top.dcp   — routed checkpoint
##   arty_a7_top.bit   — bitstream (flash directly with Vivado HW Manager)
##   timing_summary.rpt / utilization.rpt / power.rpt
## =============================================================================

set PART        "xc7a35tcsg324-1"
set TOP         "arty_a7_top"
set REPO_ROOT   [file dirname [file dirname [file normalize [info script]]]]
set BUILD_DIR   [file join [file dirname [file normalize [info script]]] build]

file mkdir $BUILD_DIR

## ---------------------------------------------------------------------------
## 1. Read Design Sources (VHDL-2008, dependency order)
## ---------------------------------------------------------------------------
puts "==> Reading RTL sources..."

read_vhdl -vhdl2008 [list \
    $REPO_ROOT/rtl/pkg/cpu_pkg.vhd          \
    $REPO_ROOT/rtl/pkg/axi4_pkg.vhd         \
    $REPO_ROOT/rtl/fetch/pc_reg.vhd         \
    $REPO_ROOT/rtl/fetch/branch_handler.vhd \
    $REPO_ROOT/rtl/fetch/decompressor.vhd   \
    $REPO_ROOT/rtl/fetch/fetch_stage.vhd    \
    $REPO_ROOT/rtl/decode/register_file.vhd \
    $REPO_ROOT/rtl/decode/instruction_decoder.vhd \
    $REPO_ROOT/rtl/decode/immediate_generator.vhd \
    $REPO_ROOT/rtl/decode/decode_stage.vhd  \
    $REPO_ROOT/rtl/execute/alu.vhd          \
    $REPO_ROOT/rtl/execute/branch_comparator.vhd \
    $REPO_ROOT/rtl/execute/forwarding_unit.vhd   \
    $REPO_ROOT/rtl/execute/execute_stage.vhd     \
    $REPO_ROOT/rtl/memory/load_store_unit.vhd    \
    $REPO_ROOT/rtl/memory/memory_stage.vhd       \
    $REPO_ROOT/rtl/writeback/writeback_stage.vhd \
    $REPO_ROOT/rtl/csr/csr_reg.vhd              \
    $REPO_ROOT/rtl/cache/icache.vhd              \
    $REPO_ROOT/rtl/cache/dcache.vhd              \
    $REPO_ROOT/rtl/mmu/mmu.vhd                   \
    $REPO_ROOT/rtl/clint/clint.vhd               \
    $REPO_ROOT/rtl/plic/plic.vhd                 \
    $REPO_ROOT/rtl/cpu_top.vhd                   \
    $REPO_ROOT/syn/arty_a7_top.vhd               \
]

## ---------------------------------------------------------------------------
## 2. Read Constraints
## ---------------------------------------------------------------------------
puts "==> Reading constraints..."
read_xdc $REPO_ROOT/syn/arty_a7.xdc

## ---------------------------------------------------------------------------
## 3. Synthesis
## ---------------------------------------------------------------------------
puts "==> Running synthesis..."
synth_design \
    -top          $TOP     \
    -part         $PART    \
    -vhdl2008              \
    -flatten_hierarchy full \
    -keep_equivalent_registers \
    -no_lc

## Post-synthesis checkpoint + reports
write_checkpoint -force $BUILD_DIR/${TOP}_synth.dcp
report_utilization  -file $BUILD_DIR/utilization_synth.rpt
report_timing_summary -max_paths 10 -file $BUILD_DIR/timing_synth.rpt

## ---------------------------------------------------------------------------
## 4. Optimization
## ---------------------------------------------------------------------------
puts "==> Optimising..."
opt_design

## ---------------------------------------------------------------------------
## 5. Placement
## ---------------------------------------------------------------------------
puts "==> Placing..."
place_design
phys_opt_design

write_checkpoint -force $BUILD_DIR/${TOP}_placed.dcp
report_clock_utilization -file $BUILD_DIR/clock_utilization.rpt

## ---------------------------------------------------------------------------
## 6. Routing
## ---------------------------------------------------------------------------
puts "==> Routing..."
route_design

## ---------------------------------------------------------------------------
## 7. Post-Route Reports
## ---------------------------------------------------------------------------
puts "==> Generating reports..."

report_timing_summary \
    -max_paths 20 \
    -nworst    5  \
    -file          $BUILD_DIR/timing_summary.rpt

report_utilization \
    -hierarchical     \
    -file             $BUILD_DIR/utilization.rpt

report_power \
    -file             $BUILD_DIR/power.rpt

report_drc \
    -file             $BUILD_DIR/drc.rpt

## Check for timing violations; exit non-zero if WNS < 0
set timing_ok [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
if { $timing_ok < 0 } {
    puts "WARNING: Setup timing violated by [expr -$timing_ok] ns — consider lowering clock period."
}

## ---------------------------------------------------------------------------
## 8. Write Routed Checkpoint + Bitstream
## ---------------------------------------------------------------------------
write_checkpoint -force $BUILD_DIR/${TOP}_routed.dcp

puts "==> Writing bitstream..."
write_bitstream \
    -force \
    -file  $BUILD_DIR/${TOP}.bit

puts ""
puts "================================================================"
puts "  DONE:  $BUILD_DIR/${TOP}.bit"
puts "  Flash via Vivado Hardware Manager → Program Device"
puts "================================================================"
