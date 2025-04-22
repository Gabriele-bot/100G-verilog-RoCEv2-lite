include config.mk
sim: hdl/crc_tb.sv hdl/crc_top.sv hdl/config.svh ../core_src/crc.sv ../core_src/crc.svh scripts/run_sim.tcl
	@rm -rf workdir/tbps_crc_simulation
	@vivado -mode tcl -nojournal -nolog -notrace -source scripts/run_sim.tcl -tclargs $(PART_NUM) $(DWIDTH) $(CRC_WIDTH) $(PIPE_LVL) $(CRC_POLY) $(INIT) $(XOR_OUT) $(REFIN) $(REFOUT) 0 $(N_MESSAGE) $(MESSAGE_LEN_MIN) $(MESSAGE_LEN_MAX) $(flitEn_ratio)
	@find . -mindepth 1 -maxdepth 1 ! -name Makefile ! -name .gitignore ! -name config.mk ! -name board_clk_source.xdc -type f | xargs -n 1 rm -rf
	@find . -mindepth 1 -maxdepth 1 ! -name hdl ! -name outputs ! -name scripts ! -name workdir -type d | xargs -n 1 rm -rf

sim_byteEn: hdl/crc_byteEn_tb.sv hdl/crc_byteEn_top.sv hdl/config.svh ../core_src/crc_byteEn.sv ../core_src/crc.svh scripts/run_sim.tcl
	@rm -rf workdir/tbps_crc_byteEn_simulation
	@vivado -mode tcl -nojournal -nolog -notrace -source scripts/run_sim.tcl -tclargs $(PART_NUM) $(DWIDTH) $(CRC_WIDTH) $(PIPE_LVL) $(CRC_POLY) $(INIT) $(XOR_OUT) $(REFIN) $(REFOUT) 1 $(N_MESSAGE) $(MESSAGE_LEN_MIN) $(MESSAGE_LEN_MAX) $(flitEn_ratio)
	@find . -mindepth 1 -maxdepth 1 ! -name Makefile ! -name .gitignore ! -name config.mk ! -name board_clk_source.xdc -type f | xargs -n 1 rm -rf
	@find . -mindepth 1 -maxdepth 1 ! -name hdl ! -name outputs ! -name scripts ! -name workdir -type d | xargs -n 1 rm -rf

gen_bitstream: hdl/crc_top.sv hdl/config.svh ../core_src/crc.sv ../core_src/crc.svh scripts/run_impl.tcl
	@rm -rf workdir/tbps_crc_implementation
	@vivado -mode batch -nojournal -nolog -notrace -source scripts/run_impl.tcl -tclargs $(PART_NUM) $(DWIDTH) $(CRC_WIDTH) $(PIPE_LVL) $(CRC_POLY) $(INIT) $(XOR_OUT) $(REFIN) $(REFOUT) 0 $(PKT_LIMIT) $(BYTE_BITS)
	@cp workdir/tbps_crc_implementation/tbps_crc_implementation.runs/impl_1/crc_top.bit outputs/
	@cp workdir/tbps_crc_implementation/tbps_crc_implementation.runs/impl_1/crc_top.ltx outputs/
	@find . -mindepth 1 -maxdepth 1 ! -name Makefile ! -name .gitignore ! -name config.mk ! -name board_clk_source.xdc -type f | xargs -n 1 rm -rf
	@find . -mindepth 1 -maxdepth 1 ! -name hdl ! -name outputs ! -name scripts ! -name workdir -type d | xargs -n 1 rm -rf

gen_bitstream_byteEn: hdl/crc_byteEn_top.sv hdl/config.svh ../core_src/crc_byteEn.sv ../core_src/crc.svh scripts/run_impl.tcl
	@rm -rf workdir/tbps_crc_byteEn_implementation
	@vivado -mode batch -nojournal -nolog -notrace -source scripts/run_impl.tcl -tclargs $(PART_NUM) $(DWIDTH) $(CRC_WIDTH) $(PIPE_LVL) $(CRC_POLY) $(INIT) $(XOR_OUT) $(REFIN) $(REFOUT) 1 $(PKT_LIMIT) $(BYTE_BITS)
	@cp workdir/tbps_crc_byteEn_implementation/tbps_crc_byteEn_implementation.runs/impl_1/crc_byteEn_top.bit outputs/
	@cp workdir/tbps_crc_byteEn_implementation/tbps_crc_byteEn_implementation.runs/impl_1/crc_byteEn_top.ltx outputs/
	@find . -mindepth 1 -maxdepth 1 ! -name Makefile ! -name .gitignore ! -name config.mk ! -name board_clk_source.xdc -type f | xargs -n 1 rm -rf
	@find . -mindepth 1 -maxdepth 1 ! -name hdl ! -name outputs ! -name scripts ! -name workdir -type d | xargs -n 1 rm -rf

clean:
	@find . -mindepth 1 -maxdepth 1 ! -name Makefile ! -name .gitignore ! -name config.mk ! -name board_clk_source.xdc -type f | xargs -n 1 rm -rf
	@find . -mindepth 1 -maxdepth 1 ! -name hdl ! -name outputs ! -name scripts ! -name workdir -type d | xargs -n 1 rm -rf

clean_all:
	@find . -mindepth 1 -maxdepth 1 ! -name Makefile ! -name .gitignore ! -name config.mk ! -name board_clk_source.xdc -type f | xargs -n 1 rm -rf
	@find . -mindepth 1 -maxdepth 1 ! -name hdl ! -name outputs ! -name scripts ! -name workdir -type d | xargs -n 1 rm -rf
	@rm -rf workdir/*
	@rm -f outputs/*
