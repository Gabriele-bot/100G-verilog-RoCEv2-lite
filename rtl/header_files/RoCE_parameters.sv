`timescale 1ns / 1ps

package RoCE_params;

    import Board_params::*; // Imports RoCE parameters

    function [31:0] time2clk;
        input real time_value; // in ms
        input real clock_period; // in ns
        time2clk = time_value*1e6/clock_period;
    endfunction

    parameter [15:0] CM_LISTEN_UDP_PORT = 16'h4321;

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

    // Infiniband specification Vol 1 realeas 1.4 page 354
    parameter [0:31][31:0] RNR_TIMER_VALUES = {
    time2clk(655.36, RoCE_CLOCK_PERIOD),
    time2clk(0.01,   RoCE_CLOCK_PERIOD),
    time2clk(0.02,   RoCE_CLOCK_PERIOD),
    time2clk(0.03,   RoCE_CLOCK_PERIOD),
    time2clk(0.04,   RoCE_CLOCK_PERIOD),
    time2clk(0.06,   RoCE_CLOCK_PERIOD),
    time2clk(0.08,   RoCE_CLOCK_PERIOD),
    time2clk(0.12,   RoCE_CLOCK_PERIOD),
    time2clk(0.16,   RoCE_CLOCK_PERIOD),
    time2clk(0.24,   RoCE_CLOCK_PERIOD),
    time2clk(0.32,   RoCE_CLOCK_PERIOD),
    time2clk(0.48,   RoCE_CLOCK_PERIOD),
    time2clk(0.64,   RoCE_CLOCK_PERIOD),
    time2clk(0.96,   RoCE_CLOCK_PERIOD),
    time2clk(1.28,   RoCE_CLOCK_PERIOD),
    time2clk(1.92,   RoCE_CLOCK_PERIOD),
    time2clk(2.56,   RoCE_CLOCK_PERIOD),
    time2clk(3.84,   RoCE_CLOCK_PERIOD),
    time2clk(5.12,   RoCE_CLOCK_PERIOD),
    time2clk(7.68,   RoCE_CLOCK_PERIOD),
    time2clk(10.24,  RoCE_CLOCK_PERIOD),
    time2clk(15.36,  RoCE_CLOCK_PERIOD),
    time2clk(20.48,  RoCE_CLOCK_PERIOD),
    time2clk(30.72,  RoCE_CLOCK_PERIOD),
    time2clk(40.98,  RoCE_CLOCK_PERIOD),
    time2clk(61.44,  RoCE_CLOCK_PERIOD),
    time2clk(81.92,  RoCE_CLOCK_PERIOD),
    time2clk(122.88, RoCE_CLOCK_PERIOD),
    time2clk(163.84, RoCE_CLOCK_PERIOD),
    time2clk(245.76, RoCE_CLOCK_PERIOD),
    time2clk(327.68, RoCE_CLOCK_PERIOD),
    time2clk(491.52, RoCE_CLOCK_PERIOD)
    };

    parameter [0:15][31:0] FREQ_CLK_COUNTER_VALUES = {
    64'd0,
    time2clk(1e3/1,   RoCE_CLOCK_PERIOD),   // 1 Hz
    time2clk(1e3/5,   RoCE_CLOCK_PERIOD),   // 5 Hz
    time2clk(1e3/10,  RoCE_CLOCK_PERIOD),  // 10 Hz
    time2clk(1e3/50,  RoCE_CLOCK_PERIOD),  // 50 Hz
    time2clk(1e3/100, RoCE_CLOCK_PERIOD), // 100 Hz
    time2clk(1e3/500, RoCE_CLOCK_PERIOD), // 500 Hz
    time2clk(1e3/1e3, RoCE_CLOCK_PERIOD), // 1 kHz
    time2clk(1e3/5e3, RoCE_CLOCK_PERIOD), // 5 kHz
    time2clk(1e3/1e4, RoCE_CLOCK_PERIOD), // 10 kHz
    time2clk(1e3/5e4, RoCE_CLOCK_PERIOD), // 50 kHz
    time2clk(1e3/1e5, RoCE_CLOCK_PERIOD), // 100 kHz
    time2clk(1e3/5e5, RoCE_CLOCK_PERIOD), // 500 kHz
    time2clk(1e3/1e6, RoCE_CLOCK_PERIOD), // 1 MHz
    time2clk(1e3/5e6, RoCE_CLOCK_PERIOD), // 5 MHz
    time2clk(1e3/1e7, RoCE_CLOCK_PERIOD)  // 10 MHz

    };

    /*
    Connection manager parameters
    */
    /*
    Local QP number starts from 2**8 and goes up to 2**8 + 2**(MAX_QUEUE_PAIRS)
    */
    parameter MAX_QUEUE_PAIRS = 4;

    parameter MAX_QUEUE_PAIRS_WIDTH = $clog2(MAX_QUEUE_PAIRS);
    //REQUESTS types
    parameter
    REQ_NULL          = 3'h0,
    REQ_OPEN_QP       = 3'h1,
    REQ_SEND_QP_INFO  = 3'h2,
    REQ_MODIFY_QP_RTS = 3'h3,
    REQ_CLOSE_QP      = 3'h4,
    REQ_ERROR         = 3'h7;

    //ACK types
    parameter
    ACK_NULL          = 3'h0,
    ACK_ACK           = 3'h1,
    ACK_NO_QP         = 3'h2, //No QP available
    ACK_NAK           = 3'h3,
    ACK_ERROR         = 3'h7;


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
        logic [7 :0] reserved_0;
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