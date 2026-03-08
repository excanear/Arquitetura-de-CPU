## Arty A7-35T — EduRISC-32  Constraints
## Target: Digilent Arty A7-35T (XC7A35TICSG324-1L)
## Clock: 100 MHz on-board oscillator  (E3 → MRCC)

# ============================================================
# Clock
# ============================================================
set_property -dict { PACKAGE_PIN E3   IOSTANDARD LVCMOS33 } [get_ports { sys_clk }]
create_clock -add -name sys_clk_pin -period 10.00 \
             -waveform {0 5} [get_ports { sys_clk }]

# ============================================================
# Reset (BTN0 — active HIGH)
# ============================================================
set_property -dict { PACKAGE_PIN D9   IOSTANDARD LVCMOS33 } [get_ports { sys_rst }]

# ============================================================
# LEDs — mostram o nibble baixo de R0 após halt
# ============================================================
#  LD0 → R0[0]   LD1 → R0[1]   LD2 → R0[2]   LD3 → R0[3]
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]

# ============================================================
# Timing constraints adicionais
# ============================================================
set_property CFGBVS         VCCO      [current_design]
set_property CONFIG_VOLTAGE 3.3       [current_design]
