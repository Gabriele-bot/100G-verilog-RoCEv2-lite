TB_TOP = tb_udp_RoCE_connection_manager
SIMULATOR ?= VIVADO

$(info Using simulator: $(SIMULATOR))

ifeq ($(SIMULATOR), VIVADO)
VLOG = xvlog
VHD  = xvhdl
VSIM = xsim
VOPTARGS =
VSIMCMDS = -gui -tclbatch run.tcl
VDPI = xsc
VLOG_SV_OPT = -svlog
else ifeq ($(SIMULATOR), QUESTA)
VLOG = vlog
VHD  = vcom
VSIM = vsim
VOPTARGS = -voptargs=+acc
VSIMCMDS = -do "run -all"
VDPI = vlog
VLOG_SV_OPT = -sv
else ifeq ($(SIMULATOR), VCS)
VLOG = vlog
VHD  = cvom
VSIM = vsim
VOPTARGS = 
VSIMCMDS = -do "run -all"
VDPI = vlog
VLOG_SV_OPT = -sv
else
VLOG = vlog
VHD  = com
VSIM = vsim
VDPI = vlog
endif

rtl:
	$(VLOG) -work work $(VLOG_SV_OPT) ../../header_files/Board_parameters.sv
	$(VLOG) -work work $(VLOG_SV_OPT) ../../header_files/RoCE_parameters.sv
	$(VLOG) -work work $(VLOG_SV_OPT) ../../qp_state/RoCE_qp_state_module.sv 
	$(VLOG) -work work $(VLOG_SV_OPT) ../../qp_state/qpn_fifo_init.sv 
	$(VLOG) -work work $(VLOG_SV_OPT) ../../connection_manager/udp_RoCE_connection_manager_rx.sv $(VLOG_SV_OPT) ../../connection_manager/udp_RoCE_connection_manager_tx.sv $(VLOG_SV_OPT) ../../connection_manager/udp_RoCE_connection_manager.sv
	$(VLOG) -work work $(VLOG_SV_OPT) ../../connection_manager/sim/udp_RoCE_connection_manager_tb.sv 
ifeq ($(SIMULATOR), VIVADO)
	xelab work.$(TB_TOP) -debug typical
endif

sim: rtl
	$(VSIM) $(VOPTARGS) work.$(TB_TOP) $(VSIMCMDS)

clean:
	rm -rf *.wdb *.jou *.log *.pb .Xil work xsim.dir transcript
