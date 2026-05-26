`timescale 1ns / 1ps

package RoCE_params;

    function [31:0] time2clk;
        input real time_value; // in ms
        input real clock_period; // in ns
        time2clk = time_value*1e6/clock_period;
    endfunction

    function [31:0] freq2clk;
        input [31:0] msg_freq; // in hz (integer)
        input [31:0] clock_freq; // in hz (integer)
        freq2clk = clock_freq/msg_freq;
    endfunction

    typedef logic [31:0] RnrTimerValues_t [0:31];
    
    function automatic RnrTimerValues_t getRNRtimercounts(input real clock_period_ns);

        // These time values in milliseconds are fixed by the Infiniband specification.
        // Infiniband specification Vol 1 realeas 1.4 page 354
        const real time_values_ms [0:31] = '{
        655.36, 0.01,   0.02,   0.03,   0.04,   0.06,   0.08,   0.12,
        0.16,   0.24,   0.32,   0.48,   0.64,   0.96,   1.28,   1.92,
        2.56,   3.84,   5.12,   7.68,   10.24,  15.36,  20.48,  30.72,
        40.96,  61.44,  81.92,  122.88, 163.84, 245.76, 327.68, 491.52
        };

        RnrTimerValues_t rnr_timer_counts;
        for (int i = 0; i < 32; i++) begin
            rnr_timer_counts[i] = time2clk(time_values_ms[i], clock_period_ns);
        end
        return rnr_timer_counts;
    endfunction

    parameter [15:0] CM_LISTEN_UDP_PORT = 16'h4321; // 17185
    parameter [15:0] CM_DEST_UDP_PORT   = 16'h4322; // 17186

    /*
    RoCE OP CODES
    */
    parameter [7:0]
    RC_SEND_FIRST         = 8'h00,
    RC_SEND_MIDDLE        = 8'h01,
    RC_SEND_LAST          = 8'h02,
    RC_SEND_LAST_IMD      = 8'h03,
    RC_SEND_ONLY          = 8'h04,
    RC_SEND_ONLY_IMD      = 8'h05,
    RC_RDMA_WRITE_FIRST   = 8'h06,
    RC_RDMA_WRITE_MIDDLE  = 8'h07,
    RC_RDMA_WRITE_LAST    = 8'h08,
    RC_RDMA_WRITE_LAST_IMD= 8'h09,
    RC_RDMA_WRITE_ONLY    = 8'h0A,
    RC_RDMA_WRITE_ONLY_IMD= 8'h0B,
    RC_RDMA_ACK           = 8'h11,
    RoCE_CNP              = 8'h81;

    parameter [15:0] ROCE_UDP_PORT = 16'h12B7;

    /*
    Connection manager parameters
    */
    //REQUESTS types
    parameter
    REQ_NULL          = 3'h0,
    REQ_OPEN_QP       = 3'h1,
    REQ_SEND_QP_INFO  = 3'h2,
    REQ_MODIFY_QP_RTS = 3'h3,
    REQ_CLOSE_QP      = 3'h4,
    REQ_FETCH_QP_INFO = 3'h5, // used only internally
    REQ_ERROR         = 3'h7;

    //ACK types
    parameter
    ACK_NULL          = 3'h0,
    ACK_ACK           = 3'h1,
    ACK_NO_QP         = 3'h2, //No QP available
    ACK_NAK           = 3'h3,
    ACK_ERROR         = 3'h7;

    parameter
    CM_STATUS_OK       = 3'd0,
    CM_ERROR_NO_LOC_QP = 3'd1,
    CM_ERROR_FAILED_OP = 3'd2,
    CM_ERROR_FETCH_QP  = 3'd3,
    CM_ERROR_MOD_QP    = 3'd4,
    CM_ERROR_TIMEOUT   = 3'd5;


    parameter [15:0] ROCE_UDP_TX_SOURCE_PORT = 16'hf8f7;

    // HEADERS 
    //+--------------------------------------+
    //|                 IP                   |
    //+--------------------------------------+
    typedef struct packed {
        logic [31:0] dest_address;
        logic [31:0] src_address;
        logic [15:0] header_checksum;
        logic [7 :0] protocol;
        logic [7 :0] ttl;
        logic [12:0] fragment_offset;
        logic [2 :0] flags;
        logic [15:0] identification;
        logic [15:0] length;
        logic [1 :0] ecn;
        logic [5 :0] dscp;
        logic [3 :0] ihl;
        logic [3:0 ] header_version;
    } ip_hdr_t;
    //+--------------------------------------+
    //|                UDP                   |
    //+--------------------------------------+
    typedef struct packed {
        logic [15:0] checksum;
        logic [15:0] length;
        logic [15:0] dest_port;
        logic [15:0] src_port;
    } udp_hdr_t;
    //+--------------------------------------+
    //|                BTH                   |
    //+--------------------------------------+
    typedef struct packed {
        logic [23:0] psn;
        logic        ack_request;
        logic [6:0]  reserved_1;
        logic [23:0] qp_number;
        logic [5 :0] reserved_0;
        logic        becn;
        logic        fecn;
        logic [15:0] p_key;
        logic        sol_event;
        logic        mig_request;
        logic [1 :0] pad_count;
        logic [3 :0] header_version;
        logic [7 :0] op_code;
    } roce_bth_hdr_t;
    //+--------------------------------------+
    //|               RETH                   |
    //+--------------------------------------+
    typedef struct packed {
        logic [31:0] dma_length;
        logic [31:0] r_key;
        logic [63:0] vaddr;
    } roce_reth_hdr_t;
    //+--------------------------------------+
    //|                IMMD                  |
    //+--------------------------------------+
    typedef struct packed {
        logic [31:0] immediate_data;
    } roce_immd_hdr_t;
    //+--------------------------------------+
    //|               AETH                   |
    //+--------------------------------------+
    typedef struct packed {
        logic [23:0] msn;
        logic [7 :0] syndrome;
    } roce_aeth_hdr_t;

endpackage
