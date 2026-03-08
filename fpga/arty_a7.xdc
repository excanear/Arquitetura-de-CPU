## ============================================================================
## arty_a7.xdc  —  Constraints de pinos e timing para Arty A7-35T
## EduRISC-32v2 FPGA Top (fpga_top)
## ============================================================================

# ---------------------------------------------------------------------------
# Clock principal (100 MHz)
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN E3   IOSTANDARD LVCMOS33 } [get_ports clk100]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk100]

# Clock gerado internamente (25 MHz) — definir para análise de timing
create_generated_clock -name cpu_clk \
    -source [get_ports clk100]       \
    -divide_by 4                     \
    [get_nets cpu_clk]

# ---------------------------------------------------------------------------
# Botão de reset (BTN0)
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN C2   IOSTANDARD LVCMOS33 } [get_ports rst_btn]

# ---------------------------------------------------------------------------
# LEDs LD0–LD3
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN H5   IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN J5   IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN T9   IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN T10  IOSTANDARD LVCMOS33 } [get_ports {led[3]}]

# ---------------------------------------------------------------------------
# UART (USB-UART via FT2232HQ)
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D10  IOSTANDARD LVCMOS33 } [get_ports uart_tx]
set_property -dict { PACKAGE_PIN A9   IOSTANDARD LVCMOS33 } [get_ports uart_rx]

# ---------------------------------------------------------------------------
# Configuração de bitstream
# ---------------------------------------------------------------------------
set_property CFGBVS VCCO          [current_design]
set_property CONFIG_VOLTAGE 3.3   [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
