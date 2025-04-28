

package RoCE_params;

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
    REQ_NULL          = 7'h0,
    REQ_OPEN_QP       = 7'h1,
    REQ_SEND_QP_INFO  = 7'h2,
    REQ_MODIFY_QP_RTS = 7'h3,
    REQ_CLOSE_QP      = 7'h4,
    REQ_ERROR         = 7'h7;


    parameter [15:0] ROCE_UDP_TX_SOURCE_PORT = 16'hf8f7;

endpackage