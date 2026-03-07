## =============================================================================
## quartus.sdc  —  Synopsys Design Constraints for Quartus / Cyclone IV
## Target: DE0-Nano 50 MHz oscillator → 100 MHz via PLL
## =============================================================================

## Primary input clock — 50 MHz from on-board oscillator
create_clock -period 20.000 -name clk_in [get_ports clk_i]

## Derive PLL clocks automatically (100 MHz internal)
derive_pll_clocks

## Constrain clock uncertainty
derive_clock_uncertainty

## Relax async inputs (reset, no timing requirement)
set_false_path -from [get_ports btn_rst_i]

## Relax output ports (LEDs, UART — no setup/hold requirement on PCB)
set_output_delay -clock clk_in -max  4.0 [get_ports {led_o[*]}]
set_output_delay -clock clk_in -min  0.0 [get_ports {led_o[*]}]
set_output_delay -clock clk_in -max  4.0 [get_ports uart_tx_o]
set_output_delay -clock clk_in -min  0.0 [get_ports uart_tx_o]
