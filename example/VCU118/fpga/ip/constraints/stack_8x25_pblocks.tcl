create_pblock pblock_stack0
add_cells_to_pblock [get_pblocks pblock_stack0] [get_cells -quiet [list {core_inst/genblk2[0].RoCE_minimal_stack_64_instance} {core_inst/genblk2[0].eth_axis_rx_inst} {core_inst/genblk2[0].eth_axis_tx_inst} {core_inst/genblk2[0].udp_complete_inst}]]
resize_pblock [get_pblocks pblock_stack0] -add {SLICE_X31Y660:SLICE_X141Y689}
create_pblock pblock_stack1
add_cells_to_pblock [get_pblocks pblock_stack1] [get_cells -quiet [list {core_inst/genblk2[1].RoCE_minimal_stack_64_instance} {core_inst/genblk2[1].eth_axis_rx_inst} {core_inst/genblk2[1].eth_axis_tx_inst} {core_inst/genblk2[1].udp_complete_inst}]]
resize_pblock [get_pblocks pblock_stack1] -add {SLICE_X31Y690:SLICE_X141Y719}
create_pblock pblock_stack2
add_cells_to_pblock [get_pblocks pblock_stack2] [get_cells -quiet [list {core_inst/genblk2[2].RoCE_minimal_stack_64_instance} {core_inst/genblk2[2].eth_axis_rx_inst} {core_inst/genblk2[2].eth_axis_tx_inst} {core_inst/genblk2[2].udp_complete_inst}]]
resize_pblock [get_pblocks pblock_stack2] -add {SLICE_X31Y720:SLICE_X141Y749}
create_pblock pblock_stack3
add_cells_to_pblock [get_pblocks pblock_stack3] [get_cells -quiet [list {core_inst/genblk2[3].RoCE_minimal_stack_64_instance} {core_inst/genblk2[3].eth_axis_rx_inst} {core_inst/genblk2[3].eth_axis_tx_inst} {core_inst/genblk2[3].udp_complete_inst}]]
resize_pblock [get_pblocks pblock_stack3] -add {SLICE_X31Y750:SLICE_X141Y779}
create_pblock pblock_stack4
add_cells_to_pblock [get_pblocks pblock_stack4] [get_cells -quiet [list {core_inst/genblk3[4].RoCE_minimal_stack_64_instance} {core_inst/genblk3[4].eth_axis_rx_inst} {core_inst/genblk3[4].eth_axis_tx_inst} {core_inst/genblk3[4].udp_complete_inst}]]
resize_pblock [get_pblocks pblock_stack4] -add {SLICE_X31Y780:SLICE_X141Y809}
create_pblock pblock_stack5
add_cells_to_pblock [get_pblocks pblock_stack5] [get_cells -quiet [list {core_inst/genblk3[5].RoCE_minimal_stack_64_instance} {core_inst/genblk3[5].eth_axis_rx_inst} {core_inst/genblk3[5].eth_axis_tx_inst} {core_inst/genblk3[5].udp_complete_inst}]]
resize_pblock [get_pblocks pblock_stack5] -add {SLICE_X31Y810:SLICE_X141Y839}
create_pblock pblock_stack6
add_cells_to_pblock [get_pblocks pblock_stack6] [get_cells -quiet [list {core_inst/genblk3[6].RoCE_minimal_stack_64_instance} {core_inst/genblk3[6].eth_axis_rx_inst} {core_inst/genblk3[6].eth_axis_tx_inst} {core_inst/genblk3[6].udp_complete_inst}]]
resize_pblock [get_pblocks pblock_stack6] -add {SLICE_X31Y840:SLICE_X141Y869}
create_pblock pblock_stack7
add_cells_to_pblock [get_pblocks pblock_stack7] [get_cells -quiet [list {core_inst/genblk3[7].RoCE_minimal_stack_64_instance} {core_inst/genblk3[7].eth_axis_rx_inst} {core_inst/genblk3[7].eth_axis_tx_inst} {core_inst/genblk3[7].udp_complete_inst}]]
resize_pblock [get_pblocks pblock_stack7] -add {SLICE_X31Y870:SLICE_X141Y899}

create_pblock pblock_MACs
add_cells_to_pblock [get_pblocks pblock_MACs] [get_cells -hierarchical -filter {NAME =~ *eth_mac_10g*}]
resize_pblock [get_pblocks pblock_MACs] -add {SLICE_X142Y600:SLICE_X168Y899}
