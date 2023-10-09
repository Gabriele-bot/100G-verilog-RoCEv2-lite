include config.mk
find_fmax: hdl/crc_top.sv hdl/config.svh ../core_src/crc.sv ../core_src/crc.svh scripts/find_fmax_nopipe.tcl
	@rm -rf workdir/run_fmax.log
	@vivado -mode batch -nojournal -nolog -source scripts/find_fmax_nopipe.tcl -tclargs $(PART_NUM) 0
	@find . -mindepth 1 -maxdepth 1 ! -name Makefile ! -name .gitignore ! -name config.mk -type f | xargs -n 1 rm -rf
	@find . -mindepth 1 -maxdepth 1 ! -name constraints ! -name hdl ! -name outputs ! -name scripts ! -name workdir -type d | xargs -n 1 rm -rf

find_fmax_byteEn: hdl/crc_byteEn_top.sv hdl/config.svh ../core_src/crc_byteEn.sv ../core_src/crc.svh scripts/find_fmax_nopipe.tcl
	@rm -rf workdir/byteEn_run_fmax.log
	@vivado -mode batch -nojournal -nolog -source scripts/find_fmax_nopipe.tcl -tclargs $(PART_NUM) 1
	@find . -mindepth 1 -maxdepth 1 ! -name Makefile ! -name .gitignore ! -name config.mk -type f | xargs -n 1 rm -rf
	@find . -mindepth 1 -maxdepth 1 ! -name constraints ! -name hdl ! -name outputs ! -name scripts ! -name workdir -type d | xargs -n 1 rm -rf

find_pipe_lvl_500mhz: hdl/crc_top.sv hdl/config.svh ../core_src/crc.sv ../core_src/crc.svh scripts/find_pipe_lvl_500mhz.tcl
	@rm -rf workdir/run_pipe.log
	@vivado -mode batch -nojournal -nolog -source scripts/find_pipe_lvl_500mhz.tcl -tclargs $(PART_NUM) 0
	@find . -mindepth 1 -maxdepth 1 ! -name Makefile ! -name .gitignore ! -name config.mk -type f | xargs -n 1 rm -rf
	@find . -mindepth 1 -maxdepth 1 ! -name constraints ! -name hdl ! -name outputs ! -name scripts ! -name workdir -type d | xargs -n 1 rm -rf

find_pipe_lvl_500mhz_byteEn: hdl/crc_byteEn_top.sv hdl/config.svh ../core_src/crc_byteEn.sv ../core_src/crc.svh scripts/find_pipe_lvl_500mhz.tcl
	@rm -rf workdir/byteEn_run_pipe.log
	@vivado -mode batch -nojournal -nolog -source scripts/find_pipe_lvl_500mhz.tcl -tclargs $(PART_NUM) 1
	@find . -mindepth 1 -maxdepth 1 ! -name Makefile ! -name .gitignore ! -name config.mk -type f | xargs -n 1 rm -rf
	@find . -mindepth 1 -maxdepth 1 ! -name constraints ! -name hdl ! -name outputs ! -name scripts ! -name workdir -type d | xargs -n 1 rm -rf

clean:
	@find . -mindepth 1 -maxdepth 1 ! -name Makefile ! -name .gitignore ! -name config.mk -type f | xargs -n 1 rm -rf
	@find . -mindepth 1 -maxdepth 1 ! -name constraints ! -name hdl ! -name outputs ! -name scripts ! -name workdir -type d | xargs -n 1 rm -rf

clean_all:
	@rm -f workdir/*run*.log
	@rm -f outputs/fmax_results/result*
	@rm -f outputs/fmax_results/logs/*
	@rm -f outputs/pipe_lvl_results/result*
	@rm -f outputs/pipe_lvl_results/logs/*
	@find . -mindepth 1 -maxdepth 1 ! -name Makefile ! -name .gitignore ! -name config.mk -type f | xargs -n 1 rm -rf
	@find . -mindepth 1 -maxdepth 1 ! -name constraints ! -name hdl ! -name outputs ! -name scripts ! -name workdir -type d | xargs -n 1 rm -rf
