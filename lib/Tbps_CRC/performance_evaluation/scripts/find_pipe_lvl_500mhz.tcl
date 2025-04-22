set part_num [lindex $argv 0]
set byteEn [lindex $argv 1]

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file dirname [file dirname [file normalize [info script]]]]
set work_dir "${root_dir}/workdir"
set freq_xdc "${root_dir}/constraints/freq.xdc"

set result_dir ${root_dir}/outputs/pipe_lvl_results
set log_dir ${result_dir}/logs
set dcp_dir ${result_dir}/dcps

set freq_xdc_f [open "$root_dir/constraints/freq_pipe.xdc" w]
puts $freq_xdc_f "create_clock -period 2.000 \[get_ports clk\]"
close $freq_xdc_f

if {$byteEn} {
    set result_csv $result_dir/result_byteEn.csv
} else {
    set result_csv $result_dir/result.csv
}
set result_f [open $result_csv w]
puts $result_f "name,polynomial,bus width,pipeline levels,throughput,latency,LUTs,FFs"
close $result_f

if {$byteEn} {
    set file_prefix "byteEn_"
    set top_rtl "crc_byteEn_top"
} else {
    set file_prefix ""
    set top_rtl "crc_top"
}

proc timeout_warning {} {
    puts "routing timeout, skipping"
}

foreach name {"CRC5-USB" "CRC16-IBM" "CRC32-Ethernet" "CRC64-ECMA"} poly {"5'h05" "16'h8005" "32'h04C11DB7" "64'h42F0E1EBA9EA3693"} crc_width {5 16 32 64} init_hex {"5'b0" "16'b0" "32'hffffffff" "64'b0"} xorout {"5'b0" "16'b0" "32'hffffffff" "64'b0"} refin {"1'b0" "1'b0" "1'b1" "1'b0"} refout {"1'b0" "1'b0" "1'b1" "1'b0"} {
    foreach bus_width {64 512 2048 8192} pipe_lvl_start {0 0 1 2} {
        set pipe_lvl $pipe_lvl_start
        puts "run poly: $name, bus width: $bus_width"
        set slack_met 0
        set init 1
        while {1} {
            if {$init != 1} {
                close_project
            } else {
                set init 0
            }
            puts "try pipe level: $pipe_lvl"
            create_project -in_memory -part $part_num
            if {$byteEn} {
                read_verilog $root_dir/../core_src/crc_byteEn.sv
                read_verilog $root_dir/hdl/crc_byteEn_top.sv
            } else {
                read_verilog $root_dir/../core_src/crc.sv
                read_verilog $root_dir/hdl/crc_top.sv
            }
            read_xdc $root_dir/constraints/freq.xdc
            if {$byteEn} {
                read_xdc $root_dir/constraints/crc_byteEn.xdc
            } else {
                read_xdc $root_dir/constraints/crc.xdc
            }

            synth_design -mode out_of_context -top $top_rtl -part $part_num \
                                      -verilog_define DWIDTH=$bus_width \
                                      -verilog_define CRC_WIDTH=$crc_width \
                                      -verilog_define PIPE_LVL=$pipe_lvl \
                                      -verilog_define CRC_POLY=$poly \
                                      -verilog_define INIT=$init_hex \
                                      -verilog_define XOR_OUT=$xorout \
                                      -verilog_define REFIN=$refin \
                                      -verilog_define REFOUT=$refout >> ${work_dir}/${file_prefix}run_pipe.log
            if {$pipe_lvl > 0} {
                resize_pblock crc_region -add {CLOCKREGION_X3Y5:CLOCKREGION_X3Y5}
            }
            opt_design >> ${work_dir}/${file_prefix}run_pipe.log
            place_design >> ${work_dir}/${file_prefix}run_pipe.log
            phys_opt_design >> ${work_dir}/${file_prefix}run_pipe.log
            after 1800000 timeout_warning continue
            route_design >> ${work_dir}/${file_prefix}run_pipe.log
            after cancel timeout_warning continue
            phys_opt_design >> ${work_dir}/${file_prefix}run_pipe.log
            write_checkpoint -force ${dcp_dir}/${file_prefix}${name}_${bus_width}_${pipe_lvl}.dcp
            set timing_log [report_timing_summary -setup -nworst 1 -return_string]
            if {[regexp {(VIOLATED)} $timing_log]} {
                set slack_met 0
                report_timing_summary -nworst 10 -file $log_dir/${file_prefix}timing_${name}_${bus_width}_${pipe_lvl}.log
            } else {
                set slack_met 1
                break
            }
            incr pipe_lvl
        }
        report_timing_summary -nworst 10 -file $log_dir/${file_prefix}timing_${name}_${bus_width}_${pipe_lvl}.log
        report_utilization -cells [get_cells u_crc_gen] -file $log_dir/${file_prefix}resource_${name}_${bus_width}.log
        regexp {CLB[ ]+\|[ ]+([0-9]+)} [report_utilization -cells [get_cells u_crc_gen] -return_string] matched clbs
        regexp {CLB LUTs[ ]+\|[ ]+([0-9]+)} [report_utilization -cells [get_cells u_crc_gen] -return_string] matched luts
        regexp {CLB Registers[ ]+\|[ ]+([0-9]+)} [report_utilization -cells [get_cells u_crc_gen] -return_string] matched ffs
        set throughput [format "%.1f" [expr $bus_width/2.0]]
        if {$byteEn} {
            set latency [format "%.1f" [expr 2*($pipe_lvl+2+log($bus_width/8)/log(2))]]
        } else {
            set latency [format "%.1f" [expr 2*($pipe_lvl+1)]]
        }
        puts "$name,$poly,$bus_width:$pipe_lvl,$throughput,$latency,$clbs,$luts,$ffs"
        set result_f [open $result_csv a]
        puts $result_f "$name,$poly,$bus_width,$pipe_lvl,$throughput,$latency,$clbs,$luts,$ffs"
        close $result_f
        close_project
    }
}
puts "finished runs, the result table can be found at ${result_dir}"
exit
