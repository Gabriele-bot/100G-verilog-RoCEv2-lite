foreach synchronizer_inst [get_cells -hier -filter {(ORIG_REF_NAME == sync_bit_array || REF_NAME == sync_bit_array)}] {
    puts "Inserting timing constraints for sync_bit_array instance $synchronizer_inst"

    # get clock periods
    set input_clk [get_clocks -of_objects [get_cells -quiet "$synchronizer_inst/data_in_reg_reg[*]"]]
    set output_clk [get_clocks -of_objects [get_cells -quiet "$synchronizer_inst/sync_reg_reg[*][*]"]]

    set input_clk_period [if {[llength $input_clk]} {get_property -min PERIOD $input_clk} {expr 1.0}]
    set output_clk_period [if {[llength $output_clk]} {get_property -min PERIOD $output_clk} {expr 1.0}]

    puts $input_clk_period
    puts $output_clk_period

    # data_bus synchronization
    set sync_ffs [get_cells -quiet -hier -regexp ".*/sync_reg_reg[*]" -filter "PARENT == $synchronizer_inst"]

    if {[llength $sync_ffs]} {
        set_property ASYNC_REG TRUE $sync_ffs
    }

    set_max_delay -from [get_cells "$synchronizer_inst/data_in_reg_reg[*]"] -to [get_cells "$synchronizer_inst/sync_reg_reg[0][*]"] -datapath_only $output_clk_period
    set_bus_skew  -from [get_cells "$synchronizer_inst/data_in_reg_reg[*]"] -to [get_cells "$synchronizer_inst/sync_reg_reg[0][*]"] $input_clk_period
}