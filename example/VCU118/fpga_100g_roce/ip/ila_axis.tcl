create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_axis
set_property -dict [list \
  CONFIG.C_DATA_DEPTH {4096} \
  CONFIG.C_INPUT_PIPE_STAGES {5} \
  CONFIG.C_NUM_OF_PROBES {6} \
  CONFIG.C_PROBE0_WIDTH {512} \
  CONFIG.C_PROBE1_WIDTH {64} \
  CONFIG.Component_Name {ila_axis} \
] [get_ips ila_axis]
