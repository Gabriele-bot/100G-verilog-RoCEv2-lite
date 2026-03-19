create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_ext_rst
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN {0} \
  CONFIG.C_NUM_PROBE_OUT {2} \
  CONFIG.Component_Name {vio_ext_rst} \
] [get_ips vio_ext_rst]
