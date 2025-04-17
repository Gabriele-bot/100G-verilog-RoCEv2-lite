create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_throughput
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN {8} \
  CONFIG.C_PROBE_IN0_WIDTH {27} \
  CONFIG.C_PROBE_IN1_WIDTH {27} \
  CONFIG.C_PROBE_IN2_WIDTH {27} \
  CONFIG.C_PROBE_IN3_WIDTH {64} \
  CONFIG.C_PROBE_IN4_WIDTH {64} \
  CONFIG.C_PROBE_IN5_WIDTH {64} \
  CONFIG.C_PROBE_IN6_WIDTH {64} \
  CONFIG.C_PROBE_IN7_WIDTH {24} \
  CONFIG.C_PROBE_OUT0_WIDTH {32} \
  CONFIG.Component_Name {vio_throughput} \
] [get_ips vio_throughput]
