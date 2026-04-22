TARGET_TAP = tapdev
TARGET_TB = tb
TARGET_DPI = tb_svdpi
BUILD_DIR = work
SIMULATOR ?= VIVADO
MAIN_DIR ?= ../..
LICENCE_SERVER ?=  

TARGET_TAP_PID_FILE = tapdev.pid


ETH_MODULES     = eth_modules.txt
ROCE_MODULES = roce_modules.txt

ETH_VERILOG_DIR = $(MAIN_DIR)/lib/eth
CRC32_DIR = $(MAIN_DIR)/lib/FAST_CRC32
ROCE_DIR = $(MAIN_DIR)/rtl
ROCE_DIR_SIM = $(MAIN_DIR)/sim

ifeq ($(SIMULATOR), VIVADO)
VLOG = xvlog
VHD  = xvhdl
VSIM = xsim
VDPI = xsc
VLOG_SV_OPT = -svlog
VOPTARGS =
VSIMCMDS = -gui -tclbatch run.tcl
else ifeq ($(SIMULATOR), QUESTA)
VLOG = vlog
VHD  = vcom
VSIM = vsim
VDPI = vlog
VLOG_SV_OPT = -sv
VOPTARGS = -voptargs=+acc
VSIMCMDS = -do "run -all"
else ifeq ($(SIMULATOR), VCS)
VLOG = vlog
VHD  = cvom
VSIM = vsim
VDPI = vlog
VOPTARGS = 
VSIMCMDS = -do "run -all"
else
VLOG = vlog
VHD  = com
VSIM = vsim
VDPI = vlog
endif

VIVADO_PATH ?= /tools/Xilinx/Vivado/2022.2

XILINX  = $(VIVADO_PATH)/data/vhdl/src/unisims
XPM     = $(VIVADO_PATH)/data/ip/xpm/
XPM_MEM = $(VIVADO_PATH)/data/ip/xpm/xpm_memory/hdl
CC = gcc -lrt
CFLAGS = -Wall -O -lrt
VLIB = vlib

define compile_modules
	@while read -r module; do \
		ext="$$(echo $$module | awk -F. '{print $$NF}')"; \
		full_module_path="$(1)/$$module"; \
		if [ "$$ext" = "vhd" ]; then \
			$(VHD) -work work $$full_module_path; \
		elif [ "$$ext" = "v" ]; then \
			$(VLOG) -work work $$full_module_path; \
		elif [ "$$ext" = "sv" ]; then \
			$(VLOG) -work work $(VLOG_SV_OPT) $$full_module_path; \
		fi \
	done < $(2)
endef

all: buildtap buildsim
buildtap: tapdev
buildsim: simlog

tapdev: tapdev.c
	gcc -o tapdev -Wall -O tapdev.c -pthread -lrt

dirs:
	mkdir -p $(BUILD_DIR)
	mkdir -p unisim xpm

xpm: dirs
	$(VLOG) -work glbl $(XILINX)/../../../verilog/src/glbl.v
	$(VHD) -work work $(XPM)/xpm_VCOMP.vhd
	$(VLOG) -work work -sv $(XPM)/xpm_fifo/hdl/xpm_fifo.sv
	$(VLOG) -work work -sv $(XPM)/xpm_cdc/hdl/xpm_cdc.sv
	$(VLOG) -work work -sv $(XPM_MEM)/xpm_memory.sv

unisim_pkg: dirs
	$(VHD) -work work $(XILINX)/unisim_VPKG.vhd
	$(VHD) -work work $(XILINX)/unisim_VCOMP.vhd
	$(VHD) -work work $(XILINX)/retarget_VCOMP.vhd
	$(VHD) -work work $(XILINX)/unisim_retarget_VCOMP.vhd

unisim: unisim_pkg
	$(VHD) -work work $(XILINX)/retarget/*.vhd

verilog-ethernet: dirs
	$(info Using simulator: $(SIMULATOR))
	$(call compile_modules, $(ETH_VERILOG_DIR), $(ETH_MODULES))
	
crc-pkg: verilog-ethernet
	$(info Using simulator: $(SIMULATOR))
	$(VLOG)  -work work $(VLOG_SV_OPT) $(ROCE_DIR)/utils/crc_byteEn.sv
	$(VHD)  -work work -2008 $(CRC32_DIR)/CRC32/CRC32_pkg.vhd
	$(VHD)  -work work -2008 $(CRC32_DIR)/CRC32/CRC32_D512_matrix.vhd
	$(VHD)  -work work -2008 $(CRC32_DIR)/Experimental/CRC32_matrix_pipeline.vhd
	
RoCE-stack: crc-pkg
	$(info Using simulator: $(SIMULATOR))
	$(call compile_modules, $(ROCE_DIR), $(ROCE_MODULES))

simlog: dirs xpm
	$(info Using simulator: $(SIMULATOR))
	$(VLOG) -work work $(VLOG_SV_OPT) $(ROCE_DIR_SIM)/fpga_core_10g_generic_with_roce_sim.sv
	$(VDPI) $(TARGET_DPI).c
	$(VLOG) -work work $(VLOG_SV_OPT) $(ROCE_DIR_SIM)/tb.sv

ifeq ($(SIMULATOR), VIVADO)
	xelab work.tb glbl.glbl -sv_lib dpi -debug typical
else
	$(VLOG) -work work $(VLOG_SV_OPT) $(ROCE_DIR_SIM)/tb.sv
endif


tap: tapdev
	sudo ./$(TARGET_TAP) tap0 
	
sim: 
ifeq ($(SIMULATOR), VIVADO)
	sudo env "PATH=$(PATH)" "LM_LICENSE_FILE=$(LICENCE_SERVER)" $(VSIM) $(VOPTARGS) work.$(TARGET_TB)#glbl.glbl -gui
else
	sudo env "PATH=$(PATH)" "LM_LICENSE_FILE=$(LICENCE_SERVER)" $(VSIM) $(VOPTARGS) work.$(TARGET_TB) 
endif


.PHONY: clean
clean:
	sudo rm -f *.o $(TARGET_TAP)
	sudo rm -f *.so transcript *.vcd
	sudo rm -rf $(BUILD_DIR)
	sudo rm -rf csrc simv* *.log xpm surf unisim work *.vpd *.key DVEfiles DEFAULT.DB WORK *.so output
	sudo rm -rf xsim.dir *.pb *.log *.jou *.wdb .Xil glbl
