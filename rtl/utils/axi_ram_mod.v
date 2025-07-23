/*

Copyright (c) 2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * AXI4 RAM
 */
module axi_ram_mod #
(
    // Width of data bus in bits
    parameter DATA_WIDTH = 32,
    // Width of address bus in bits
    parameter ADDR_WIDTH = 16,
    // Width of wstrb (width of data bus in words)
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    // Width of ID signal
    parameter ID_WIDTH = 8
)
(
    input  wire                   clk,
    input  wire                   rst,

    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awlock,
    input  wire [3:0]             s_axi_awcache,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,
    output wire [ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arlock,
    input  wire [3:0]             s_axi_arcache,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,
    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready
);

    parameter VALID_ADDR_WIDTH = ADDR_WIDTH - $clog2(STRB_WIDTH);
    parameter WORD_WIDTH = STRB_WIDTH;
    parameter WORD_SIZE = DATA_WIDTH/WORD_WIDTH;

    parameter BIGGEST_MEM_ADDR_WIDTH  = 14 + $clog2(STRB_WIDTH);
    parameter VALID_ADDR_WIDTH_SINGLE = (ADDR_WIDTH > BIGGEST_MEM_ADDR_WIDTH) ?  BIGGEST_MEM_ADDR_WIDTH - $clog2(STRB_WIDTH) : ADDR_WIDTH - $clog2(STRB_WIDTH);
    parameter N_RAMS                  = (ADDR_WIDTH > BIGGEST_MEM_ADDR_WIDTH) ?  2**(ADDR_WIDTH-BIGGEST_MEM_ADDR_WIDTH) : 1;
    parameter N_RAMS_WIDTH            = (ADDR_WIDTH > BIGGEST_MEM_ADDR_WIDTH) ?  ADDR_WIDTH-BIGGEST_MEM_ADDR_WIDTH : 1;

    // bus width assertions
    initial begin
        if (WORD_SIZE * STRB_WIDTH != DATA_WIDTH) begin
            $error("Error: AXI data width not evenly divisble (instance %m)");
            $finish;
        end

        if (2**$clog2(WORD_WIDTH) != WORD_WIDTH) begin
            $error("Error: AXI word width must be even power of two (instance %m)");
            $finish;
        end
    end

    localparam [0:0]
    READ_STATE_IDLE = 1'd0,
    READ_STATE_BURST = 1'd1;

    reg [0:0] read_state_reg = READ_STATE_IDLE, read_state_next;

    localparam [1:0]
    WRITE_STATE_IDLE = 2'd0,
    WRITE_STATE_BURST = 2'd1,
    WRITE_STATE_RESP = 2'd2;

    reg [1:0] write_state_reg = WRITE_STATE_IDLE, write_state_next;

    reg mem_wr_en;
    reg mem_rd_en;

    reg [ID_WIDTH-1:0] read_id_reg = {ID_WIDTH{1'b0}}, read_id_next;
    reg [ADDR_WIDTH-1:0] read_addr_reg = {ADDR_WIDTH{1'b0}}, read_addr_next;
    reg [7:0] read_count_reg = 8'd0, read_count_next;
    reg [2:0] read_size_reg = 3'd0, read_size_next;
    reg [1:0] read_burst_reg = 2'd0, read_burst_next;
    reg [ID_WIDTH-1:0] write_id_reg = {ID_WIDTH{1'b0}}, write_id_next;
    reg [ADDR_WIDTH-1:0] write_addr_reg = {ADDR_WIDTH{1'b0}}, write_addr_next;
    reg [7:0] write_count_reg = 8'd0, write_count_next;
    reg [2:0] write_size_reg = 3'd0, write_size_next;
    reg [1:0] write_burst_reg = 2'd0, write_burst_next;

    reg s_axi_awready_reg = 1'b0, s_axi_awready_next;
    reg s_axi_wready_reg = 1'b0, s_axi_wready_next;
    reg [ID_WIDTH-1:0] s_axi_bid_reg = {ID_WIDTH{1'b0}}, s_axi_bid_next;
    reg s_axi_bvalid_reg = 1'b0, s_axi_bvalid_next;
    reg s_axi_arready_reg = 1'b0, s_axi_arready_next;
    reg [ID_WIDTH-1:0] s_axi_rid_reg = {ID_WIDTH{1'b0}}, s_axi_rid_next;
    reg [DATA_WIDTH-1:0] s_axi_rdata_reg = {DATA_WIDTH{1'b0}}, s_axi_rdata_next;
    reg s_axi_rlast_reg = 1'b0, s_axi_rlast_next;
    reg s_axi_rvalid_reg = 1'b0, s_axi_rvalid_next;
    //reg [ID_WIDTH-1:0] s_axi_rid_pipe_reg = {ID_WIDTH{1'b0}};
    //reg [DATA_WIDTH-1:0] s_axi_rdata_pipe_reg = {DATA_WIDTH{1'b0}};
    //reg s_axi_rlast_pipe_reg = 1'b0;
    //reg s_axi_rvalid_pipe_reg = 1'b0;
    reg [ID_WIDTH-1:0] s_axi_rid_pipe_reg [1:0];
    reg [DATA_WIDTH-1:0] s_axi_rdata_pipe_reg [1:0];
    reg [1:0] s_axi_rlast_pipe_reg = 1'b0;
    reg [1:0] s_axi_rvalid_pipe_reg = 1'b0;


    wire [VALID_ADDR_WIDTH-1:0] s_axi_awaddr_valid = s_axi_awaddr >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
    wire [VALID_ADDR_WIDTH-1:0] s_axi_araddr_valid = s_axi_araddr >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
    wire [VALID_ADDR_WIDTH-1:0] read_addr_valid = read_addr_reg >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
    wire [VALID_ADDR_WIDTH-1:0] write_addr_valid = write_addr_reg >> (ADDR_WIDTH - VALID_ADDR_WIDTH);


    wire [DATA_WIDTH -1 : 0] ramout_single [N_RAMS-1:0];
    wire [DATA_WIDTH -1 : 0] ramout;
    wire [DATA_WIDTH -1 : 0] din;
    wire [STRB_WIDTH -1 : 0] strb;
    wire [VALID_ADDR_WIDTH_SINGLE -1 : 0] waddr;
    wire [VALID_ADDR_WIDTH_SINGLE -1 : 0] raddr;
    wire ena;
    wire ren [N_RAMS-1:0];
    wire wen [N_RAMS-1:0];

    reg [N_RAMS_WIDTH-1:0] ram_sel_shreg [2:0];

    // output logic
    reg                  temp_s_axi_rvalid_next, temp_s_axi_rvalid_reg;
    reg [DATA_WIDTH-1:0] temp_s_axi_rdata_reg;
    reg [ID_WIDTH  -1:0] temp_s_axi_rid_reg;
    reg                  temp_s_axi_rlast_reg;
    wire s_axi_rready_int_early;
    reg store_axi_int_to_output;
    reg store_axi_int_to_temp;
    reg store_axi_temp_to_output;

    reg  s_axi_rready_int_reg;
    wire s_axi_rvalid_int;
    wire [DATA_WIDTH-1:0] s_axi_rdata_int;
    wire [ID_WIDTH  -1:0] s_axi_rid_int;
    wire s_axi_rlast_int;

    reg                  s_axi_rvalid_next_out, s_axi_rvalid_reg_out;
    reg [DATA_WIDTH-1:0] s_axi_rdata_reg_out;
    reg [ID_WIDTH  -1:0] s_axi_rid_reg_out;
    reg                  s_axi_rlast_reg_out;

    integer i, j;

    assign s_axi_rvalid_int = s_axi_rvalid_pipe_reg[0];
    assign s_axi_rdata_int  = ramout;
    assign s_axi_rid_int    = s_axi_rid_pipe_reg[0];
    assign s_axi_rlast_int  = s_axi_rlast_pipe_reg[0];


    assign waddr = write_addr_valid[VALID_ADDR_WIDTH_SINGLE -1 : 0];
    assign raddr = read_addr_valid[VALID_ADDR_WIDTH_SINGLE -1 : 0];
    assign din   = s_axi_wdata;
    assign strb  = s_axi_wstrb;
    assign ena   = 1'b1;

    for(genvar k = 0; k < N_RAMS; k = k + 1) begin
        assign wen[k]   = mem_wr_en && (write_addr_valid >> VALID_ADDR_WIDTH_SINGLE == k);
        assign ren[k]   = mem_rd_en && (read_addr_valid  >> VALID_ADDR_WIDTH_SINGLE == k);

        simple_dpram #(
            .ADDR_WIDTH(VALID_ADDR_WIDTH_SINGLE),
            .DATA_WIDTH(DATA_WIDTH),
            .STRB_WIDTH(STRB_WIDTH),
            .NPIPES(0),
            .STYLE("ultra")
        ) test_ith_ram_instance (
            .clk(clk),
            .rst(rst),
            .waddr(waddr),
            .raddr(raddr),
            .din(din),
            .dout(ramout_single[k]),
            .strb(strb),
            .ena(ena),
            .ren(ren[k]),
            .wen(wen[k])
        );
    end

    always @(posedge clk) begin
        ram_sel_shreg[0] <= read_addr_valid >> VALID_ADDR_WIDTH_SINGLE;

        for(i = 1; i < 3; i = i + 1) begin
            ram_sel_shreg[i] <= ram_sel_shreg[i-1];
        end
    end

    assign ramout = ramout_single[ram_sel_shreg[1]];
    

    assign s_axi_awready = s_axi_awready_reg;
    assign s_axi_wready = s_axi_wready_reg;
    assign s_axi_bid = s_axi_bid_reg;
    assign s_axi_bresp = 2'b00;
    assign s_axi_bvalid = s_axi_bvalid_reg;
    assign s_axi_arready = s_axi_arready_reg;
    assign s_axi_rid    = s_axi_rid_reg_out;
    assign s_axi_rdata  = s_axi_rdata_reg_out;
    assign s_axi_rresp  = 2'b00;
    assign s_axi_rlast  = s_axi_rlast_reg_out;
    assign s_axi_rvalid = s_axi_rvalid_reg_out;

    initial begin
        for(i = 0; i < 2; i = i + 1) begin
            ram_sel_shreg[i] <= {N_RAMS_WIDTH{1'b0}};
        end
    end
    

    always @* begin
        write_state_next = WRITE_STATE_IDLE;

        mem_wr_en = 1'b0;

        write_id_next = write_id_reg;
        write_addr_next = write_addr_reg;
        write_count_next = write_count_reg;
        write_size_next = write_size_reg;
        write_burst_next = write_burst_reg;

        s_axi_awready_next = 1'b0;
        s_axi_wready_next = 1'b0;
        s_axi_bid_next = s_axi_bid_reg;
        s_axi_bvalid_next = s_axi_bvalid_reg && !s_axi_bready;

        case (write_state_reg)
            WRITE_STATE_IDLE: begin
                s_axi_awready_next = 1'b1;

                if (s_axi_awready && s_axi_awvalid) begin
                    write_id_next = s_axi_awid;
                    write_addr_next = s_axi_awaddr;
                    write_count_next = s_axi_awlen;
                    write_size_next = s_axi_awsize < $clog2(STRB_WIDTH) ? s_axi_awsize : $clog2(STRB_WIDTH);
                    write_burst_next = s_axi_awburst;

                    s_axi_awready_next = 1'b0;
                    s_axi_wready_next = 1'b1;
                    write_state_next = WRITE_STATE_BURST;
                end else begin
                    write_state_next = WRITE_STATE_IDLE;
                end
            end
            WRITE_STATE_BURST: begin
                s_axi_wready_next = 1'b1;

                if (s_axi_wready && s_axi_wvalid) begin
                    mem_wr_en = 1'b1;
                    if (write_burst_reg != 2'b00) begin
                        write_addr_next = write_addr_reg + (1 << write_size_reg);
                    end
                    write_count_next = write_count_reg - 1;
                    if (write_count_reg > 0) begin
                        write_state_next = WRITE_STATE_BURST;
                    end else begin
                        s_axi_wready_next = 1'b0;
                        if (s_axi_bready || !s_axi_bvalid) begin
                            s_axi_bid_next = write_id_reg;
                            s_axi_bvalid_next = 1'b1;
                            s_axi_awready_next = 1'b1;
                            write_state_next = WRITE_STATE_IDLE;
                        end else begin
                            write_state_next = WRITE_STATE_RESP;
                        end
                    end
                end else begin
                    write_state_next = WRITE_STATE_BURST;
                end
            end
            WRITE_STATE_RESP: begin
                if (s_axi_bready || !s_axi_bvalid) begin
                    s_axi_bid_next = write_id_reg;
                    s_axi_bvalid_next = 1'b1;
                    s_axi_awready_next = 1'b1;
                    write_state_next = WRITE_STATE_IDLE;
                end else begin
                    write_state_next = WRITE_STATE_RESP;
                end
            end
        endcase
    end

    always @(posedge clk) begin
        write_state_reg <= write_state_next;

        write_id_reg <= write_id_next;
        write_addr_reg <= write_addr_next;
        write_count_reg <= write_count_next;
        write_size_reg <= write_size_next;
        write_burst_reg <= write_burst_next;

        s_axi_awready_reg <= s_axi_awready_next;
        s_axi_wready_reg <= s_axi_wready_next;
        s_axi_bid_reg <= s_axi_bid_next;
        s_axi_bvalid_reg <= s_axi_bvalid_next;

        if (rst) begin
            write_state_reg <= WRITE_STATE_IDLE;

            s_axi_awready_reg <= 1'b0;
            s_axi_wready_reg <= 1'b0;
            s_axi_bvalid_reg <= 1'b0;
        end
    end

    always @* begin
        read_state_next = READ_STATE_IDLE;

        mem_rd_en = 1'b0;

        s_axi_rid_next = s_axi_rid_reg;
        s_axi_rlast_next = s_axi_rlast_reg;
        s_axi_rvalid_next = s_axi_rvalid_reg && !(s_axi_rready || !s_axi_rvalid_pipe_reg[0]);

        read_id_next = read_id_reg;
        read_addr_next = read_addr_reg;
        read_count_next = read_count_reg;
        read_size_next = read_size_reg;
        read_burst_next = read_burst_reg;

        s_axi_arready_next = 1'b0;

        case (read_state_reg)
            READ_STATE_IDLE: begin
                s_axi_arready_next = 1'b1;

                if (s_axi_arready && s_axi_arvalid) begin
                    read_id_next = s_axi_arid;
                    read_addr_next = s_axi_araddr;
                    read_count_next = s_axi_arlen;
                    read_size_next = s_axi_arsize < $clog2(STRB_WIDTH) ? s_axi_arsize : $clog2(STRB_WIDTH);
                    read_burst_next = s_axi_arburst;

                    s_axi_arready_next = 1'b0;
                    read_state_next = READ_STATE_BURST;
                end else begin
                    read_state_next = READ_STATE_IDLE;
                end
            end
            READ_STATE_BURST: begin
                if (s_axi_rready || (!s_axi_rvalid_pipe_reg[0]) || !s_axi_rvalid_reg) begin
                    mem_rd_en = 1'b1;
                    s_axi_rvalid_next = 1'b1;
                    s_axi_rid_next = read_id_reg;
                    s_axi_rlast_next = read_count_reg == 0;
                    if (read_burst_reg != 2'b00) begin
                        read_addr_next = read_addr_reg + (1 << read_size_reg);
                    end
                    read_count_next = read_count_reg - 1;
                    if (read_count_reg > 0) begin
                        read_state_next = READ_STATE_BURST;
                    end else begin
                        s_axi_arready_next = 1'b1;
                        read_state_next = READ_STATE_IDLE;
                    end
                end else begin
                    read_state_next = READ_STATE_BURST;
                end
            end
        endcase
    end

    always @(posedge clk) begin
        read_state_reg <= read_state_next;

        read_id_reg    <= read_id_next;
        read_addr_reg  <= read_addr_next;
        read_count_reg <= read_count_next;
        read_size_reg  <= read_size_next;
        read_burst_reg <= read_burst_next;

        s_axi_arready_reg <= s_axi_arready_next;
        s_axi_rid_reg     <= s_axi_rid_next;
        s_axi_rlast_reg   <= s_axi_rlast_next;
        s_axi_rvalid_reg  <= s_axi_rvalid_next;

        s_axi_rid_pipe_reg[0]       <= s_axi_rid_reg;
        s_axi_rlast_pipe_reg[0]     <= s_axi_rlast_reg;
        s_axi_rvalid_pipe_reg[0]    <= s_axi_rvalid_reg;


        if (rst) begin
            read_state_reg <= READ_STATE_IDLE;

            s_axi_arready_reg <= 1'b0;
            s_axi_rvalid_reg <= 1'b0;
            s_axi_rvalid_pipe_reg <= 2'b00;
        end
    end

    always @* begin
        s_axi_rdata_reg = ramout;
    end

    


    // enable ready input next cycle if output is ready or if both output registers are empty
    assign s_axi_rready_int_early = s_axi_rready || (!temp_s_axi_rvalid_reg && !s_axi_rvalid_reg_out);
    // enable ready input next cycle if output is ready or the temp reg will not be filled on the next cycle (output reg empty or no input)

    always @* begin
        // transfer sink ready state to source
        s_axi_rvalid_next_out  = s_axi_rvalid_reg_out;
        temp_s_axi_rvalid_next = temp_s_axi_rvalid_reg;

        store_axi_int_to_output = 1'b0;
        store_axi_int_to_temp = 1'b0;
        store_axi_temp_to_output = 1'b0;

        if (s_axi_rready_int_reg) begin
            // input is ready
            if (s_axi_rready || !s_axi_rvalid_reg_out) begin
                // output is ready or currently not valid, transfer data to output
                s_axi_rvalid_next_out = s_axi_rvalid_int;
                store_axi_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_s_axi_rvalid_next = s_axi_rvalid_int;
                store_axi_int_to_temp  = 1'b1;
            end
        end else if (s_axi_rready) begin
            // input is not ready, but output is ready
            s_axi_rvalid_next_out = temp_s_axi_rvalid_reg;
            temp_s_axi_rvalid_next = 1'b0;
            store_axi_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        s_axi_rvalid_reg_out <= s_axi_rvalid_next_out;
        s_axi_rready_int_reg <= s_axi_rready_int_early;
        temp_s_axi_rvalid_reg <= temp_s_axi_rvalid_next;

        // datapath
        if (store_axi_int_to_output) begin
            s_axi_rdata_reg_out <= s_axi_rdata_int;
            s_axi_rid_reg_out   <= s_axi_rid_int;
            s_axi_rlast_reg_out <= s_axi_rlast_int;


        end else if (store_axi_temp_to_output) begin
            s_axi_rdata_reg_out <= temp_s_axi_rdata_reg;
            s_axi_rid_reg_out   <= temp_s_axi_rid_reg;
            s_axi_rlast_reg_out <= temp_s_axi_rlast_reg;

        end

        if (store_axi_int_to_temp) begin
            temp_s_axi_rdata_reg <= s_axi_rdata_int;
            temp_s_axi_rid_reg   <= s_axi_rid_int;
            temp_s_axi_rlast_reg <= s_axi_rlast_int;

        end

        if (rst) begin
            s_axi_rvalid_reg_out <= 1'b0;
            s_axi_rready_int_reg <= 1'b0;
            temp_s_axi_rvalid_reg <= 1'b0;
        end
    end

endmodule

`resetall