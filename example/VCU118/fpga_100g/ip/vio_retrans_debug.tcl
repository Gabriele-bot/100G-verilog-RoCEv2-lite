create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_retrans_debug
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN {13} \
  CONFIG.C_NUM_PROBE_OUT {0} \
  CONFIG.C_PROBE_IN0_WIDTH {4} \
  CONFIG.C_PROBE_IN1_WIDTH {1} \
  CONFIG.C_PROBE_IN2_WIDTH {64} \
  CONFIG.C_PROBE_IN3_WIDTH {4} \
  CONFIG.C_PROBE_IN4_WIDTH {22} \
  CONFIG.C_PROBE_IN5_WIDTH {13} \
  CONFIG.C_PROBE_IN6_WIDTH {4} \
  CONFIG.C_PROBE_IN7_WIDTH {22} \
  CONFIG.C_PROBE_IN8_WIDTH {13} \
  CONFIG.C_PROBE_IN9_WIDTH {14} \
  CONFIG.C_PROBE_IN10_WIDTH {24} \
  CONFIG.C_PROBE_IN11_WIDTH {24} \
  CONFIG.C_PROBE_IN12_WIDTH {32} \
  CONFIG.Component_Name {vio_retrans_debug} \
] [get_ips vio_retrans_debug]
