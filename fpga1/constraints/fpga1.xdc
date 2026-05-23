# ==============================================================================
# fpga1.xdc  -  Basys3 FPGA1 Constraints  (FINAL)
#
# Ports in top_fpga1:
#   clk, rst_btn, pc_rx, pc_tx, fpga2_tx,
#   led[13:0], mx_din, mx_cs, mx_clk
# ==============================================================================

# ------------------------------------------------------------------------------
# Clock - 100 MHz onboard oscillator
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# ------------------------------------------------------------------------------
# Reset - BTNC (centre button, active HIGH on Basys3)
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports rst_btn]

# ------------------------------------------------------------------------------
# USB-UART Bridge  (PC1 <-> FPGA1)
# B18 = RXD from PC,  A18 = TXD to PC
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports pc_rx]
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports pc_tx]

# ------------------------------------------------------------------------------
# PMOD JA pin 1 = UART TX to FPGA2
# Physical: FPGA1 JA-pin1 -> jumper wire -> FPGA2 JA-pin1
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN J1  IOSTANDARD LVCMOS33 } [get_ports fpga2_tx]

# ------------------------------------------------------------------------------
# LEDs
# LD0-LD7  = data bits  d0-d7
# LD8-LD13 = parity bits P0-P5
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN V3  IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN W3  IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN U3  IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN P3  IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN N3  IOSTANDARD LVCMOS33 } [get_ports {led[13]}]

# ------------------------------------------------------------------------------
# PMOD JB -> MAX7219 8x8 LED Matrix
#
# JB pin1 (A14) = DIN  (data in)
# JB pin2 (A16) = CS   (chip select, active low)
# JB pin3 (B15) = CLK  (SPI clock)
#
# Physical wiring:
#   PMOD JB pin1 -> MAX7219 DIN
#   PMOD JB pin2 -> MAX7219 CS/LOAD
#   PMOD JB pin3 -> MAX7219 CLK
#   PMOD JB pin5 -> MAX7219 GND
#   PMOD JB pin6 -> MAX7219 VCC (use 5V from J15 if matrix is dim)
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 } [get_ports mx_din]
set_property -dict { PACKAGE_PIN A16 IOSTANDARD LVCMOS33 } [get_ports mx_cs]
set_property -dict { PACKAGE_PIN B15 IOSTANDARD LVCMOS33 } [get_ports mx_clk]

# ------------------------------------------------------------------------------
# Bitstream configuration
# ------------------------------------------------------------------------------
set_property CFGBVS        VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3  [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
