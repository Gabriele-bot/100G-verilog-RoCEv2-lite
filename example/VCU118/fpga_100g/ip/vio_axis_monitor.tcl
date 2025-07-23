create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_axis_monitor
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN {9} \
  CONFIG.C_NUM_PROBE_OUT {0} \
  CONFIG.C_PROBE_IN0_WIDTH {27} \
  CONFIG.C_PROBE_IN1_WIDTH {27} \
  CONFIG.C_PROBE_IN2_WIDTH {27} \
  CONFIG.C_PROBE_IN3_WIDTH {27} \
  CONFIG.C_PROBE_IN4_WIDTH {27} \
  CONFIG.C_PROBE_IN5_WIDTH {27} \
  CONFIG.C_PROBE_IN6_WIDTH {27} \
  CONFIG.C_PROBE_IN7_WIDTH {27} \
  CONFIG.C_PROBE_IN8_WIDTH {27} \
  CONFIG.Component_Name {vio_axis_monitor} \
] [get_ips vio_axis_monitor]
