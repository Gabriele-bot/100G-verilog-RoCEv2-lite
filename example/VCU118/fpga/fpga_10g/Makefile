
# FPGA settings
FPGA_PART = xcvu9p-flga2104-2L-e
FPGA_TOP = fpga
FPGA_ARCH = virtexuplus

# Files for synthesis
SYN_FILES = rtl/fpga.v
SYN_FILES += rtl/fpga_core.v
SYN_FILES += rtl/eth_xcvr_phy_wrapper.v
SYN_FILES += rtl/eth_xcvr_phy_quad_wrapper.v
SYN_FILES += rtl/debounce_switch.v
SYN_FILES += rtl/sync_signal.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_mac_10g_fifo.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_mac_10g.v
SYN_FILES += lib/RoCE/lib/eth/rtl/mac_ctrl_tx.v
SYN_FILES += lib/RoCE/lib/eth/rtl/mac_ctrl_rx.v
SYN_FILES += lib/RoCE/lib/eth/rtl/mac_pause_ctrl_tx.v
SYN_FILES += lib/RoCE/lib/eth/rtl/mac_pause_ctrl_rx.v
SYN_FILES += lib/RoCE/lib/eth/rtl/axis_xgmii_rx_64.v
SYN_FILES += lib/RoCE/lib/eth/rtl/axis_xgmii_tx_64.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_phy_10g.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_phy_10g_rx.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_phy_10g_rx_if.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_phy_10g_rx_frame_sync.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_phy_10g_rx_ber_mon.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_phy_10g_rx_watchdog.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_phy_10g_tx.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_phy_10g_tx_if.v
SYN_FILES += lib/RoCE/lib/eth/rtl/xgmii_baser_dec_64.v
SYN_FILES += lib/RoCE/lib/eth/rtl/xgmii_baser_enc_64.v
SYN_FILES += lib/RoCE/lib/eth/rtl/lfsr.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_axis_rx.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_axis_tx.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_hdr_fifo.v
SYN_FILES += lib/RoCE/lib/eth/rtl/udp_complete_64.v
SYN_FILES += lib/RoCE/lib/eth/rtl/udp_checksum_gen_test.v
SYN_FILES += lib/RoCE/lib/eth/rtl/udp_test.v
SYN_FILES += lib/RoCE/lib/eth/rtl/udp_ip_rx_test.v
SYN_FILES += lib/RoCE/lib/eth/rtl/udp_ip_tx_test.v
SYN_FILES += lib/RoCE/lib/eth/rtl/ip_complete_64.v
SYN_FILES += lib/RoCE/lib/eth/rtl/ip_test.v
SYN_FILES += lib/RoCE/lib/eth/rtl/ip_eth_rx_test.v
SYN_FILES += lib/RoCE/lib/eth/rtl/ip_eth_tx_test.v
SYN_FILES += lib/RoCE/lib/eth/rtl/ip_arb_mux.v
SYN_FILES += lib/RoCE/lib/eth/rtl/icmp_ip_tx.v
SYN_FILES += lib/RoCE/lib/eth/rtl/icmp_ip_rx.v
SYN_FILES += lib/RoCE/lib/eth/rtl/icmp_gen_checksum.v
SYN_FILES += lib/RoCE/lib/eth/rtl/icmp_echo_reply.v
SYN_FILES += lib/RoCE/lib/eth/rtl/arp.v
SYN_FILES += lib/RoCE/lib/eth/rtl/arp_cache.v
SYN_FILES += lib/RoCE/lib/eth/rtl/arp_eth_rx.v
SYN_FILES += lib/RoCE/lib/eth/rtl/arp_eth_tx.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_demux.v
SYN_FILES += lib/RoCE/lib/eth/rtl/eth_arb_mux.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/arbiter.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/priority_encoder.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/axis_adapter.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/axis_fifo.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/axis_srl_fifo.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/axis_switch.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/axis_register.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/axis_pipeline_register.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/axis_frame_length_adjust.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/axis_async_fifo.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/axis_async_fifo_adapter.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/axis_broadcast.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/axis_mux.v
SYN_FILES += lib/RoCE/lib/eth/lib/axis/rtl/sync_reset.v
SYN_FILES += lib/RoCE/lib/eth/lib/axi/rtl/axi_dma_wr.v
SYN_FILES += lib/RoCE/lib/eth/lib/axi/rtl/axi_dma_rd.v
SYN_FILES += lib/RoCE/lib/eth/lib/axi/rtl/axi_dma.v
SYN_FILES += lib/RoCE/lib/eth/lib/axi/rtl/axi_register_wr.v
SYN_FILES += lib/RoCE/lib/eth/lib/axi/rtl/axi_register_rd.v
SYN_FILES += lib/RoCE/lib/eth/lib/axi/rtl/axi_register.v


# RoCE Files
SYN_FILES +=  lib/RoCE/rtl/axis_mask_fields_icrc.v
SYN_FILES +=  lib/RoCE/rtl/axis_RoCE_icrc_insert_64.v
SYN_FILES +=  lib/RoCE/rtl/RoCE_udp_tx_64.v
SYN_FILES +=  lib/RoCE/rtl/RoCE_udp_rx_64.v
SYN_FILES +=  lib/RoCE/rtl/RoCE_tx_header_producer.v
SYN_FILES +=  lib/RoCE/rtl/RoCE_minimal_stack_64.v
SYN_FILES +=  lib/RoCE/rtl/udp_RoCE_connection_manager_64.v
SYN_FILES +=  lib/RoCE/rtl/RoCE_latency_eval.v
SYN_FILES +=  lib/RoCE/rtl/RoCE_qp_state_module.v
SYN_FILES +=  lib/RoCE/rtl/RoCE_retransmission_module.v
SYN_FILES +=  lib/RoCE/rtl/ram_block.v
SYN_FILES +=  lib/RoCE/rtl/axis_handshake_monitor.vhd
SYN_FILES +=  lib/RoCE/rtl/axi_ram_mod.v
SYN_FILES +=  lib/RoCE/rtl/test_ram.v

