`default_nettype none
`timescale 1ns / 1ps

module tb #(
	parameter max_recvpkt = 100000,
	parameter nPreamble = 8,
	parameter nIFG = 12
)();

import "DPI-C" context function int shared_mem_init();
import "DPI-C" context task tap2xgmii(output int ret);
import "DPI-C" context function int xgmii_read(longint xgmiiTxd, byte xgmiiTxc);
export "DPI-C" task xgmii_write;
export "DPI-C" task xgmii_idle;

logic clk20;
logic clk160;
logic extRst;
logic mem_clk;
logic mem_rst;
logic c0_sys_clk_p;
logic c0_sys_clk_n;
logic c1_sys_clk_p;
logic c1_sys_clk_n;
logic [7:0] xgmiiTxc;
logic [63:0] xgmiiTxd;
logic [7:0] xgmiiRxc;
logic [63:0] xgmiiRxd;

// generazione clocks
initial begin
    clk160 <= 0;
    clk20  <= 0;
    mem_clk   <= 0;
    c0_sys_clk_p <= 0;
    c0_sys_clk_n <= 0;
    c1_sys_clk_p <= 0;
    c1_sys_clk_n <= 0;
    end
    
// Clock generator
  always
  begin
    #1.666 mem_clk <= 1;
    #1.666 mem_clk <= 0;
  end
  
  always
  begin
    #25.00 clk20 <= 1;
    #25.00 clk20 <= 0;
  end
  
  always
  begin
    #3.125 clk160 <= 1;
    #3.125 clk160 <= 0;
  end
  
  always
  begin
    #2;
    c0_sys_clk_p <= 1;
    c0_sys_clk_n <= 0;
    #2;
    c0_sys_clk_p <= 0;
    c0_sys_clk_n <= 1;
 end;
 
  always
  begin
    #2;
    c1_sys_clk_p <= 1;
    c1_sys_clk_n <= 0;
    #2;
    c1_sys_clk_p <= 0;
    c1_sys_clk_n <= 1;
  end

default clocking clk @(posedge clk160);
endclocking


top #() top0 (
        .clk_x1(clk20),
        .clk_x8(clk160),
	.rst(extRst),

        .btnu(1'b0),
        .btnl(1'b0),
        .btnd(1'b0),
        .btnr(1'b0),
        .btnc(1'b0),
        .sw(4'd0),
	.led(),
	
	.xgmii_tx_clk(clk160),
        .xgmii_tx_rst(extRst),
        .xgmii_txd(xgmiiTxd),
        .xgmii_txc(xgmiiTxc),
        .xgmii_rx_clk(clk160),
        .xgmii_rx_rst(extRst),
        .xgmii_rxd(xgmiiRxd),
        .xgmii_rxc(xgmiiRxc)
);

int ret, pkt_count;
initial begin
	//$dumpfile("wave.vcd");
	//$dumpvars(0, top0);
        extRst = 1'b1;

	ret <= shared_mem_init();
	if (ret < 0) begin
		$display("pipe_init: open: ret < 0");
	end

	#5000;
        extRst = 1'b0;
	pkt_count = max_recvpkt;
	while(1) begin
		tap2xgmii(ret);
		if (ret == 1) begin
			if (!(--pkt_count)) begin
				break;
			end
		end
	        #5;
	end

	#10;
	$finish;
end

/*
 * xgmii_read
 */
reg ret_reg;
always @(posedge clk160) begin
	if (extRst) begin
		ret_reg <= 0;
	end else begin
		ret_reg <= xgmii_read(xgmiiTxd,xgmiiTxc);
	end
end


/*
 * xgmii_write
 * @data
 */
task xgmii_write(input longint data, input byte control);
	@(posedge clk160) begin
		xgmiiRxc <= control;
		xgmiiRxd <= data;
	end
endtask

/*
 * xgmii_idle
 */
task xgmii_idle;
	@(posedge clk160) begin
		xgmiiRxc <= 8'b11111111;
		xgmiiRxd <= 64'h0707070707070707;
	end
endtask

endmodule

`default_nettype wire

