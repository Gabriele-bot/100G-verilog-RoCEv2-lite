#modify the period, IOSTANDARD and PACKAGE_PIN to match with your board
create_clock -period 3.333 [get_ports clk_p]
set_property IOSTANDARD LVDS [get_ports clk_p]
set_property IOSTANDARD LVDS [get_ports clk_n]
set_property PACKAGE_PIN AW20 [get_ports clk_p]
set_property PACKAGE_PIN AW19 [get_ports clk_n]