#CRC FILES
SYN_FILES += lib/RoCE/lib/FAST_CRC32/CRC32/CRC32_pkg.vhd
SYN_FILES += lib/RoCE/lib/FAST_CRC32/Experimental/CRC32_matrix_pipeline.vhd


# XDC files
XDC_FILES = fpga.xdc
XDC_FILES += lib/RoCE/lib/eth/syn/vivado/eth_mac_fifo.tcl
XDC_FILES += lib/RoCE/lib/eth/lib/axis/syn/vivado/axis_async_fifo.tcl
XDC_FILES += lib/RoCE/lib/eth/lib/axis/syn/vivado/sync_reset.tcl

# IP
IP_TCL_FILES = ip/eth_xcvr_gt.tcl
IP_TCL_FILES += ip/vio_ext_rst.tcl
IP_TCL_FILES += ip/vio_roce_cfg.tcl
IP_TCL_FILES += ip/vio_throughput.tcl
IP_TCL_FILES += ip/vio_retrans_debug.tcl
IP_TCL_FILES += ip/ila_axis.tcl

# Configuration
CONFIG_TCL_FILES = ./config.tcl


include ../common/vivado.mk

program: $(FPGA_TOP).bit
	echo "open_hw" > program.tcl
	echo "connect_hw_server" >> program.tcl
	echo "open_hw_target" >> program.tcl
	echo "current_hw_device [lindex [get_hw_devices] 0]" >> program.tcl
	echo "refresh_hw_device -update_hw_probes false [current_hw_device]" >> program.tcl
	echo "set_property PROGRAM.FILE {$(FPGA_TOP).bit} [current_hw_device]" >> program.tcl
	echo "program_hw_devices [current_hw_device]" >> program.tcl
	echo "exit" >> program.tcl
	vivado -nojournal -nolog -mode batch -source program.tcl

%_primary.mcs %_secondary.mcs %_primary.prm %_secondary.prm: %.bit
	echo "write_cfgmem -force -format mcs -size 256 -interface SPIx8 -loadbit {up 0x0000000 $*.bit} -checksum -file $*.mcs" > generate_mcs.tcl
	echo "exit" >> generate_mcs.tcl
	vivado -nojournal -nolog -mode batch -source generate_mcs.tcl
	mkdir -p rev
	COUNT=100; \
	while [ -e rev/$*_rev$$COUNT.bit ]; \
	do COUNT=$$((COUNT+1)); done; \
	COUNT=$$((COUNT-1)); \
	for x in _primary.mcs _secondary.mcs _primary.prm _secondary.prm; \
	do cp $*$$x rev/$*_rev$$COUNT$$x; \
	echo "Output: rev/$*_rev$$COUNT$$x"; done;

flash: $(FPGA_TOP)_primary.mcs $(FPGA_TOP)_secondary.mcs $(FPGA_TOP)_primary.prm $(FPGA_TOP)_secondary.prm
	echo "open_hw" > flash.tcl
	echo "connect_hw_server" >> flash.tcl
	echo "open_hw_target" >> flash.tcl
	echo "current_hw_device [lindex [get_hw_devices] 0]" >> flash.tcl
	echo "refresh_hw_device -update_hw_probes false [current_hw_device]" >> flash.tcl
	echo "create_hw_cfgmem -hw_device [current_hw_device] [lindex [get_cfgmem_parts {mt25qu01g-spi-x1_x2_x4_x8}] 0]" >> flash.tcl
	echo "current_hw_cfgmem -hw_device [current_hw_device] [get_property PROGRAM.HW_CFGMEM [current_hw_device]]" >> flash.tcl
	echo "set_property PROGRAM.FILES [list \"$(FPGA_TOP)_primary.mcs\" \"$(FPGA_TOP)_secondary.mcs\"] [current_hw_cfgmem]" >> flash.tcl
	echo "set_property PROGRAM.PRM_FILES [list \"$(FPGA_TOP)_primary.prm\" \"$(FPGA_TOP)_secondary.prm\"] [current_hw_cfgmem]" >> flash.tcl
	echo "set_property PROGRAM.ERASE 1 [current_hw_cfgmem]" >> flash.tcl
	echo "set_property PROGRAM.CFG_PROGRAM 1 [current_hw_cfgmem]" >> flash.tcl
	echo "set_property PROGRAM.VERIFY 1 [current_hw_cfgmem]" >> flash.tcl
	echo "set_property PROGRAM.CHECKSUM 0 [current_hw_cfgmem]" >> flash.tcl
	echo "set_property PROGRAM.ADDRESS_RANGE {use_file} [current_hw_cfgmem]" >> flash.tcl
	echo "set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} [current_hw_cfgmem]" >> flash.tcl
	echo "create_hw_bitstream -hw_device [current_hw_device] [get_property PROGRAM.HW_CFGMEM_BITFILE [current_hw_device]]" >> flash.tcl
	echo "program_hw_devices [current_hw_device]" >> flash.tcl
	echo "refresh_hw_device [current_hw_device]" >> flash.tcl
	echo "program_hw_cfgmem -hw_cfgmem [current_hw_cfgmem]" >> flash.tcl
	echo "boot_hw_device [current_hw_device]" >> flash.tcl
	echo "exit" >> flash.tcl
	vivado -nojournal -nolog -mode batch -source flash.tcl

