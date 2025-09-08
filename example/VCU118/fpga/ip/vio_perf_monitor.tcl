create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_perf_monitor
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN {3} \
  CONFIG.C_NUM_PROBE_OUT {4} \
  CONFIG.C_PROBE_OUT0_WIDTH {4} \
  CONFIG.C_PROBE_OUT1_WIDTH {24} \
  CONFIG.C_PROBE_OUT2_WIDTH {3} \
  CONFIG.C_PROBE_IN0_WIDTH {32} \
  CONFIG.C_PROBE_IN1_WIDTH {32} \
  CONFIG.C_PROBE_IN2_WIDTH {32} \
  CONFIG.C_PROBE_IN3_WIDTH {32} \
  CONFIG.Component_Name {vio_perf_monitor} \
] [get_ips vio_perf_monitor]
