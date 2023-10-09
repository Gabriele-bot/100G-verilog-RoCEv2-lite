set part_num [lindex $argv 0]
set byteEn [lindex $argv 1]

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file dirname [file dirname [file normalize [info script]]]]
set work_dir "${root_dir}/workdir"
set freq_xdc "${root_dir}/constraints/freq.xdc"

set result_dir ${root_dir}/outputs/fmax_results
set log_dir ${result_dir}/logs
set dcp_dir ${result_dir}/dcps

if {$byteEn} {
    set result_csv $result_dir/result_byteEn.csv
} else {
    set result_csv $result_dir/result.csv
}
set result_f [open $result_csv w]
puts $result_f "name,polynomial,bus width,fmax,throughput,latency,LUTs,FFs"
close $result_f

if {$byteEn} {
    set file_prefix "byteEn_"
    set top_rtl "crc_byteEn_top"
} else {
    set file_prefix ""
    set top_rtl "crc_top"
}

foreach name {"CRC5-USB" "CRC8-Bluetooth" "CRC10-CDMA2000" "CRC16-IBM" "CRC32-Ethernet" "CRC64-ECMA"} poly {"5'h05" "8'hA7" "10'h3D9" "16'h8005" "32'h04C11DB7" "64'h42F0E1EBA9EA3693"} crc_width {5 8 10 16 32 64} init_hex {"5'b0" "8'b0" "10'b0" "16'b0" "32'hffffffff" "64'b0"} xorout {"5'b0" "8'b0" "10'b0" "16'b0" "32'hffffffff" "64'b0"} refin {"1'b0" "1'b0" "1'b0" "1'b0" "1'b1" "1'b0"} refout {"1'b0" "1'b0" "1'b0" "1'b0" "1'b1" "1'b0"} {
    set fmin 300
    set fmax 500
    foreach bus_width {64 128 256 512 1024} {
        puts "run poly: $name, bus width: $bus_width"
        set fmin 300
        set slack_met 1
        set init 1
        while {1} {
            if {$init == 1} {
                set init 0
                set freq $fmax
            } else {
                close_project
                set freq [format "%.3f" [expr ($fmin+$fmax)/2.0]]
            }
            set period [format "%.3f" [expr 1000.0/$freq]]
            set freq_xdc_f [open $freq_xdc w]
            puts $freq_xdc_f "create_clock -period $period \[get_ports clk\]"
            close $freq_xdc_f
            puts "try frequency: $freq MHz"
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
                                      -verilog_define PIPE_LVL=0 \
                                      -verilog_define CRC_POLY=$poly \
                                      -verilog_define INIT=$init_hex \
                                      -verilog_define XOR_OUT=$xorout \
                                      -verilog_define REFIN=$refin \
                                      -verilog_define REFOUT=$refout >> ${work_dir}/${file_prefix}run_fmax.log
            opt_design >> ${work_dir}/${file_prefix}run_fmax.log
            place_design >> ${work_dir}/${file_prefix}run_fmax.log
            phys_opt_design >> ${work_dir}/${file_prefix}run_fmax.log
            route_design >> ${work_dir}/${file_prefix}run_fmax.log
            phys_opt_design >> ${work_dir}/${file_prefix}run_fmax.log
            write_checkpoint -force ${dcp_dir}/${file_prefix}${name}_${bus_width}_${freq}.dcp

            set timing_log [report_timing_summary -setup -nworst 1 -return_string]
            if {[regexp {(VIOLATED)} $timing_log]} {
                set fmax $freq
                set slack_met 0
                report_timing_summary -nworst 10 -file $log_dir/${file_prefix}timing_${name}_${bus_width}_${freq}mhz.log
            } else {
                set fmin $freq
                set slack_met 1
                report_timing_summary -nworst 10 -file $log_dir/${file_prefix}timing_${name}_${bus_width}_${freq}mhz.log
                report_utilization -cells [get_cells u_crc_gen] -file $log_dir/${file_prefix}resource_${name}_${bus_width}.log
                regexp {CLB LUTs[ ]+\|[ ]+([0-9]+)} [report_utilization -cells [get_cells u_crc_gen] -return_string] matched luts
                regexp {CLB Registers[ ]+\|[ ]+([0-9]+)} [report_utilization  -cells [get_cells u_crc_gen] -return_string] matched ffs
            }
            if {[expr $fmax-$fmin] <= 5} {
                break
            }
        }
        if {$slack_met} {
            set fmax $freq
        } else {
            set fmax $fmin
        }
        set throughput [format "%.1f" [expr $bus_width*$fmax/1000.0]]
        if {$byteEn} {
            set latency [format "%.1f" [expr (1000.0/$fmax)*(2+log($bus_width/8)/log(2))]]
        } else {
            set latency [format "%.1f" [expr 1000.0/$fmax]]
        }
        puts "$name,$poly,$bus_width:$fmax,$throughput,$latency,$luts,$ffs"
        set result_f [open $result_csv a]
        puts $result_f "$name,$poly,$bus_width,$fmax,$throughput,$latency,$luts,$ffs"
        close $result_f
        close_project
    }
}
puts "finished runs, the result table can be found at ${result_dir}"
exit
