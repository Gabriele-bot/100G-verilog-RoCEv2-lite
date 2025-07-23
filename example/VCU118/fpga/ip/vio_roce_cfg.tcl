create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_roce_ip_cfg
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN {0} \
  CONFIG.C_NUM_PROBE_OUT {4} \
  CONFIG.C_PROBE_OUT0_INIT_VAL {0x4} \
  CONFIG.C_PROBE_OUT0_WIDTH {3} \
  CONFIG.C_PROBE_OUT1_INIT_VAL {0x12b7} \
  CONFIG.C_PROBE_OUT1_WIDTH {16} \
  CONFIG.C_PROBE_OUT2_INIT_VAL {0x1601d40a} \
  CONFIG.C_PROBE_OUT2_WIDTH {32} \
  CONFIG.Component_Name {vio_roce_ip_cfg} \
] [get_ips vio_roce_ip_cfg]
