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

parameter MAC_DATA_WIDTH = 1024;
parameter RoCE_DATA_WIDTH = 2048;

localparam SCALE_UP_FACT = MAC_DATA_WIDTH/64;

parameter MAC_FREQ      = 390.625_000;
parameter UDP_IP_FREQ   = 276/SCALE_UP_FACT;
parameter ROCE_FREQ     = 276/SCALE_UP_FACT;
parameter AXI_SEG_FREQ  = 398.66/SCALE_UP_FACT;
parameter AXI_SEG_FREQ_09 = 390.625_000/SCALE_UP_FACT;

parameter MAC_PERIOD      = 1000/MAC_FREQ;
parameter UDP_IP_PERIOD   = 1000/UDP_IP_FREQ;
parameter ROCE_PERIOD     = 1000/ROCE_FREQ;
parameter AXI_SEG_PERIOD  = 1000/AXI_SEG_FREQ;
parameter AXI_SEG_PERIOD_09 = 1000/AXI_SEG_FREQ_09;

logic clk_mac, clk_udp, clk_roce, clk_axi_seg, clk_axi_seg_09;
logic extRst;
logic clk25;
logic rst25;
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
    clk_mac <= 0;
    clk_udp  <= 0;
    clk_roce  <= 0;
    clk_axi_seg  <= 0;
    clk_axi_seg_09 <= 0;
    c0_sys_clk_p <= 0;
    c0_sys_clk_n <= 0;
    c1_sys_clk_p <= 0;
    c1_sys_clk_n <= 0;
    end
    
// Clock generator
  always
  begin
    #(MAC_PERIOD/2) clk_mac <= 1;
    #(MAC_PERIOD/2) clk_mac <= 0;
  end
  
  always
  begin
    #(UDP_IP_PERIOD/2) clk_udp <= 1;
    #(UDP_IP_PERIOD/2) clk_udp <= 0;
  end
  
  always
  begin
    #(ROCE_PERIOD/2) clk_roce <= 1;
    #(ROCE_PERIOD/2) clk_roce <= 0;
  end
  
  always
  begin
    #(AXI_SEG_PERIOD/2) clk_axi_seg <= 1;
    #(AXI_SEG_PERIOD/2) clk_axi_seg <= 0;
  end
  
  always
  begin
    #(AXI_SEG_PERIOD_09/2) clk_axi_seg_09 <= 1;
    #(AXI_SEG_PERIOD_09/2) clk_axi_seg_09 <= 0;
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

default clocking clk @(posedge clk_mac);
endclocking


top #(
	.MAC_DATA_WIDTH(MAC_DATA_WIDTH),
	.RoCE_DATA_WIDTH(RoCE_DATA_WIDTH)
) top0 (
        .clk_mac(clk_mac),
        .clk_udp(clk_udp),
        .clk_roce(clk_roce),
        .clk_axi_seg(clk_axi_seg),
        .clk_axi_seg_09(clk_axi_seg_09),
	.rst(extRst),
	
	.clk_mem(clk_mac),
	.rst_mem(clk_mac),

        .btnu(1'b0),
        .btnl(1'b0),
        .btnd(1'b0),
        .btnr(1'b0),
        .btnc(1'b0),
        .sw(4'd0),
	.led(),
	
	.xgmii_tx_clk(clk_mac),
        .xgmii_tx_rst(extRst),
        .xgmii_txd(xgmiiTxd),
        .xgmii_txc(xgmiiTxc),
        .xgmii_rx_clk(clk_mac),
        .xgmii_rx_rst(extRst),
        .xgmii_rxd(xgmiiRxd),
        .xgmii_rxc(xgmiiRxc)
);

int ret, pkt_count;
initial begin
	//$dumpfile("wave.vcd");
	//$dumpvars(0, top0);
        extRst = 1'b1;
        rst25 = 1'b1;

	ret <= shared_mem_init();
	if (ret < 0) begin
		$display("pipe_init: open: ret < 0");
	end

	#5000;
        extRst = 1'b0;
        rst25 = 1'b0;
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
always @(posedge clk_mac) begin
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
	@(posedge clk_mac) begin
		xgmiiRxc <= control;
		xgmiiRxd <= data;
	end
endtask

/*
 * xgmii_idle
 */
task xgmii_idle;
	@(posedge clk_mac) begin
		xgmiiRxc <= 8'b11111111;
		xgmiiRxd <= 64'h0707070707070707;
	end
endtask

endmodule

`default_nettype wire

