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
set N_MESSAGE [lindex $argv 10]
set MESSAGE_LEN_MIN [lindex $argv 11]
set MESSAGE_LEN_MAX [lindex $argv 12]
set flitEn_ratio [lindex $argv 13]

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file dirname [file dirname [file normalize [info script]]]]
set work_dir "${root_dir}/workdir"

if {$BYTEEN} {
    create_project tbps_crc_byteEn_simulation ${work_dir}/tbps_crc_byteEn_simulation -part $PART_NUM -force
    add_files -fileset sim_1 -norecurse [list "${root_dir}/hdl/crc_byteEn_tb.sv" \
                            "${root_dir}/hdl/crc_byteEn_top.sv" \
                            "${root_dir}/hdl/config.svh" \
                            "${root_dir}/../core_src/crc_byteEn.sv" \
                            "${root_dir}/../core_src/crc.svh"
    ]
    set top_rtl "crc_byteEn_tb"
} else {
    create_project tbps_crc_simulation ${work_dir}/tbps_crc_simulation -part $PART_NUM -force
    add_files -fileset sim_1 -norecurse [list "${root_dir}/hdl/crc_tb.sv" \
                            "${root_dir}/hdl/crc_top.sv" \
                            "${root_dir}/hdl/config.svh" \
                            "${root_dir}/../core_src/crc.sv" \
                            "${root_dir}/../core_src/crc.svh"
    ]
    set top_rtl "crc_tb"
}

set_property top $top_rtl [get_filesets sim_1]
set_property -name {xsim.simulate.log_all_signals} -value {true} -objects [get_filesets sim_1]
#had to add the dummy macro to prevent vivado from failing, this is dummy!
set_property -name {xsim.compile.xvlog.more_options} -value "-d SIM -d DWIDTH=${DWIDTH} -d CRC_WIDTH=${CRC_WIDTH} -d PIPE_LVL=${PIPE_LVL} -d CRC_POLY=\"${CRC_POLY}\" -d INIT=\"${INIT}\" -d XOR_OUT=\"${XOR_OUT}\" -d REFIN=\"1'b${REFIN}\" -d REFOUT=\"1'b${REFOUT}\" -d N_MESSAGE=${N_MESSAGE} -d MESSAGE_LEN_MIN=${MESSAGE_LEN_MIN} -d MESSAGE_LEN_MAX=${MESSAGE_LEN_MAX} -d flitEn_ratio=${flitEn_ratio} -d dummy=\"'\"" -objects [get_filesets sim_1] 

launch_simulation
run all
put "type <start_gui> to see the waveform or type <exit> to close vivado"
