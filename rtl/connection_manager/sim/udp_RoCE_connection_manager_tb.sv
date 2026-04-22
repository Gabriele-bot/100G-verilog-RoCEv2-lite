`timescale 1ns/1ps

module tb_udp_RoCE_connection_manager;


    import RoCE_params::*; // Imports RoCE parameters

    localparam DATA_WIDTH = 512;
    localparam KEEP_WIDTH = DATA_WIDTH/8;

    localparam FPGA_IP_ADDR   = {8'd22, 8'd01, 8'd212, 8'd10};
    localparam SERVER_IP_ADDR = {8'd22, 8'd01, 8'd212, 8'd21};
    localparam SRC_UDP_PORT   = 16'h8765;

    localparam CM_TIMEOUT = 200;

    localparam WAIT_REPLY_TIMEOUT = 5*CM_TIMEOUT;




    // ----------------------------------------------------------------
    // Clock / Reset
    // ----------------------------------------------------------------
    logic clk;
    logic rst;

    // UDP frame connections to CM                
    logic                        rx_udp_cm_hdr_valid;
    logic                        rx_udp_cm_hdr_ready;
    logic [15:0]                 rx_udp_cm_source_port;
    logic [15:0]                 rx_udp_cm_dest_port;
    logic [15:0]                 rx_udp_cm_length;
    logic [15:0]                 rx_udp_cm_checksum;
    logic [DATA_WIDTH   - 1 : 0] rx_udp_cm_payload_axis_tdata;
    logic [DATA_WIDTH/8 - 1 : 0] rx_udp_cm_payload_axis_tkeep;
    logic                        rx_udp_cm_payload_axis_tvalid;
    logic                        rx_udp_cm_payload_axis_tready;
    logic                        rx_udp_cm_payload_axis_tlast;
    logic                        rx_udp_cm_payload_axis_tuser;

    logic                        tx_udp_cm_hdr_valid;
    logic                        tx_udp_cm_hdr_ready;
    logic [31:0]                 tx_udp_cm_ip_source_ip;
    logic [31:0]                 tx_udp_cm_ip_dest_ip;
    logic [15:0]                 tx_udp_cm_source_port;
    logic [15:0]                 tx_udp_cm_dest_port;
    logic [15:0]                 tx_udp_cm_length;
    logic [15:0]                 tx_udp_cm_checksum;
    logic [DATA_WIDTH   - 1 : 0] tx_udp_cm_payload_axis_tdata;
    logic [DATA_WIDTH/8 - 1 : 0] tx_udp_cm_payload_axis_tkeep;
    logic                        tx_udp_cm_payload_axis_tvalid;
    logic                        tx_udp_cm_payload_axis_tready;
    logic                        tx_udp_cm_payload_axis_tlast;
    logic                        tx_udp_cm_payload_axis_tuser;

    logic        cm_qp_valid;
    logic [2 :0] cm_qp_req_type;
    logic [31:0] cm_qp_dma_transfer_length;
    logic [23:0] cm_qp_rem_qpn;
    logic [23:0] cm_qp_loc_qpn;
    logic [23:0] cm_qp_rem_psn;
    logic [23:0] cm_qp_loc_psn;
    logic [31:0] cm_qp_r_key;
    logic [63:0] cm_qp_rem_addr;
    logic [31:0] cm_qp_rem_ip_addr;

    logic        cm_qp_status_valid;
    logic [1 :0] cm_qp_status;
    logic [2 :0] cm_qp_status_state;
    logic [31:0] cm_qp_status_r_key;
    logic [23:0] cm_qp_status_rem_qpn;
    logic [23:0] cm_qp_status_loc_qpn;
    logic [23:0] cm_qp_status_rem_psn;
    logic [23:0] cm_qp_status_loc_psn;
    logic [31:0] cm_qp_status_rem_ip_addr;
    logic [63:0] cm_qp_status_rem_addr;
    // CM master requests
    logic        cm_qp_master_req_valid;
    logic [2:0]  cm_qp_master_req_type;
    logic [23:0] cm_qp_master_req_loc_qpn;
    logic [31:0] cm_qp_master_req_rem_ip_addr;

    logic        cm_qp_master_status_valid;
    logic [2:0]  cm_qp_master_status;
    logic [23:0] cm_qp_master_status_loc_qpn;

    logic [23:0] open_loc_qpn;


    always #5 clk = ~clk; // 100MHz clock


    // Module instantiation
    udp_RoCE_connection_manager #(
        .DATA_WIDTH(DATA_WIDTH),
        .MODULE_DIRECTION("Master"),
        .MASTER_TIMEOUT(CM_TIMEOUT)
    ) udp_RoCE_connection_manager_instance (
        .clk(clk),
        .rst(rst),

        .s_udp_hdr_valid          (rx_udp_cm_hdr_valid),
        .s_udp_hdr_ready          (rx_udp_cm_hdr_ready),
        .s_udp_source_port        (rx_udp_cm_source_port),
        .s_udp_dest_port          (rx_udp_cm_dest_port),
        .s_udp_length             (rx_udp_cm_length),
        .s_udp_checksum           (rx_udp_cm_checksum),

        .s_udp_payload_axis_tdata (rx_udp_cm_payload_axis_tdata),
        .s_udp_payload_axis_tkeep (rx_udp_cm_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid(rx_udp_cm_payload_axis_tvalid),
        .s_udp_payload_axis_tready(rx_udp_cm_payload_axis_tready),
        .s_udp_payload_axis_tlast (rx_udp_cm_payload_axis_tlast),
        .s_udp_payload_axis_tuser (rx_udp_cm_payload_axis_tuser),

        .m_udp_hdr_valid          (tx_udp_cm_hdr_valid),
        .m_udp_hdr_ready          (tx_udp_cm_hdr_ready),
        .m_ip_source_ip           (tx_udp_cm_ip_source_ip),
        .m_ip_dest_ip             (tx_udp_cm_ip_dest_ip),
        .m_udp_source_port        (tx_udp_cm_source_port),
        .m_udp_dest_port          (tx_udp_cm_dest_port),
        .m_udp_length             (tx_udp_cm_length),
        .m_udp_checksum           (tx_udp_cm_checksum),

        .m_udp_payload_axis_tdata (tx_udp_cm_payload_axis_tdata),
        .m_udp_payload_axis_tkeep (tx_udp_cm_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(tx_udp_cm_payload_axis_tvalid),
        .m_udp_payload_axis_tready(tx_udp_cm_payload_axis_tready),
        .m_udp_payload_axis_tlast (tx_udp_cm_payload_axis_tlast),
        .m_udp_payload_axis_tuser (tx_udp_cm_payload_axis_tuser),

        // write to qp state
        .cm_qp_valid        (cm_qp_valid),
        .cm_qp_req_type     (cm_qp_req_type),
        .cm_qp_r_key        (cm_qp_r_key),
        .cm_qp_rem_qpn      (cm_qp_rem_qpn),
        .cm_qp_loc_qpn      (cm_qp_loc_qpn),
        .cm_qp_rem_psn      (cm_qp_rem_psn),
        .cm_qp_loc_psn      (cm_qp_loc_psn),
        .cm_qp_rem_base_addr(cm_qp_rem_addr),
        .cm_qp_rem_ip_addr  (cm_qp_rem_ip_addr),
        // read from qp state
        .cm_qp_status_valid      (cm_qp_status_valid),
        .cm_qp_status            (cm_qp_status),
        .cm_qp_status_state      (cm_qp_status_state),
        .cm_qp_status_r_key      (cm_qp_status_r_key),
        .cm_qp_status_rem_qpn    (cm_qp_status_rem_qpn),
        .cm_qp_status_loc_qpn    (cm_qp_status_loc_qpn),
        .cm_qp_status_rem_psn    (cm_qp_status_rem_psn),
        .cm_qp_status_loc_psn    (cm_qp_status_loc_psn),
        .cm_qp_status_rem_ip_addr(cm_qp_status_rem_ip_addr),
        .cm_qp_status_rem_addr   (cm_qp_status_rem_addr),
        // Request (for master only)
        .cm_qp_master_req_valid      (cm_qp_master_req_valid),
        .cm_qp_master_req_type       (cm_qp_master_req_type),
        .cm_qp_master_req_loc_qpn    (cm_qp_master_req_loc_qpn),
        .cm_qp_master_req_rem_ip_addr(cm_qp_master_req_rem_ip_addr),

        .cm_qp_master_status_valid   (cm_qp_master_status_valid),
        .cm_qp_master_status         (cm_qp_master_status),
        .cm_qp_master_status_loc_qpn (cm_qp_master_status_loc_qpn),

        .m_metadata_valid     (),
        .m_start_transfer     (),
        .m_txmeta_loc_qpn     (),
        .m_txmeta_is_immediate(),
        .m_txmeta_tx_type     (),
        .m_txmeta_dma_transfer(),
        .m_txmeta_n_transfers (),
        .m_txmeta_frequency   (),

        .cfg_udp_source_port(SRC_UDP_PORT),
        .cfg_loc_ip_addr    (FPGA_IP_ADDR)
    );

    RoCE_qp_state_module #(
        .REM_ADDR_WIDTH(16)
    ) RoCE_qp_state_module_instance (
        .clk                    (clk),
        .rst                    (rst),
        .rst_qp                 (rst),
        // cm write interface
        .cm_qp_valid          (cm_qp_valid),
        .cm_qp_req_type       (cm_qp_req_type),
        .cm_qp_r_key          (cm_qp_r_key),
        .cm_qp_rem_qpn        (cm_qp_rem_qpn),
        .cm_qp_loc_qpn        (cm_qp_loc_qpn),
        .cm_qp_rem_psn        (cm_qp_rem_psn),
        .cm_qp_loc_psn        (cm_qp_loc_psn),
        .cm_qp_rem_ip_addr    (cm_qp_rem_ip_addr),
        .cm_qp_rem_addr       (cm_qp_rem_addr),
        //cm read interface
        .cm_qp_status_valid      (cm_qp_status_valid),
        .cm_qp_status            (cm_qp_status),
        .cm_qp_status_state      (cm_qp_status_state),
        .cm_qp_status_r_key      (cm_qp_status_r_key),
        .cm_qp_status_rem_qpn    (cm_qp_status_rem_qpn),
        .cm_qp_status_loc_qpn    (cm_qp_status_loc_qpn),
        .cm_qp_status_rem_psn    (cm_qp_status_rem_psn),
        .cm_qp_status_loc_psn    (cm_qp_status_loc_psn),
        .cm_qp_status_rem_ip_addr(cm_qp_status_rem_ip_addr),
        .cm_qp_status_rem_addr   (cm_qp_status_rem_addr),
        // close qp if transfer did not succeed
        .qp_close_valid(1'b0),
        .qp_close_loc_qpn(0), // loc_qpn
        // QP request
        .qp_context_req         (1'b0),
        .qp_local_qpn_req       (0),
        .qp_req_context_valid   (),
        .qp_req_state           (),
        .qp_req_r_key           (),
        .qp_req_rem_qpn         (),
        .qp_req_loc_qpn         (),
        .qp_req_rem_psn         (),
        .qp_req_loc_psn         (),
        .qp_req_rem_ip_addr     (),
        .qp_req_rem_addr        (),

        // QP spy
        .qp_context_spy         (1'b0),
        .qp_local_qpn_spy       (0),
        .qp_spy_context_valid   (),
        .qp_spy_state           (),
        .qp_spy_r_key           (),
        .qp_spy_rem_qpn         (),
        .qp_spy_loc_qpn         (),
        .qp_spy_rem_psn         (),
        .qp_spy_rem_acked_psn   (),
        .qp_spy_loc_psn         (),
        .qp_spy_rem_ip_addr     (),
        .qp_spy_rem_addr        (),
        .qp_spy_syndrome        (),

        .s_qp_update_context_valid(1'b0),
        .s_qp_update_loc_qpn      (0),
        .s_qp_update_rem_psn      (0),

        .s_roce_rx_bth_valid    (0),
        .s_roce_rx_bth_ready    (),
        .s_roce_rx_bth_op_code  (0),
        .s_roce_rx_bth_p_key    (0),
        .s_roce_rx_bth_psn      (0),
        .s_roce_rx_bth_dest_qp  (0),
        .s_roce_rx_bth_ack_req  (0),
        .s_roce_rx_aeth_valid   (0),
        .s_roce_rx_aeth_ready   (),
        .s_roce_rx_aeth_syndrome(0),
        .s_roce_rx_aeth_msn     (0),

        .last_acked_psn         (),
        .stop_transfer          (),
        .pmtu(4'd5)
    );

    // Reset
    initial begin
        clk = 0;
        rst = 1;

        rx_udp_cm_hdr_valid = 0;
        rx_udp_cm_payload_axis_tvalid = 0;
        tx_udp_cm_hdr_ready = 1;
        tx_udp_cm_payload_axis_tready = 1;

        cm_qp_master_req_valid = 0;

        repeat(10) @(posedge clk);
        rst = 0;
    end

    task check_cm_status(output logic [23:0] loc_qpn);

        int timeout;

        begin
            // -------------------------------------------------
            // Wait for error response (with timeout)
            // -------------------------------------------------

            timeout = 0;

            while (!cm_qp_master_status_valid) begin
                @(posedge clk);
                timeout++;

                if (timeout > WAIT_REPLY_TIMEOUT) begin
                    $error("[%t] ERROR TIMEOUT waiting for cm_qp_master_status_valid", $time);
                    return;
                end
            end

            // -------------------------------------------------
            // Error Valid MUST be high
            // -------------------------------------------------
            if (!cm_qp_master_status_valid) begin
                $error("[%t] cm_qp_master_status_valid not asserted!", $time);
            end

            // -------------------------------------------------
            // Decode Error Code
            // -------------------------------------------------
            case (cm_qp_master_status)

                CM_STATUS_OK: begin
                    $display("[%t] CM STATUS OK: OPERATION COMPLETED\n", $time);
                    if (cm_qp_master_req_type == REQ_OPEN_QP) begin
                        $display("[%t] OPENED LOCAL QPN = %0d \n", $time, cm_qp_master_status_loc_qpn);
                    end
                end

                CM_ERROR_NO_LOC_QP: begin
                    $display("[%t] CM ERROR: NO LOCAL QP\n", $time);
                    $display("[%t] MASTER REQUEST COMPLETED WITH ERRORS\n", $time);
                end

                CM_ERROR_FAILED_OP: begin
                    $display("[%t] CM ERROR: FAILED OPERATION\n", $time);
                    $display("[%t] MASTER REQUEST COMPLETED WITH ERRORS\n", $time);
                end

                CM_ERROR_FETCH_QP: begin
                    $display("[%t] CM ERROR: FETCH QP FAILED\n", $time);
                    $display("[%t] MASTER REQUEST COMPLETED WITH ERRORS\n", $time);
                end

                CM_ERROR_MOD_QP: begin
                    $display("[%t] CM ERROR: FAILED TO MODIFY QP\n", $time);
                    $display("[%t] MASTER REQUEST COMPLETED WITH ERRORS\n", $time);
                end

                CM_ERROR_TIMEOUT: begin
                    $display("[%t] CM ERROR: TIMEOUT REACHED\n", $time);
                    $display("[%t] MASTER REQUEST COMPLETED WITH ERRORS\n", $time);
                end

                default:
                $error("[%t] UNKNOWN CM ERROR CODE: %0d\n",
                    $time, cm_qp_master_status);

            endcase

            loc_qpn = cm_qp_master_status_loc_qpn;
        end
    endtask

    task send_master_open(output logic [23:0] loc_qpn);

        int timeout;

        begin
            @(posedge clk);

            // -------------------------------------------------
            // Send OPEN request
            // -------------------------------------------------
            cm_qp_master_req_valid       <= 1;
            cm_qp_master_req_type        <= REQ_OPEN_QP;
            cm_qp_master_req_loc_qpn     <= 24'h0; // not relevant
            cm_qp_master_req_rem_ip_addr <= SERVER_IP_ADDR;

            @(posedge clk);
            cm_qp_master_req_valid <= 0;

            $display("[%t] MASTER OPEN REQUEST SENT TO IP ADDRESS %0d.%0d.%0d.%0d\n", $time, SERVER_IP_ADDR[31:24], SERVER_IP_ADDR[23:16], SERVER_IP_ADDR[15:8], SERVER_IP_ADDR[7:0]);

            check_cm_status(loc_qpn);

        end
    endtask

    // Close QP request task
    task send_master_close(input logic [23:0] close_loc_qpn);
        logic [23:0] temp_loc_qpn;
        begin
            @(posedge clk);

            cm_qp_master_req_valid       <= 1;
            cm_qp_master_req_type        <= REQ_CLOSE_QP;
            cm_qp_master_req_loc_qpn     <= close_loc_qpn;
            cm_qp_master_req_rem_ip_addr <= 32'd0; // not relevant

            @(posedge clk);
            cm_qp_master_req_valid <= 0;

            $display("[%t] MASTER CLOSE LOCAL QP (%0d) REQUEST SENT\n", $time, close_loc_qpn);

            check_cm_status(temp_loc_qpn);
        end
    endtask



    // ------------------------------------------------------------
    // AXI STREAM UDP PAYLOAD DECODER (DATA_WIDTH AGNOSTIC)
    // ------------------------------------------------------------
    task automatic decode_udp_payload(input logic [511:0] payload);

        begin
            // ----------------------------------------------------
            // Decode fields
            // ----------------------------------------------------
            $display("\n");
            $display("-------------------------------------------------");
            $display(" UDP CM PAYLOAD DECODE ");
            $display("-------------------------------------------------");

            $display("QP_info_valid            : %0d",  payload[0]);
            $display("QP_req_type              : %0d",  payload[3:1]);
            $display("QP_ack_valid             : %0d",  payload[4]);
            $display("QP_ack_type              : %0d",  payload[7:5]);

            $display("QP_info_loc_qpn          : %h",   {<<8{payload[39:16]}});
            $display("QP_info_loc_psn          : %h",   {<<8{payload[71:48]}});
            $display("QP_info_loc_r_key        : %h",   {<<8{payload[103:72]}});
            $display("QP_info_loc_base_addr    : %h",   {<<8{payload[167:104]}});
            $display("QP_info_loc_ip_addr      : %d.%d.%d.%d", payload[175:168],payload[183:176],payload[191:184],payload[199:192]);

            $display("QP_info_rem_qpn          : %h",   {<<8{payload[231:208]}});
            $display("QP_info_rem_psn          : %h",   {<<8{payload[263:240]}});
            $display("QP_info_rem_r_key        : %h",   {<<8{payload[295:264]}});
            $display("QP_info_rem_base_addr    : %h",   {<<8{payload[359:296]}});
            $display("QP_info_rem_ip_addr      : %d.%d.%d.%d", payload[367:360],payload[375:368],payload[383:376],payload[391:384]);
            $display("QP_info_listening_port   : %h",   {<<8{payload[407:392]}});

            $display("txmeta_valid             : %0d",  payload[408]);
            $display("txmeta_start             : %0d",  payload[409]);
            $display("txmeta_is_immediate      : %0d",  payload[410]);
            $display("txmeta_tx_type           : %0d",  payload[411]);
            $display("txmeta_dma_length        : %h",   {<<8{payload[447:416]}});
            $display("txmeta_n_transfers       : %h",   {<<8{payload[479:448]}});
            $display("txmeta_frequency         : %h",   {<<8{payload[511:480]}});

            $display("-------------------------------------------------\n");

        end

    endtask

    // -----------------------------------------------------------------------------
    // MONITOR TX UDP PACKET (Outgoing from DUT)
    // -----------------------------------------------------------------------------
    task automatic monitor_tx_udp();

        logic [511:0] payload;
        int           bit_ptr;

        begin
            forever begin
                @(posedge clk);

                // ---------------------------------------------------------
                // WAIT FOR HEADER HANDSHAKE
                // ---------------------------------------------------------
                if (tx_udp_cm_hdr_valid && tx_udp_cm_hdr_ready) begin

                    $display("\n=================================================");
                    $display("[%t] >>> TX UDP HEADER <<<", $time);
                    $display("Source IP  : %0d.%0d.%0d.%0d", tx_udp_cm_ip_source_ip[31:24],tx_udp_cm_ip_source_ip[23:16],tx_udp_cm_ip_source_ip[15:8],tx_udp_cm_ip_source_ip[7:0]);
                    $display("Dest IP    : %0d.%0d.%0d.%0d", tx_udp_cm_ip_dest_ip[31:24],tx_udp_cm_ip_dest_ip[23:16],tx_udp_cm_ip_dest_ip[15:8],tx_udp_cm_ip_dest_ip[7:0]);
                    $display("Source Port: %h", tx_udp_cm_source_port);
                    $display("Dest Port  : %h", tx_udp_cm_dest_port);
                    $display("Length     : %0d", tx_udp_cm_length);
                    $display("Checksum   : %h", tx_udp_cm_checksum);
                    $display("=================================================");

                    // ---------------------------------------------------------
                    // COLLECT AXI PAYLOAD
                    // ---------------------------------------------------------
                    payload = '0;
                    bit_ptr = 0;

                    while (1) begin
                        @(posedge clk);

                        if (tx_udp_cm_payload_axis_tvalid &&
                        tx_udp_cm_payload_axis_tready) begin

                            payload[bit_ptr +: DATA_WIDTH] =
                            tx_udp_cm_payload_axis_tdata;

                            bit_ptr += DATA_WIDTH;

                            if (tx_udp_cm_payload_axis_tlast)
                                break;
                        end
                    end

                    // ---------------------------------------------------------
                    // DECODE PAYLOAD
                    // ---------------------------------------------------------
                    decode_udp_payload(payload);

                end
            end
        end
    endtask

    // -----------------------------------------------------------------------------
    // MONITOR RX UDP PACKET (Incoming to DUT)
    // -----------------------------------------------------------------------------
    task automatic monitor_rx_udp();

        logic [511:0] payload;
        int           bit_ptr;

        begin
            forever begin
                @(posedge clk);

                // ---------------------------------------------------------
                // WAIT FOR HEADER HANDSHAKE
                // ---------------------------------------------------------
                if (rx_udp_cm_hdr_valid && rx_udp_cm_hdr_ready) begin

                    $display("\n=================================================");
                    $display("[%t] <<< RX UDP HEADER <<<", $time);
                    $display("Source Port: %h", rx_udp_cm_source_port);
                    $display("Dest Port  : %h", rx_udp_cm_dest_port);
                    $display("Length     : %0d", rx_udp_cm_length);
                    $display("Checksum   : %h", rx_udp_cm_checksum);
                    $display("=================================================");

                    // ---------------------------------------------------------
                    // COLLECT AXI PAYLOAD
                    // ---------------------------------------------------------
                    payload = '0;
                    bit_ptr = 0;

                    while (1) begin
                        @(posedge clk);

                        if (rx_udp_cm_payload_axis_tvalid &&
                        rx_udp_cm_payload_axis_tready) begin

                            payload[bit_ptr +: DATA_WIDTH] =
                            rx_udp_cm_payload_axis_tdata;

                            bit_ptr += DATA_WIDTH;

                            if (rx_udp_cm_payload_axis_tlast)
                                break;
                        end
                    end

                    // ---------------------------------------------------------
                    // DECODE PAYLOAD
                    // ---------------------------------------------------------
                    decode_udp_payload(payload);

                end
            end
        end
    endtask

    // -----------------------------------------------------------------------------
    // UDP AUTO-REPLY TASK
    // Waits for outgoing UDP packet and sends ACK reply back on RX interface
    // -----------------------------------------------------------------------------
    task automatic udp_auto_reply(input logic [31:0] latency = 32'd1000);

        logic [511:0] payload;
        logic [511:0] reply_payload;
        logic [31:0]  src_ip, dst_ip;
        logic [15:0]  src_port, dst_port;
        int           bit_ptr;

        begin
            payload = '0;
            bit_ptr = 0;

            // ---------------------------------------------------------
            // 1. WAIT FOR TX HEADER
            // ---------------------------------------------------------
            @(posedge clk);
            wait(tx_udp_cm_hdr_valid);

            src_ip   = tx_udp_cm_ip_dest_ip; // swap
            dst_ip   = tx_udp_cm_ip_source_ip;
            src_port = tx_udp_cm_dest_port;
            dst_port = CM_LISTEN_UDP_PORT;

            $display("[%t] UDP REQUEST CAPTURED - Preparing ACK\n", $time);

            // ---------------------------------------------------------
            // 2. CAPTURE AXI STREAM PAYLOAD
            // ---------------------------------------------------------
            while (1) begin
                @(posedge clk);

                if (tx_udp_cm_payload_axis_tvalid &&
                tx_udp_cm_payload_axis_tready) begin

                    payload[bit_ptr +: DATA_WIDTH] =
                    tx_udp_cm_payload_axis_tdata;

                    bit_ptr += DATA_WIDTH;

                    if (tx_udp_cm_payload_axis_tlast)
                        break;
                end
            end

            // ---------------------------------------------------------
            // 3. BUILD REPLY PAYLOAD
            // ---------------------------------------------------------
            reply_payload = payload;

            // Keep same request type
            // payload[3:0] unchanged

            reply_payload[4]   = 1'b1; // QP_ack_valid
            reply_payload[7:5] = ACK_ACK; // ACK_ACK type

            // local params (SWAP ENDIANESS)
            reply_payload[39 :16 ] = {<<8{24'($urandom)}}; // local QPN
            reply_payload[71 :48 ] = {<<8{24'($urandom)}}; // local PSN
            reply_payload[103:72 ] = {<<8{$urandom}}; // local R_KEY
            reply_payload[167:104] = {<<8{{$urandom, $urandom}}}; // local BASE ADDR
            reply_payload[199:168] = {<<8{SERVER_IP_ADDR}}; // local IP ADDR
            // remote params
            reply_payload[231:208] = payload[39 :16 ]; // remote QPN
            reply_payload[263:240] = payload[71 :48 ]; // remote PSN
            reply_payload[295:264] = payload[103:72 ]; // remote R_KEY
            reply_payload[359:296] = payload[167:104]; // remote BASE ADDR
            reply_payload[391:360] = payload[199:168]; // remote IP ADDR

            reply_payload[407:392]= CM_DEST_UDP_PORT;


            repeat(latency) @(posedge clk);



            // ---------------------------------------------------------
            // 4. DRIVE REPLY ON RX INTERFACE
            // ---------------------------------------------------------

            $display("[%t] SENDING ACK PACKET BACK TO DUT\n", $time);
            @(posedge clk);

            rx_udp_cm_hdr_valid <= 1;
            rx_udp_cm_source_port <= src_port;
            rx_udp_cm_dest_port   <= dst_port;
            rx_udp_cm_length      <= 16'd72; // 512 bits + header
            rx_udp_cm_checksum    <= 16'd0; // No checksum

            wait(rx_udp_cm_hdr_ready);
            @(posedge clk);
            rx_udp_cm_hdr_valid <= 0;

            // Send AXI payload
            bit_ptr = 0;

            while (bit_ptr < 512) begin
                @(posedge clk);

                rx_udp_cm_payload_axis_tdata  <= reply_payload[bit_ptr +: DATA_WIDTH];
                rx_udp_cm_payload_axis_tkeep  <= {DATA_WIDTH/8{1'b1}};
                rx_udp_cm_payload_axis_tvalid <= 1;
                rx_udp_cm_payload_axis_tlast  <= (bit_ptr + DATA_WIDTH >= 512);
                rx_udp_cm_payload_axis_tuser  <= 0;

                wait(rx_udp_cm_payload_axis_tready);

                bit_ptr += DATA_WIDTH;
            end

            @(posedge clk);
            rx_udp_cm_payload_axis_tvalid <= 0;
            rx_udp_cm_payload_axis_tlast  <= 0;

            //$display("[%t] ACK REPLY SENT BACK TO DUT\n", $time);

        end
    endtask

    // monitor reply latency

    task monitor_raply_latency();
        automatic logic [31:0] counter = 0;
        while (1) begin
            @(posedge clk);
            counter = counter + 1;
            if (tx_udp_cm_hdr_valid && tx_udp_cm_hdr_ready) begin
                counter = 0;
            end

            if (rx_udp_cm_hdr_valid && rx_udp_cm_hdr_ready) begin
                $display("[%t] GOT A REPLY AFTER %0d CLOCK TICKS\n", $time,  counter);
                counter = 0;
            end

        end

    endtask

    // test sequence
    initial begin
        wait(!rst);

        fork
            monitor_raply_latency();
        join_none

        $display("=================================================");
        $display("            NORMAL OPERATION");
        $display("=================================================");
        fork
            udp_auto_reply(32'd100);
        join_none
        send_master_open(open_loc_qpn);
        fork
            udp_auto_reply(CM_TIMEOUT-50);
        join_none
        send_master_close(open_loc_qpn);


        $display("=================================================");
        $display("            CLOSE QP NOT OPEN");
        $display("=================================================");
        fork
            udp_auto_reply(CM_TIMEOUT-50);
        join_none
        send_master_open(open_loc_qpn);
        fork
            udp_auto_reply(CM_TIMEOUT-50);
        join_none
        send_master_close(24'd259); // wrong one
        send_master_close(open_loc_qpn); // correct one


        $display("=================================================");
        $display("            FORCE RETRY");
        $display("=================================================");
        fork
            udp_auto_reply(CM_TIMEOUT+50);
        join_none
        send_master_open(open_loc_qpn);
        fork
            udp_auto_reply(CM_TIMEOUT-50);
        join_none
        send_master_close(open_loc_qpn);


        $display("=================================================");
        $display("            NO REPLY");
        $display("=================================================");
        send_master_open(open_loc_qpn);

        repeat(10) begin
            $display("=================================================");
            $display("            NORMAL OPERATION");
            $display("=================================================");
            fork
                udp_auto_reply(CM_TIMEOUT-50);
            join_none
            send_master_open(open_loc_qpn);
            fork
                udp_auto_reply(CM_TIMEOUT-50);
            join_none
            send_master_close(open_loc_qpn);
        end



        repeat(10) @(posedge clk);
        $display("TEST COMPLETE");
        //$finish;
        $stop;
    end


endmodule
