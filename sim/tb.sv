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

    // Simulation MAC speed
    // 64b Simulation MAC datapath width
    // either 25G or 10G (390.625MHz or 156.25MHz)
    parameter SIM_MAC_SPEED = 10; // in Gbps
    parameter SIM_MAC_DATAPATH_WIDTH = 64; //dont change! 
    parameter SIM_MAC_FREQ = SIM_MAC_SPEED*1000.0/SIM_MAC_DATAPATH_WIDTH; //in MHz 

    // MAC to simulate
    parameter MAC_SPEED = 100;
    parameter MAC_DATAPATH_WIDTH = 512;
    parameter MAC_FREQ = MAC_SPEED*1000.0/MAC_DATAPATH_WIDTH; //in MHz 

    // stack to simulate, with effective throughput, 
    parameter STACK_DATAPATH_WIDTH = 512;
    parameter STACK_FREQ  = 322.622;
    parameter STACK_SPEED = STACK_DATAPATH_WIDTH*STACK_FREQ/1000.0;

    // now we need do reduce/increase the mac frequency to match the speed of the simulation MAC
    // eg for a 100G MAC it has to go 10 times slower than the sim MAC
    localparam SCALE_UP_FACT       = MAC_SPEED/SIM_MAC_SPEED;

    parameter MAC_FREQ_REAL   = MAC_FREQ/SCALE_UP_FACT;
    parameter STACK_FREQ_REAL = STACK_FREQ/SCALE_UP_FACT;

    // in ns
    parameter SIM_MAC_PERIOD      = 1000/SIM_MAC_FREQ;
    parameter MAC_PERIOD      = 1000/MAC_FREQ_REAL;
    parameter STACK_PERIOD    = 1000/STACK_FREQ_REAL;

    logic clk_mac_sim, clk_mac, clk_stack;
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
        clk_mac_sim <= 0;
        clk_mac <= 0;
        clk_stack  <= 0;
        c0_sys_clk_p <= 0;
        c0_sys_clk_n <= 0;
        c1_sys_clk_p <= 0;
        c1_sys_clk_n <= 0;
    end

    // Clock generator
    always
    begin
        #(SIM_MAC_PERIOD/2) clk_mac_sim <= 1;
        #(SIM_MAC_PERIOD/2) clk_mac_sim <= 0;
    end

    always
    begin
        #(MAC_PERIOD/2) clk_mac <= 1;
        #(MAC_PERIOD/2) clk_mac <= 0 ;
    end

    always
    begin
        #(STACK_PERIOD/2) clk_stack <= 1;
        #(STACK_PERIOD/2) clk_stack <= 0;
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
        .MAC_DATA_WIDTH(MAC_DATAPATH_WIDTH),
        .STACK_DATA_WIDTH(STACK_DATAPATH_WIDTH)
    ) top0 (
        .clk_mac_sim(clk_mac_sim),
        .clk_mac(clk_mac),
        .clk_stack(clk_stack),
        .rst(extRst),

        .clk_mem(clk_mac),
        .rst_mem(clk_mac),

        .xgmii_tx_clk(clk_mac_sim),
        .xgmii_tx_rst(extRst),
        .xgmii_txd(xgmiiTxd),
        .xgmii_txc(xgmiiTxc),
        .xgmii_rx_clk(clk_mac_sim),
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
    always @(posedge clk_mac_sim) begin
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
        @(posedge clk_mac_sim) begin
            xgmiiRxc <= control;
            xgmiiRxd <= data;
        end
    endtask

    /*
     * xgmii_idle
     */
    task xgmii_idle;
        @(posedge clk_mac_sim) begin
            xgmiiRxc <= 8'b11111111;
            xgmiiRxd <= 64'h0707070707070707;
        end
    endtask

endmodule

`default_nettype wire

