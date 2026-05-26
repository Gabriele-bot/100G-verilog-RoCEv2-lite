create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_eth
set_property -dict [list \
  CONFIG.C_DATA_DEPTH {2048} \
  CONFIG.C_INPUT_PIPE_STAGES {6} \
  CONFIG.C_NUM_OF_PROBES {11} \
  CONFIG.C_PROBE0_WIDTH {512} \
  CONFIG.C_PROBE1_WIDTH {64} \
  CONFIG.C_PROBE2_WIDTH {1} \
  CONFIG.C_PROBE3_WIDTH {1} \
  CONFIG.C_PROBE4_WIDTH {1} \
  CONFIG.C_PROBE5_WIDTH {1} \
  CONFIG.C_PROBE6_WIDTH {1} \
  CONFIG.C_PROBE7_WIDTH {1} \
  CONFIG.C_PROBE8_WIDTH {48} \
  CONFIG.C_PROBE9_WIDTH {48} \
  CONFIG.C_PROBE10_WIDTH {16} \
  CONFIG.Component_Name {ila_eth} \
] [get_ips ila_eth]
