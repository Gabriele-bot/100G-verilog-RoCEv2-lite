create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_latency_distrib
set_property -dict [list \
  CONFIG.C_DATA_DEPTH {4096} \
  CONFIG.C_INPUT_PIPE_STAGES {6} \
  CONFIG.C_NUM_OF_PROBES {3} \
  CONFIG.C_PROBE0_WIDTH {24} \
  CONFIG.C_PROBE1_WIDTH {12} \
  CONFIG.C_PROBE2_WIDTH {1} \
  CONFIG.Component_Name {ila_latency_distrib} \
] [get_ips ila_latency_distrib]
