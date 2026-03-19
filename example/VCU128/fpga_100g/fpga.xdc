# General configuration
set_property CFGBVS GND                                [current_design]
set_property CONFIG_VOLTAGE 1.8                        [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true           [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN {DIV-1} [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES       [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 8           [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES        [current_design]
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable  [current_design]

# RLD3 100 MHz clk
set_property PACKAGE_PIN F35 [get_ports CLK_100MHZ_P]
set_property PACKAGE_PIN F36 [get_ports CLK_100MHZ_N]
set_property IOSTANDARD LVDS [get_ports CLK_100MHZ_P]
set_property IOSTANDARD LVDS [get_ports CLK_100MHZ_N]
create_clock -period 10.000 -name CLK_100MHZ_user [get_ports CLK_100MHZ_P]


# QDR4 100 MHz clk
set_property PACKAGE_PIN BJ4 [get_ports CLK1_100MHZ_P]
set_property PACKAGE_PIN BK3 [get_ports CLK1_100MHZ_N]
set_property IOSTANDARD LVDS [get_ports CLK1_100MHZ_P]
set_property IOSTANDARD LVDS [get_ports CLK1_100MHZ_N]
create_clock -period 10.000 -name CLK1_100MHZ_user [get_ports CLK1_100MHZ_P]


# HBM
# DDR4 100 MHz clk
set_property PACKAGE_PIN BH51 [get_ports HBM_clk_ref_p]
set_property PACKAGE_PIN BJ51 [get_ports HBM_clk_ref_n]
set_property IOSTANDARD LVDS [get_ports HBM_clk_ref_p]
set_property IOSTANDARD LVDS [get_ports HBM_clk_ref_n]
create_clock -period 10.000 -name HBM_clk_ref [get_ports HBM_clk_ref_p]


# LEDs
set_property -dict {LOC BH24 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[0]}]
set_property -dict {LOC BG24 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[1]}]
set_property -dict {LOC BG25 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[2]}]
set_property -dict {LOC BF25 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[3]}]
set_property -dict {LOC BF26 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[4]}]
set_property -dict {LOC BF27 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[5]}]
set_property -dict {LOC BG27 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[6]}]
set_property -dict {LOC BG28 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports {led[7]}]

set_false_path -to [get_ports {led[*]}]
set_output_delay 0 [get_ports {led[*]}]

# Reset button
set_property -dict {LOC BM29  IOSTANDARD LVCMOS12} [get_ports reset]

set_false_path -from [get_ports {reset}]
set_input_delay 0 [get_ports {reset}]


# QSFP28 Interfaces
set_property -dict {LOC G53  } [get_ports {qsfp1_rx_p[0]}] ;
set_property -dict {LOC G54  } [get_ports {qsfp1_rx_n[0]}] ;
set_property -dict {LOC G48  } [get_ports {qsfp1_tx_p[0]}] ;
set_property -dict {LOC G49  } [get_ports {qsfp1_tx_n[0]}] ;
set_property -dict {LOC F51  } [get_ports {qsfp1_rx_p[1]}] ;
set_property -dict {LOC F52  } [get_ports {qsfp1_rx_n[1]}] ;
set_property -dict {LOC E48  } [get_ports {qsfp1_tx_p[1]}] ;
set_property -dict {LOC E49  } [get_ports {qsfp1_tx_n[1]}] ;
set_property -dict {LOC E53  } [get_ports {qsfp1_rx_p[2]}] ;
set_property -dict {LOC E54  } [get_ports {qsfp1_rx_n[2]}] ;
set_property -dict {LOC C48  } [get_ports {qsfp1_tx_p[2]}] ;
set_property -dict {LOC C49  } [get_ports {qsfp1_tx_n[2]}] ;
set_property -dict {LOC D51  } [get_ports {qsfp1_rx_p[3]}] ;
set_property -dict {LOC D52  } [get_ports {qsfp1_rx_n[3]}] ;
set_property -dict {LOC A49  } [get_ports {qsfp1_tx_p[3]}] ;
set_property -dict {LOC A50  } [get_ports {qsfp1_tx_n[3]}] ;
set_property -dict {LOC P42  } [get_ports qsfp1_mgt_refclk_0_p] ;
set_property -dict {LOC P43  } [get_ports qsfp1_mgt_refclk_0_n] ;
set_property -dict {LOC BM24 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports qsfp1_modsell]
set_property -dict {LOC BN25 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports qsfp1_resetl]
set_property -dict {LOC BM25 IOSTANDARD LVCMOS18 PULLUP true} [get_ports qsfp1_modprsl]
set_property -dict {LOC BP24 IOSTANDARD LVCMOS18 PULLUP true} [get_ports qsfp1_intl]
set_property -dict {LOC BN24 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports qsfp1_lpmode]

# 156.25 MHz MGT reference clock
create_clock -period 6.400 -name qsfp1_mgt_refclk_0 [get_ports qsfp1_mgt_refclk_0_p]

set_false_path -to [get_ports {qsfp1_modsell qsfp1_resetl qsfp1_lpmode}]
set_output_delay 0 [get_ports {qsfp1_modsell qsfp1_resetl qsfp1_lpmode}]
set_false_path -from [get_ports {qsfp1_modprsl qsfp1_intl}]
set_input_delay 0 [get_ports {qsfp1_modprsl qsfp1_intl}]

