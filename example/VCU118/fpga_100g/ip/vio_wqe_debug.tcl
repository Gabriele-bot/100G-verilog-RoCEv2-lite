create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_wqe_debug
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN {10} \
  CONFIG.C_NUM_PROBE_OUT {0} \
  CONFIG.C_PROBE_IN0_WIDTH {3} \
  CONFIG.C_PROBE_IN1_WIDTH {1} \
  CONFIG.C_PROBE_IN2_WIDTH {3} \
  CONFIG.C_PROBE_IN3_WIDTH {32} \
  CONFIG.C_PROBE_IN4_WIDTH {24} \
  CONFIG.C_PROBE_IN5_WIDTH {24} \
  CONFIG.C_PROBE_IN6_WIDTH {24} \
  CONFIG.C_PROBE_IN7_WIDTH {24} \
  CONFIG.C_PROBE_IN8_WIDTH {32} \
  CONFIG.C_PROBE_IN9_WIDTH {64} \
  CONFIG.Component_Name {vio_wqe_debug} \
] [get_ips vio_wqe_debug]
