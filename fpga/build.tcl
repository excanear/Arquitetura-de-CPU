## ============================================================================
## build.tcl  —  Script Vivado para EduRISC-32v2 (Arty A7-35T)
##
## Uso:
##   vivado -mode batch -source fpga/build.tcl
##
## Gera: vivado/eduriscv32.bit (bitstream)
## ============================================================================

set project_name   "eduriscv32"
set project_dir    "./vivado"
set part           "xc7a35ticsg324-1L"
set top_module     "fpga_top"

# ---------------------------------------------------------------------------
# 1. Criar projeto
# ---------------------------------------------------------------------------
create_project $project_name $project_dir -part $part -force

# ---------------------------------------------------------------------------
# 2. Adicionar fontes RTL
# ---------------------------------------------------------------------------
set rtl_files [concat \
    [glob -nocomplain rtl_v/*.v]         \
    [glob -nocomplain rtl_v/*.vh]        \
    [glob -nocomplain rtl_v/cache/*.v]   \
    [glob -nocomplain rtl_v/mmu/*.v]     \
    [glob -nocomplain rtl_v/execute/*.v] \
    [glob -nocomplain rtl_v/interrupts/*.v] \
    [glob -nocomplain fpga/top.v]        \
]

add_files -norecurse $rtl_files
set_property file_type SystemVerilog [get_files *.vh]

# ---------------------------------------------------------------------------
# 3. Adicionar constraints XDC (pinos e timing)
# ---------------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse fpga/arty_a7.xdc

# ---------------------------------------------------------------------------
# 4. Definir top-level
# ---------------------------------------------------------------------------
set_property top $top_module [current_fileset]

# ---------------------------------------------------------------------------
# 5. Síntese
# ---------------------------------------------------------------------------
synth_design -top $top_module -part $part
report_utilization  -file $project_dir/utilization_synth.rpt
report_timing_summary -file $project_dir/timing_synth.rpt

# ---------------------------------------------------------------------------
# 6. Implementação
# ---------------------------------------------------------------------------
opt_design
place_design
route_design

report_utilization  -file $project_dir/utilization_impl.rpt
report_timing_summary -max_paths 10 -file $project_dir/timing_impl.rpt

# ---------------------------------------------------------------------------
# 7. Verificar timing (falhar se violations > 0)
# ---------------------------------------------------------------------------
set wns [get_property STATS.WNS [get_runs impl_1]]
if { $wns < 0 } {
    puts "ERRO: Timing não fechado! WNS = $wns ns"
    exit 1
}

# ---------------------------------------------------------------------------
# 8. Gerar bitstream
# ---------------------------------------------------------------------------
write_bitstream -force $project_dir/${project_name}.bit
puts "Bitstream gerado: $project_dir/${project_name}.bit"
