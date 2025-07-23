create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_qp_state_spy
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN {11} \
  CONFIG.C_NUM_PROBE_OUT {2} \
  CONFIG.C_PROBE_IN0_WIDTH {3} \
  CONFIG.C_PROBE_IN1_WIDTH {32} \
  CONFIG.C_PROBE_IN2_WIDTH {24} \
  CONFIG.C_PROBE_IN3_WIDTH {24} \
  CONFIG.C_PROBE_IN4_WIDTH {24} \
  CONFIG.C_PROBE_IN5_WIDTH {24} \
  CONFIG.C_PROBE_IN6_WIDTH {24} \
  CONFIG.C_PROBE_IN7_WIDTH {24} \
  CONFIG.C_PROBE_IN8_WIDTH {32} \
  CONFIG.C_PROBE_IN9_WIDTH {64} \
  CONFIG.C_PROBE_IN10_WIDTH {8} \
  CONFIG.C_PROBE_OUT0_WIDTH {1} \
  CONFIG.C_PROBE_OUT1_WIDTH {24} \
   CONFIG.C_PROBE_OUT1_INIT_VAL {0x000100} \
  CONFIG.Component_Name {vio_qp_state_spy} \
] [get_ips vio_qp_state_spy]
