set PART_NUM [lindex $argv 0]
set DWIDTH [lindex $argv 1]
set CRC_WIDTH [lindex $argv 2]
set PIPE_LVL [lindex $argv 3]
set CRC_POLY [lindex $argv 4]
set INIT [lindex $argv 5]
set XOR_OUT [lindex $argv 6]
set REFIN [lindex $argv 7]
set REFOUT [lindex $argv 8]
set BYTEEN [lindex $argv 9]
set PKT_LIMIT [lindex $argv 10]
set BYTE_BITS [lindex $argv 11]

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file dirname [file dirname [file normalize [info script]]]]
set work_dir "${root_dir}/workdir"

if {$BYTEEN} {
    set project_name "tbps_crc_byteEn_implementation"
    create_project $project_name ${work_dir}/${project_name} -part $PART_NUM -force
    add_files -fileset sources_1 -norecurse [list "${root_dir}/hdl/crc_byteEn_top.sv" \
                            "${root_dir}/hdl/xoshiro128ss_simple.sv" \
                            "${root_dir}/hdl/xoshiro32pp_simple.sv" \
                            "${root_dir}/hdl/config.svh" \
                            "${root_dir}/../core_src/crc_byteEn.sv" \
                            "${root_dir}/../core_src/crc.svh"
    ]
    add_files -fileset constrs_1 "${root_dir}/board_clk_source.xdc"
    set top_rtl "crc_byteEn_top"
} else {
    set project_name "tbps_crc_implementation"
    create_project $project_name ${work_dir}/${project_name} -part $PART_NUM -force
    add_files -fileset sources_1 -norecurse [list "${root_dir}/hdl/crc_top.sv" \
                            "${root_dir}/hdl/xoshiro128ss_simple.sv" \
                            "${root_dir}/hdl/xoshiro32pp_simple.sv" \
                            "${root_dir}/hdl/config.svh" \
                            "${root_dir}/../core_src/crc.sv" \
                            "${root_dir}/../core_src/crc.svh"
    ]
    add_files -fileset constrs_1 "${root_dir}/board_clk_source.xdc"
    set top_rtl "crc_top"
}

set_property top $top_rtl [get_filesets sources_1]

create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_0
set_property -dict [list CONFIG.C_PROBE_OUT0_WIDTH {1} CONFIG.C_NUM_PROBE_OUT {1} CONFIG.C_NUM_PROBE_IN {0} CONFIG.C_EN_PROBE_IN_ACTIVITY {0}] [get_ips vio_0]
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_0
if {$BYTEEN} {
    set_property -dict [list CONFIG.C_PROBE6_WIDTH {32} CONFIG.C_PROBE3_WIDTH {64} CONFIG.C_PROBE2_WIDTH {512} CONFIG.C_NUM_OF_PROBES {8}] [get_ips ila_0]
} else {
    set_property -dict [list CONFIG.C_PROBE5_WIDTH {32} CONFIG.C_PROBE2_WIDTH {512} CONFIG.C_NUM_OF_PROBES {7}] [get_ips ila_0]
}

reset_run synth_1
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value "-verilog_define DWIDTH=${DWIDTH} -verilog_define CRC_WIDTH=${CRC_WIDTH} -verilog_define PIPE_LVL=${PIPE_LVL} -verilog_define CRC_POLY=${CRC_POLY} -verilog_define INIT=${INIT} -verilog_define XOR_OUT=${XOR_OUT} -verilog_define REFIN=1'b${REFIN} -verilog_define REFOUT=1'b${REFOUT} -verilog_define PKT_LIMIT=${PKT_LIMIT} -verilog_define BYTE_BITS=${BYTE_BITS}" -objects [get_runs synth_1]

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
       error "ERROR: synthesis failed"
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
       error "ERROR: implementation failed"
}
put "bitstream has been generated, you can find the bitstream ($top_rtl.bit) and the debug probe file ($top_rtl.ltx) under ${work_dir}/outputs/"
exit
