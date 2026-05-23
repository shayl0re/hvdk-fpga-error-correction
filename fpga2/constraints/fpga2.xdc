## ============================================================================
## fpga2.xdc  -  Basys3 FPGA2 Constraints
## Pin names verified against official Digilent Basys-3-Master.xdc
## Every port in top_fpga2 is constrained here.
##
## top_fpga2 ports:
##   clk, rst_btn, fpga1_rx, pc_tx, led[13:0]
## ============================================================================

## --- Clock 100 MHz ---
set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## --- Reset: BTNC (active HIGH on Basys3) ---
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports rst_btn]

## --- PMOD JA pin 1 (J1) = UART RX from FPGA1 ---
## Physical: FPGA2 JA-pin1 <- jumper wire <- FPGA1 JA-pin1
set_property -dict { PACKAGE_PIN J1  IOSTANDARD LVCMOS33 } [get_ports fpga1_rx]

## --- USB-UART Bridge TX to PC2 ---
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports pc_tx]

## --- LEDs LD0-LD7  (data bits) ---
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {led[7]}]

## --- LEDs LD8-LD13  (parity bits P0-P5) ---
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN V3  IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN W3  IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN U3  IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN P3  IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN N3  IOSTANDARD LVCMOS33 } [get_ports {led[13]}]

## --- Config ---
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
