## =============================================================================
## arty_a7.xdc
## Xilinx Design Constraints — Digilent Arty A7-35T / A7-100T
## Target: rv32ima_cpu  (arty_a7_top entity)
##
## Timing budget: 10 ns period = 100 MHz
## Achievable fmax on Artix-7-1 (speed grade -1): ~85–95 MHz post-impl.
## Achievable fmax on Artix-7-2 (speed grade -2): ~100 MHz post-impl.
## =============================================================================

## ---------------------------------------------------------------------------
## Primary Clock — 100 MHz on-board oscillator (E3)
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk_i]
create_clock -period 10.000 -name sys_clk_100 -waveform {0.000 5.000} \
    [get_ports clk_i]

## ---------------------------------------------------------------------------
## Reset — BTN0 (active HIGH on board, inverted in RTL to give active-LOW)
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports btn_rst_i]

## ---------------------------------------------------------------------------
## LEDs LD4–LD7 (4 green LEDs on Arty)
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN H5  IOSTANDARD LVCMOS33} [get_ports {led_o[0]}]
set_property -dict {PACKAGE_PIN J5  IOSTANDARD LVCMOS33} [get_ports {led_o[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {led_o[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led_o[3]}]

## ---------------------------------------------------------------------------
## UART TX — PMOD JA pin 1 (D10)
## Connect to USB-UART bridge or serial adapter (115200-8N1)
## ---------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_tx_o]

## ---------------------------------------------------------------------------
## Timing Exceptions
## ---------------------------------------------------------------------------

## Multi-cycle path for BRAM read (2 cycles: accept + deliver)
set_multicycle_path 2 -setup -from [get_cells -hierarchical -filter {NAME =~ *irom*}] \
    -to [get_cells -hierarchical -filter {NAME =~ *im_rdata*}]
set_multicycle_path 1 -hold  -from [get_cells -hierarchical -filter {NAME =~ *irom*}] \
    -to [get_cells -hierarchical -filter {NAME =~ *im_rdata*}]

set_multicycle_path 2 -setup -from [get_cells -hierarchical -filter {NAME =~ *dram*}] \
    -to [get_cells -hierarchical -filter {NAME =~ *dm_rdata*}]
set_multicycle_path 1 -hold  -from [get_cells -hierarchical -filter {NAME =~ *dram*}] \
    -to [get_cells -hierarchical -filter {NAME =~ *dm_rdata*}]

## False path on async reset (synchronous reset used, but keep XDC clean)
# set_false_path -from [get_ports btn_rst_i]

## ---------------------------------------------------------------------------
## I/O Timing (relax output delays — LEDs and UART are not timing-critical)
## ---------------------------------------------------------------------------
set_output_delay -clock sys_clk_100 -max 4.0 [get_ports {led_o[*]}]
set_output_delay -clock sys_clk_100 -min 0.0 [get_ports {led_o[*]}]

set_output_delay -clock sys_clk_100 -max 4.0 [get_ports uart_tx_o]
set_output_delay -clock sys_clk_100 -min 0.0 [get_ports uart_tx_o]

set_input_delay  -clock sys_clk_100 -max 4.0 [get_ports btn_rst_i]
set_input_delay  -clock sys_clk_100 -min 0.0 [get_ports btn_rst_i]

## ---------------------------------------------------------------------------
## Physical / Placement
## ---------------------------------------------------------------------------

## Allow Vivado to use all available resources
set_property BITSTREAM.GENERAL.COMPRESS    TRUE   [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE   33     [current_design]
set_property CONFIG_VOLTAGE                3.3    [current_design]
set_property CFGBVS                        VCCO   [current_design]
