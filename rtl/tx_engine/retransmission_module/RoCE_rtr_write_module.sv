`resetall `timescale 1ns / 1ps `default_nettype none


module RoCE_rtr_write_module #(
    parameter DATA_WIDTH = 64,
    parameter BUFFER_ADDR_WIDTH = 24,
    parameter HEADER_ADDR_WIDTH = BUFFER_ADDR_WIDTH - 8,
    parameter MAX_QPS = 4
) (
    input wire clk,
    input wire rst,
    /*
     * RoCE TX frame input
     */
    // BTH
    input  wire         s_roce_bth_valid,
    output wire         s_roce_bth_ready,
    input  wire [  7:0] s_roce_bth_op_code,
    input  wire [ 15:0] s_roce_bth_p_key,
    input  wire [ 23:0] s_roce_bth_psn,
    input  wire [ 23:0] s_roce_bth_dest_qp,
    input  wire [ 23:0] s_roce_bth_src_qp,
    input  wire         s_roce_bth_ack_req,
    // RETH
    input  wire         s_roce_reth_valid,
    output wire         s_roce_reth_ready,
    input  wire [ 63:0] s_roce_reth_v_addr,
    input  wire [ 31:0] s_roce_reth_r_key,
    input  wire [ 31:0] s_roce_reth_length,
    // IMMD
    input  wire         s_roce_immdh_valid,
    output wire         s_roce_immdh_ready,
    input  wire [ 31:0] s_roce_immdh_data,
    // udp, ip, eth
    input  wire [ 47:0] s_eth_dest_mac,
    input  wire [ 47:0] s_eth_src_mac,
    input  wire [ 15:0] s_eth_type,
    input  wire [  3:0] s_ip_version,
    input  wire [  3:0] s_ip_ihl,
    input  wire [  5:0] s_ip_dscp,
    input  wire [  1:0] s_ip_ecn,
    input  wire [ 15:0] s_ip_identification,
    input  wire [  2:0] s_ip_flags,
    input  wire [ 12:0] s_ip_fragment_offset,
    input  wire [  7:0] s_ip_ttl,
    input  wire [  7:0] s_ip_protocol,
    input  wire [ 15:0] s_ip_header_checksum,
    input  wire [ 31:0] s_ip_source_ip,
    input  wire [ 31:0] s_ip_dest_ip,
    input  wire [ 15:0] s_udp_source_port,
    input  wire [ 15:0] s_udp_dest_port,
    input  wire [ 15:0] s_udp_length,
    input  wire [ 15:0] s_udp_checksum,
    // payload
    input  wire [DATA_WIDTH   - 1 :0] s_roce_payload_axis_tdata,
    input  wire [DATA_WIDTH/8 - 1 :0] s_roce_payload_axis_tkeep,
    input  wire                       s_roce_payload_axis_tvalid,
    output wire                       s_roce_payload_axis_tready,
    input  wire                       s_roce_payload_axis_tlast,
    input  wire                       s_roce_payload_axis_tuser,

    /*
     * DMA Write command
     */
    output wire [BUFFER_ADDR_WIDTH-1:0] m_axis_dma_write_desc_addr,
    output wire [12:0]                  m_axis_dma_write_desc_len,
    output wire                         m_axis_dma_write_desc_valid,
    input wire                          m_axis_dma_write_desc_ready,
    /*
     * DMA Write status
     */
    input wire [12:0]                  s_axis_dma_write_desc_status_len,
    input wire [3 :0]                  s_axis_dma_write_desc_status_error,
    input wire                         s_axis_dma_write_desc_status_valid,
    // DMA write payload
    output  wire [DATA_WIDTH   - 1 :0] m_dma_write_axis_tdata,
    output  wire [DATA_WIDTH/8 - 1 :0] m_dma_write_axis_tkeep,
    output  wire                       m_dma_write_axis_tvalid,
    input   wire                       m_dma_write_axis_tready,
    output  wire                       m_dma_write_axis_tlast,
    output  wire                       m_dma_write_axis_tuser,

    /*HEADER RAM write */
    output wire                         hdr_ram_we,
    output wire [HEADER_ADDR_WIDTH-1:0] hdr_ram_addr,
    output wire [175:0]                 hdr_ram_data,
    /*
    Write table interface, update when succesfully write to mem
    */
    output wire                       m_wr_table_we,
    output wire [$clog2(MAX_QPS)-1:0] m_wr_table_qpn, // used as address
    output wire [24-1:0]              m_wr_table_psn,
    /*
    Close QP input, when a qp is close flush whatever is left in the queue
    */
    input wire        s_qp_close_valid,
    input wire [23:0] s_qp_close_loc_qpn,
    /*
    Qpen QP input, needed to reset flush reg
    */
    input wire        s_qp_open_valid,
    input wire [23:0] s_qp_open_loc_qpn,
    /*
    Status
    */
    output wire mem_full,
    /*
    Configuration
    */
    input wire [2 :0] pmtu
);

    import RoCE_params::*; // Imports RoCE parameters

    localparam RAM_OP_CODE_OFFSET   = 0;
    localparam RAM_PSN_OFFSET       = RAM_OP_CODE_OFFSET   + 8;
    localparam RAM_VADDR_OFFSET     = RAM_PSN_OFFSET       + 24;
    localparam RAM_RETH_LEN_OFFSET  = RAM_VADDR_OFFSET     + 64;
    localparam RAM_IMMD_DATA_OFFSET = RAM_RETH_LEN_OFFSET  + 32;
    localparam RAM_UDP_LEN_OFFSET   = RAM_IMMD_DATA_OFFSET + 32;
    localparam HEADER_MEMORY_SIZE   = RAM_UDP_LEN_OFFSET + 16; // in bits

    localparam [2:0]
    STATE_IDLE           = 3'd0,
    STATE_DMA_WAIT_READY = 3'd1,
    STATE_DMA_WRITE      = 3'd2;

    reg [2:0] state_reg = STATE_IDLE, state_next;

    reg [3:0] memory_steps;
    reg [12:0] pmtu_val;

    reg s_roce_bth_ready_reg, s_roce_bth_ready_next;

    reg [BUFFER_ADDR_WIDTH-1:0] dma_write_desc_addr_reg, dma_write_desc_addr_next;
    reg [12:0]                  dma_write_desc_len_reg, dma_write_desc_len_next;
    reg                         dma_write_desc_valid_reg, dma_write_desc_valid_next;
    wire                        dma_write_desc_ready;

    reg                            hdr_ram_we_reg, hdr_ram_we_next;
    reg [HEADER_ADDR_WIDTH - 1: 0] hdr_ram_addr_reg, hdr_ram_addr_next;
    reg [175 :0]                   hdr_ram_data_in_reg, hdr_ram_data_in_next;


    wire                      wr_table_fifo_ready;
    reg                       wr_table_valid_reg, wr_table_valid_next;
    reg [24-1:0]              wr_table_psn_reg, wr_table_psn_next;
    reg [$clog2(MAX_QPS)-1:0] wr_table_qpn_reg, wr_table_qpn_next;

    reg                       m_wr_table_valid_reg;
    reg [24-1:0]              m_wr_table_psn_reg;
    reg [$clog2(MAX_QPS)-1:0] m_wr_table_qpn_reg;



    wire s_qp_close_fifo_valid;
    wire [23:0] s_qp_close_fifo_loc_qpn;

    reg [MAX_QPS-1:0]  qp_flush_reg;
    reg [MAX_QPS-1:0]  qp_close_reg;

    wire wr_table_fifo_out_valid;
    wire [$clog2(MAX_QPS)-1:0] wr_table_fifo_out_qpn;
    wire [23:0]                wr_table_fifo_out_psn;

    always @(posedge clk) begin
        memory_steps <= 4'd8 + pmtu;
        pmtu_val     <= 13'd1 << ( pmtu + 13'd8);
    end


    /* Create the DMA write descriptor, addr and len basically
    Addr is computed with the loc qpn and the psn (might add a translate table somewhere)
    */
    always @(*) begin
        state_next = STATE_IDLE;

        s_roce_bth_ready_next = 1'b0;

        dma_write_desc_addr_next = dma_write_desc_addr_reg;
        dma_write_desc_len_next  = dma_write_desc_len_reg;

        dma_write_desc_valid_next = dma_write_desc_valid_reg && !dma_write_desc_ready;

        wr_table_valid_next = wr_table_valid_reg && !wr_table_fifo_ready;
        wr_table_psn_next   = wr_table_psn_reg;
        wr_table_qpn_next   = wr_table_qpn_reg;


        hdr_ram_we_next = 1'b0;
        hdr_ram_addr_next  = hdr_ram_addr_reg;
        hdr_ram_data_in_next   = hdr_ram_data_in_reg;

        case(state_reg)
            STATE_IDLE : begin
                s_roce_bth_ready_next               = 1'b1;

                if (s_roce_bth_valid && s_roce_bth_ready) begin
                    s_roce_bth_ready_next               = 1'b0;


                    if (dma_write_desc_ready) begin
                        //state_next                = STATE_DMA_WRITE;
                        state_next                = STATE_IDLE;
                    end else begin
                        state_next                = STATE_DMA_WAIT_READY;
                    end
                    dma_write_desc_valid_next = 1'b1;
                    dma_write_desc_addr_next[BUFFER_ADDR_WIDTH-$clog2(MAX_QPS)-1:0]  =  (s_roce_bth_psn << memory_steps);
                    dma_write_desc_addr_next[BUFFER_ADDR_WIDTH-1 -: $clog2(MAX_QPS)] =  s_roce_bth_src_qp[$clog2(MAX_QPS)-1:0];

                    // if qp need to be flushed, write to mem, but don't update WR pointer
                    wr_table_valid_next = !qp_flush_reg[s_roce_bth_src_qp[$clog2(MAX_QPS)-1:0]];
                    wr_table_psn_next   = s_roce_bth_psn;
                    wr_table_qpn_next   = s_roce_bth_src_qp;

                    hdr_ram_we_next = 1'b1;
                    hdr_ram_addr_next[HEADER_ADDR_WIDTH-$clog2(MAX_QPS)-1:0]  = s_roce_bth_psn[HEADER_ADDR_WIDTH-$clog2(MAX_QPS)-1:0];
                    hdr_ram_addr_next[HEADER_ADDR_WIDTH-1 -: $clog2(MAX_QPS)] = s_roce_bth_src_qp[$clog2(MAX_QPS)-1:0];

                    hdr_ram_data_in_next[RAM_OP_CODE_OFFSET+:8]   = s_roce_bth_op_code;
                    hdr_ram_data_in_next[RAM_PSN_OFFSET+:24]      = s_roce_bth_psn;
                    // RETH Fields
                    hdr_ram_data_in_next[RAM_VADDR_OFFSET+:64]    = s_roce_reth_v_addr;
                    hdr_ram_data_in_next[RAM_RETH_LEN_OFFSET+:32] = s_roce_reth_length;
                    // Immdh field
                    hdr_ram_data_in_next[RAM_IMMD_DATA_OFFSET+:32] = s_roce_immdh_data;
                    // UDP length
                    hdr_ram_data_in_next[RAM_UDP_LEN_OFFSET+:16]   = s_udp_length;

                    if (~s_roce_reth_valid && ~s_roce_immdh_valid) begin
                        dma_write_desc_len_next  =  s_udp_length - 12 - 8; // UDP length - BTH - UDP HEADER 
                    end else if (s_roce_immdh_valid && s_roce_immdh_ready && ~s_roce_reth_valid ) begin
                        dma_write_desc_len_next  =  s_udp_length - 12 - 4 - 8; // UDP length - BTH - IMMD - UDP HEADER 
                    end else if (s_roce_reth_valid &&  s_roce_reth_ready && ~s_roce_immdh_valid) begin
                        dma_write_desc_len_next  =  s_udp_length - 12 - 16 - 8; // UDP length - BTH - RETH - UDP HEADER 
                    end else if (s_roce_reth_valid && s_roce_reth_ready & s_roce_immdh_valid & s_roce_immdh_ready) begin
                        dma_write_desc_len_next  =  s_udp_length - 12 - 16 - 4 - 8; // UDP length - BTH - RETH - IMMD - UDP HEADER
                    end else  begin // what happend here??
                        dma_write_desc_valid_next = 1'b0;
                        wr_table_valid_next       = 1'b0;
                        hdr_ram_we_next           = 1'b0;
                        state_next                = STATE_IDLE;
                    end
                end
            end
            STATE_DMA_WAIT_READY: begin
                s_roce_bth_ready_next               = 1'b0;
                if (dma_write_desc_ready) begin
                    //state_next                = STATE_DMA_WRITE;
                    state_next                = STATE_IDLE;
                end else begin
                    state_next                = STATE_DMA_WAIT_READY;
                end
            end
            //STATE_DMA_WRITE : begin
            //    if (s_roce_payload_axis_tvalid && s_roce_payload_axis_tlast && s_roce_payload_axis_tready) begin // end of transfer
            //        state_next = STATE_IDLE;
            //    end else begin
            //        state_next = STATE_DMA_WRITE;
            //    end
            //end
            default : begin
                state_next                = STATE_IDLE;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state_reg <= STATE_IDLE;

            s_roce_bth_ready_reg    <= 1'b0;

            dma_write_desc_addr_reg  <= 'd0;
            dma_write_desc_len_reg   <= 13'd0;
            dma_write_desc_valid_reg <= 1'b0;

            wr_table_valid_reg <= 1'b0;
            wr_table_psn_reg   <= 24'd0;
            wr_table_qpn_reg   <= 'd0;

            hdr_ram_we_reg    <= 1'b0;
            hdr_ram_addr_reg  <= 'd0;
            hdr_ram_data_in_reg   <= 'd0;

            qp_close_reg <= 'd0;
            qp_flush_reg <= 'd0;

            m_wr_table_valid_reg <= 1'b0;
            m_wr_table_qpn_reg   <= 'd0;
            m_wr_table_psn_reg   <= 24'd0;
        end else begin

            state_reg <= state_next;

            s_roce_bth_ready_reg    <= s_roce_bth_ready_next;

            dma_write_desc_addr_reg  <= dma_write_desc_addr_next;
            dma_write_desc_len_reg   <= dma_write_desc_len_next;
            dma_write_desc_valid_reg <= dma_write_desc_valid_next;

            wr_table_valid_reg <= wr_table_valid_next;
            wr_table_psn_reg   <= wr_table_psn_next;
            wr_table_qpn_reg   <= wr_table_qpn_next;

            hdr_ram_we_reg      <= hdr_ram_we_next;
            hdr_ram_addr_reg    <= hdr_ram_addr_next;
            hdr_ram_data_in_reg <= hdr_ram_data_in_next;

            // check if there was a close qp signal
            if (s_qp_close_valid) begin
                if (s_qp_close_loc_qpn - 256 < MAX_QPS) begin
                    qp_close_reg[s_qp_close_loc_qpn[$clog2(MAX_QPS)-1:0]] <= 1'b1;
                    qp_flush_reg[s_qp_close_loc_qpn[$clog2(MAX_QPS)-1:0]] <= 1'b1;
                end
            end else if (s_qp_open_valid) begin
                if (s_qp_open_loc_qpn - 256 < MAX_QPS) begin
                    qp_close_reg[s_qp_close_loc_qpn[$clog2(MAX_QPS)-1:0]] <= 1'b0;
                    qp_flush_reg[s_qp_close_loc_qpn[$clog2(MAX_QPS)-1:0]] <= 1'b0;
                end
            end

            if (wr_table_fifo_out_valid && s_axis_dma_write_desc_status_valid && (s_axis_dma_write_desc_status_error == 0)) begin
                if (qp_flush_reg[wr_table_fifo_out_qpn]) begin
                    m_wr_table_valid_reg <= 1'b0;
                    m_wr_table_qpn_reg   <= wr_table_fifo_out_qpn;
                    m_wr_table_psn_reg   <= wr_table_fifo_out_psn;
                end else begin
                    m_wr_table_valid_reg <= 1'b1;
                    m_wr_table_qpn_reg   <= wr_table_fifo_out_qpn;
                    m_wr_table_psn_reg   <= wr_table_fifo_out_psn;
                end
            end else begin
                m_wr_table_valid_reg <= 1'b0;
                m_wr_table_qpn_reg   <= 'd0;
                m_wr_table_psn_reg   <= 24'd0;
            end


        end
    end

    /*
    axis_fifo #(
        .DEPTH((DATA_WIDTH/8)*8), // 8 frames
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH(DATA_WIDTH/8),
        .ID_ENABLE(0),
        .DEST_ENABLE(0),
        .USER_ENABLE(1),
        .USER_WIDTH(1),
        .FRAME_FIFO(0)
    ) dma_write_payload_axis_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata (s_roce_payload_axis_tdata),
        .s_axis_tkeep (s_roce_payload_axis_tkeep),
        .s_axis_tvalid(s_roce_payload_axis_tvalid),
        .s_axis_tready(s_roce_payload_axis_tready),
        .s_axis_tlast (s_roce_payload_axis_tlast),
        .s_axis_tuser (s_roce_payload_axis_tuser),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata (m_dma_write_axis_tdata),
        .m_axis_tkeep (m_dma_write_axis_tkeep),
        .m_axis_tvalid(m_dma_write_axis_tvalid),
        .m_axis_tready(m_dma_write_axis_tready),
        .m_axis_tlast (m_dma_write_axis_tlast),
        .m_axis_tuser (m_dma_write_axis_tuser),

        // Status
        .status_overflow  (),
        .status_bad_frame (),
        .status_good_frame()
    );
    */
    assign m_dma_write_axis_tdata     = s_roce_payload_axis_tdata;
    assign m_dma_write_axis_tkeep     = s_roce_payload_axis_tkeep;
    assign m_dma_write_axis_tvalid    = s_roce_payload_axis_tvalid;
    assign s_roce_payload_axis_tready = m_dma_write_axis_tready; 
    assign m_dma_write_axis_tlast     = s_roce_payload_axis_tlast;
    assign m_dma_write_axis_tuser     = s_roce_payload_axis_tuser;

    axis_fifo #(
        .DEPTH(8),
        .DATA_WIDTH(BUFFER_ADDR_WIDTH+13),
        .KEEP_ENABLE(0),
        .LAST_ENABLE(0),
        .ID_ENABLE  (0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0)
    ) dma_write_command_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata ({dma_write_desc_addr_reg,dma_write_desc_len_reg}),
        .s_axis_tvalid(dma_write_desc_valid_reg),
        .s_axis_tready(dma_write_desc_ready),
        .s_axis_tuser (0),
        .s_axis_tkeep (0),
        .s_axis_tlast (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata ({m_axis_dma_write_desc_addr, m_axis_dma_write_desc_len}),
        .m_axis_tvalid(m_axis_dma_write_desc_valid),
        .m_axis_tready(m_axis_dma_write_desc_ready),

        // Status
        .status_overflow  (),
        .status_bad_frame (),
        .status_good_frame()
    );

    axis_fifo #(
        .DEPTH(8),
        .DATA_WIDTH($clog2(MAX_QPS)+24), // qpn and psn
        .KEEP_ENABLE(0),
        .LAST_ENABLE(0),
        .ID_ENABLE  (0),
        .DEST_ENABLE(0),
        .USER_ENABLE(0)
    ) write_table_entry_fifo (
        .clk(clk),
        .rst(rst),

        // AXI input
        .s_axis_tdata ({wr_table_qpn_reg, wr_table_psn_reg}),
        .s_axis_tvalid(wr_table_valid_reg),
        .s_axis_tready(wr_table_fifo_ready),
        .s_axis_tuser (0),
        .s_axis_tkeep (0),
        .s_axis_tlast (0),
        .s_axis_tid   (0),
        .s_axis_tdest (0),

        // AXI output
        .m_axis_tdata ({wr_table_fifo_out_qpn, wr_table_fifo_out_psn}),
        .m_axis_tvalid(wr_table_fifo_out_valid),
        .m_axis_tready(s_axis_dma_write_desc_status_valid),

        // Status
        .status_overflow  (),
        .status_bad_frame (),
        .status_good_frame()
    );

    assign s_roce_bth_ready   = s_roce_bth_ready_reg;
    assign s_roce_reth_ready  = s_roce_bth_ready_reg;
    assign s_roce_immdh_ready = s_roce_bth_ready_reg;

    assign m_wr_table_we  = m_wr_table_valid_reg;
    assign m_wr_table_qpn = m_wr_table_qpn_reg;
    assign m_wr_table_psn = m_wr_table_psn_reg;

    assign hdr_ram_we   = hdr_ram_we_reg;
    assign hdr_ram_addr = hdr_ram_addr_reg;
    assign hdr_ram_data = hdr_ram_data_in_reg;

endmodule

`resetall