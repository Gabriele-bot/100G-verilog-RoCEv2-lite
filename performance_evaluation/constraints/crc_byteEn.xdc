set src_clk [get_clocks -of [get_ports clk]]
#the top level ports are actually fake ports to prevent vivado from optimizing out the entire design
#the real "ports" are the registers instantiated in the top level design, they emulates the logic that connect with the crc module
#the top level ports don't really get placed at anywhere, hence there is no route from or to these ports
#it makes no sense to care about the timing related to these fake top level ports
#especially, vivado can't properly calculate the clock skew related to these ports (again, because they are not placed)
#therefore, we set false path for all the fake top level ports
set_false_path -from [get_ports rst]
set_false_path -from [get_ports din[*]]
set_false_path -from [get_ports dlast]
set_false_path -from [get_ports byteEn[*]]
set_false_path -from [get_ports flitEn]
set_false_path -to [get_ports crc_out[*]]
set_false_path -to [get_ports crc_out_vld]

#restrict the place and route area for the crc module
create_pblock crc_region
resize_pblock crc_region -add {CLOCKREGION_X1Y5:CLOCKREGION_X3Y5}
add_cells_to_pblock crc_region [get_cells u_crc_gen]
set_property SNAPPING_MODE ON [get_pblocks crc_region]
#assign a real clock buffer source to clk, so that clock skew can be realistically calculated
set_property HD.CLK_SRC BUFGCE_X0Y133 [get_ports clk]
