`timescale 1ns/1ps
`default_nettype none

/*
 * Testbench for RoCE_udp_rx
 *
 * Supports any DATA_WIDTH (set the localparam below).  All packet drivers
 * use a byte-array + generic loop so beat count and tkeep are computed
 * automatically via BYTE_LANES = DATA_WIDTH/8.
 *
 * Bus convention: little-endian – byte N of the frame sits at
 *   tdata[N%BYTE_LANES*8 +: 8] in beat N/BYTE_LANES.
 *
 * UDP payloads under test:
 *   RC ACK (op=0x11) – 20 bytes : BTH(12) + AETH(4) + ICRC(4)
 *   CNP    (op=0x81) – 24 bytes : BTH(12) + rsvd(8) + ICRC(4)
 *   Drop   (op=0x05) – 20 bytes : same layout as ACK, no output fires
 */
module tb_RoCE_udp_rx;

    localparam DATA_WIDTH = 64;
    localparam KEEP_WIDTH = DATA_WIDTH / 8;   // 8
    localparam CLK_HALF   = 5;                // 10 ns clock
    localparam int BURST_N    = 10;             // packets in burst test
    localparam int BYTE_LANES = KEEP_WIDTH;   // bytes per bus beat
    localparam int MAX_PKT    = 64;           // max UDP payload bytes

    // ----------------------------------------------------------------
    // Clock / reset
    // ----------------------------------------------------------------
    logic clk = 1'b0;
    logic rst = 1'b1;

    always #CLK_HALF clk = ~clk;

    // ----------------------------------------------------------------
    // DUT port signals – inputs driven by TB
    // ----------------------------------------------------------------
    logic        s_udp_hdr_valid     = 1'b0;
    logic [47:0] s_eth_dest_mac      = 48'hAABBCCDDEEFF;
    logic [47:0] s_eth_src_mac       = 48'h112233445566;
    logic [15:0] s_eth_type          = 16'h0800;
    logic [ 3:0] s_ip_version        = 4'd4;
    logic [ 3:0] s_ip_ihl            = 4'd5;
    logic [ 5:0] s_ip_dscp           = 6'd0;
    logic [ 1:0] s_ip_ecn            = 2'd0;
    logic [15:0] s_ip_length         = 16'd68;
    logic [15:0] s_ip_identification = 16'd0;
    logic [ 2:0] s_ip_flags          = 3'b010;
    logic [12:0] s_ip_fragment_offset = 13'd0;
    logic [ 7:0] s_ip_ttl            = 8'd64;
    logic [ 7:0] s_ip_protocol       = 8'd17;
    logic [15:0] s_ip_header_checksum = 16'd0;
    logic [31:0] s_ip_source_ip      = {8'd10, 8'd0, 8'd0, 8'd1};
    logic [31:0] s_ip_dest_ip        = {8'd10, 8'd0, 8'd0, 8'd2};
    logic [15:0] s_udp_source_port   = 16'd12345;
    logic [15:0] s_udp_dest_port     = 16'd4791;
    logic [15:0] s_udp_length        = 16'd28;   // updated per packet
    logic [15:0] s_udp_checksum      = 16'd0;

    logic [DATA_WIDTH-1:0] s_udp_payload_axis_tdata  = '0;
    logic [KEEP_WIDTH-1:0] s_udp_payload_axis_tkeep  = '0;
    logic                  s_udp_payload_axis_tvalid = 1'b0;
    logic                  s_udp_payload_axis_tlast  = 1'b0;
    logic                  s_udp_payload_axis_tuser  = 1'b0;

    logic                  m_roce_aeth_hdr_ready = 1'b1;
    logic                  m_roce_cnp_hdr_ready  = 1'b1;

    // ----------------------------------------------------------------
    // DUT port signals – outputs observed by TB
    // ----------------------------------------------------------------
    logic        s_udp_hdr_ready;
    logic        s_udp_payload_axis_tready;

    logic        m_roce_aeth_hdr_valid;
    logic [23:0] m_roce_aeth_dest_qp;
    logic [23:0] m_roce_aeth_psn;
    logic [ 7:0] m_roce_aeth_syndrome;
    logic [23:0] m_roce_aeth_msn;
    logic [31:0] m_roce_aeth_icrc;

    logic        m_roce_cnp_hdr_valid;
    logic [23:0] m_roce_cnp_dest_qp;
    logic [31:0] m_roce_cnp_icrc;

    logic        busy;
    logic        error_header_early_termination;
    logic        error_payload_early_termination;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    RoCE_udp_rx #(
        .DATA_WIDTH  (DATA_WIDTH),
        .KEEP_ENABLE (1),
        .KEEP_WIDTH  (KEEP_WIDTH)
    ) dut (
        .clk                          (clk),
        .rst                          (rst),

        .s_udp_hdr_valid              (s_udp_hdr_valid),
        .s_udp_hdr_ready              (s_udp_hdr_ready),
        .s_eth_dest_mac               (s_eth_dest_mac),
        .s_eth_src_mac                (s_eth_src_mac),
        .s_eth_type                   (s_eth_type),
        .s_ip_version                 (s_ip_version),
        .s_ip_ihl                     (s_ip_ihl),
        .s_ip_dscp                    (s_ip_dscp),
        .s_ip_ecn                     (s_ip_ecn),
        .s_ip_length                  (s_ip_length),
        .s_ip_identification          (s_ip_identification),
        .s_ip_flags                   (s_ip_flags),
        .s_ip_fragment_offset         (s_ip_fragment_offset),
        .s_ip_ttl                     (s_ip_ttl),
        .s_ip_protocol                (s_ip_protocol),
        .s_ip_header_checksum         (s_ip_header_checksum),
        .s_ip_source_ip               (s_ip_source_ip),
        .s_ip_dest_ip                 (s_ip_dest_ip),
        .s_udp_source_port            (s_udp_source_port),
        .s_udp_dest_port              (s_udp_dest_port),
        .s_udp_length                 (s_udp_length),
        .s_udp_checksum               (s_udp_checksum),
        .s_udp_payload_axis_tdata     (s_udp_payload_axis_tdata),
        .s_udp_payload_axis_tkeep     (s_udp_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid    (s_udp_payload_axis_tvalid),
        .s_udp_payload_axis_tready    (s_udp_payload_axis_tready),
        .s_udp_payload_axis_tlast     (s_udp_payload_axis_tlast),
        .s_udp_payload_axis_tuser     (s_udp_payload_axis_tuser),

        .m_roce_aeth_hdr_valid        (m_roce_aeth_hdr_valid),
        .m_roce_aeth_hdr_ready        (m_roce_aeth_hdr_ready),
        .m_roce_aeth_dest_qp          (m_roce_aeth_dest_qp),
        .m_roce_aeth_psn              (m_roce_aeth_psn),
        .m_roce_aeth_syndrome         (m_roce_aeth_syndrome),
        .m_roce_aeth_msn              (m_roce_aeth_msn),
        .m_roce_aeth_icrc             (m_roce_aeth_icrc),

        .m_roce_cnp_hdr_valid         (m_roce_cnp_hdr_valid),
        .m_roce_cnp_hdr_ready         (m_roce_cnp_hdr_ready),
        .m_roce_cnp_dest_qp           (m_roce_cnp_dest_qp),
        .m_roce_cnp_icrc              (m_roce_cnp_icrc),

        .busy                         (busy),
        .error_header_early_termination  (error_header_early_termination),
        .error_payload_early_termination (error_payload_early_termination)
    );

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    int error_count = 0;

    // Burst test (Test 5) capture storage
    logic [23:0] burst_cap_qp  [0:BURST_N-1];
    logic [23:0] burst_cap_psn [0:BURST_N-1];
    logic [31:0] burst_cap_icrc[0:BURST_N-1];
    int          burst_cap_cnt;

    // Shared UDP-payload byte buffer used by the generic packet tasks
    logic [7:0]  pkt_buf[0:MAX_PKT-1];

    task wait_clk(input int n = 1);
        repeat (n) @(posedge clk);
    endtask

    task assert_eq32(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got !== exp) begin
            $display("  FAIL  %-30s  got=0x%08h  exp=0x%08h", name, got, exp);
            error_count++;
        end else begin
            $display("  OK    %-30s  0x%08h", name, got);
        end
    endtask

    // Drive one payload beat and wait for tready
    task drive_beat(
        input logic [DATA_WIDTH-1:0] data,
        input logic [KEEP_WIDTH-1:0] keep,
        input logic                  last
    );
        s_udp_payload_axis_tdata  = data;
        s_udp_payload_axis_tkeep  = keep;
        s_udp_payload_axis_tlast  = last;
        s_udp_payload_axis_tvalid = 1'b1;
        do @(posedge clk); while (!s_udp_payload_axis_tready);
        // deassert after acceptance
        s_udp_payload_axis_tvalid = 1'b0;
        s_udp_payload_axis_tlast  = 1'b0;
        s_udp_payload_axis_tkeep  = '0;
        s_udp_payload_axis_tdata  = '0;
    endtask

    // Like drive_beat but keeps tvalid asserted after acceptance (burst mode).
    // The next beat's data should be applied immediately after this task returns.
    task drive_beat_cont(
        input logic [DATA_WIDTH-1:0] data,
        input logic [KEEP_WIDTH-1:0] keep,
        input logic                  last
    );
        s_udp_payload_axis_tdata  = data;
        s_udp_payload_axis_tkeep  = keep;
        s_udp_payload_axis_tlast  = last;
        s_udp_payload_axis_tvalid = 1'b1;
        do @(posedge clk); while (!s_udp_payload_axis_tready);
        // tvalid intentionally left high so the next beat is gapless
    endtask

    // Assert UDP header and wait for ready
    task send_udp_hdr(input logic [15:0] udp_len);
        s_udp_length     = udp_len;
        s_udp_hdr_valid  = 1'b1;
        do @(posedge clk); while (!s_udp_hdr_ready);
        s_udp_hdr_valid  = 1'b0;
    endtask

    // ----------------------------------------------------------------
    // Generic packet infrastructure
    //
    // pkt_buf holds the UDP payload as a raw byte array (big-endian on
    // wire).  send_pkt / send_pkt_payload / send_pkt_payload_cont pack
    // the buffer into DATA_WIDTH-bit beats and compute tkeep for the
    // last beat automatically → no hardcoded beat counts or byte masks.
    //
    // UDP payload byte layout (big-endian on wire, little-endian on bus:
    //   byte N sits at tdata[N%BYTE_LANES*8 +: 8] in beat N/BYTE_LANES)
    // ----------------------------------------------------------------

    // Fill pkt_buf with an RC ACK UDP payload (20 bytes)
    task build_ack_bytes(
        input logic [23:0] dest_qp,
        input logic        ack_req,
        input logic [23:0] psn,
        input logic [ 7:0] syndrome,
        input logic [23:0] msn,
        input logic [31:0] icrc
    );
        pkt_buf[ 0] = 8'h11;            // op_code RC_ACK
        pkt_buf[ 1] = 8'h40;            // MigReq=1
        pkt_buf[ 2] = 8'hFF;            // p_key[15:8]
        pkt_buf[ 3] = 8'hFF;            // p_key[7:0]
        pkt_buf[ 4] = 8'h00;            // FECN/BECN/rsvd
        pkt_buf[ 5] = dest_qp[23:16];
        pkt_buf[ 6] = dest_qp[15:8];
        pkt_buf[ 7] = dest_qp[7:0];
        pkt_buf[ 8] = {ack_req, 7'b0};
        pkt_buf[ 9] = psn[23:16];
        pkt_buf[10] = psn[15:8];
        pkt_buf[11] = psn[7:0];
        pkt_buf[12] = syndrome;
        pkt_buf[13] = msn[23:16];
        pkt_buf[14] = msn[15:8];
        pkt_buf[15] = msn[7:0];
        pkt_buf[16] = icrc[31:24];
        pkt_buf[17] = icrc[23:16];
        pkt_buf[18] = icrc[15:8];
        pkt_buf[19] = icrc[7:0];
    endtask

    // Fill pkt_buf with a CNP UDP payload (24 bytes)
    task build_cnp_bytes(
        input logic [23:0] dest_qp,
        input logic [31:0] icrc
    );
        int i;
        pkt_buf[ 0] = 8'h81;            // op_code CNP
        pkt_buf[ 1] = 8'h00;
        pkt_buf[ 2] = 8'hFF;            // p_key[15:8]
        pkt_buf[ 3] = 8'hFF;            // p_key[7:0]
        pkt_buf[ 4] = 8'h00;            // FECN/BECN/rsvd
        pkt_buf[ 5] = dest_qp[23:16];
        pkt_buf[ 6] = dest_qp[15:8];
        pkt_buf[ 7] = dest_qp[7:0];
        for (i = 8; i < 20; i++) pkt_buf[i] = 8'h00;  // PSN/AckReq + 8B reserved
        pkt_buf[20] = icrc[31:24];
        pkt_buf[21] = icrc[23:16];
        pkt_buf[22] = icrc[15:8];
        pkt_buf[23] = icrc[7:0];
    endtask

    // Drive pkt_buf[0:total-1] as AXI-S beats with UDP header handshake.
    // tkeep on the last beat = {BYTE_LANES{1}} >> (BYTE_LANES - last_b).
    // Deasserts tvalid after the last beat.
    task send_pkt(input int total, input logic [15:0] udp_len);
        logic [DATA_WIDTH-1:0] bdata;
        logic [KEEP_WIDTH-1:0] bkeep;
        int nbeats, last_b, bidx, i, boff;
        nbeats = (total + BYTE_LANES - 1) / BYTE_LANES;
        last_b = total % BYTE_LANES;
        send_udp_hdr(udp_len);
        for (bidx = 0; bidx < nbeats; bidx++) begin
            bdata = '0;
            bkeep = (bidx == nbeats-1 && last_b != 0)
                    ? ({KEEP_WIDTH{1'b1}} >> (BYTE_LANES - last_b))
                    : {KEEP_WIDTH{1'b1}};
            for (i = 0; i < BYTE_LANES; i++) begin
                boff = bidx * BYTE_LANES + i;
                if (boff < total) bdata[i*8 +: 8] = pkt_buf[boff];
            end
            drive_beat(bdata, bkeep, (bidx == nbeats - 1));
        end
    endtask

    // Drive pkt_buf[0:total-1] as AXI-S beats without a header handshake.
    // Deasserts tvalid after the last beat.
    task send_pkt_payload(input int total);
        logic [DATA_WIDTH-1:0] bdata;
        logic [KEEP_WIDTH-1:0] bkeep;
        int nbeats, last_b, bidx, i, boff;
        nbeats = (total + BYTE_LANES - 1) / BYTE_LANES;
        last_b = total % BYTE_LANES;
        for (bidx = 0; bidx < nbeats; bidx++) begin
            bdata = '0;
            bkeep = (bidx == nbeats-1 && last_b != 0)
                    ? ({KEEP_WIDTH{1'b1}} >> (BYTE_LANES - last_b))
                    : {KEEP_WIDTH{1'b1}};
            for (i = 0; i < BYTE_LANES; i++) begin
                boff = bidx * BYTE_LANES + i;
                if (boff < total) bdata[i*8 +: 8] = pkt_buf[boff];
            end
            drive_beat(bdata, bkeep, (bidx == nbeats - 1));
        end
    endtask

    // Same as send_pkt_payload but keeps tvalid high after the last beat
    // so the next packet's first beat follows with no gap (burst mode).
    task send_pkt_payload_cont(input int total);
        logic [DATA_WIDTH-1:0] bdata;
        logic [KEEP_WIDTH-1:0] bkeep;
        int nbeats, last_b, bidx, i, boff;
        nbeats = (total + BYTE_LANES - 1) / BYTE_LANES;
        last_b = total % BYTE_LANES;
        for (bidx = 0; bidx < nbeats; bidx++) begin
            bdata = '0;
            bkeep = (bidx == nbeats-1 && last_b != 0)
                    ? ({KEEP_WIDTH{1'b1}} >> (BYTE_LANES - last_b))
                    : {KEEP_WIDTH{1'b1}};
            for (i = 0; i < BYTE_LANES; i++) begin
                boff = bidx * BYTE_LANES + i;
                if (boff < total) bdata[i*8 +: 8] = pkt_buf[boff];
            end
            drive_beat_cont(bdata, bkeep, (bidx == nbeats - 1));
        end
    endtask

    // ----------------------------------------------------------------
    // RC ACK packet  (UDP payload = 20 bytes, udp_length = 28)
    // ----------------------------------------------------------------
    task send_ack_packet(
        input logic [23:0] dest_qp,
        input logic        ack_req,
        input logic [23:0] psn,
        input logic [ 7:0] syndrome,
        input logic [23:0] msn,
        input logic [31:0] icrc
    );
        build_ack_bytes(dest_qp, ack_req, psn, syndrome, msn, icrc);
        send_pkt(20, 16'd28);
    endtask

    // ----------------------------------------------------------------
    // CNP packet  (UDP payload = 24 bytes, udp_length = 32)
    // ----------------------------------------------------------------
    task send_cnp_packet(
        input logic [23:0] dest_qp,
        input logic [31:0] icrc
    );
        build_cnp_bytes(dest_qp, icrc);
        send_pkt(24, 16'd32);
    endtask

    // ----------------------------------------------------------------
    // Unknown opcode packet (same size as ACK, dropped silently)
    // ----------------------------------------------------------------
    task send_unknown_packet;
        int i;
        pkt_buf[0] = 8'h05;             // unknown op_code
        pkt_buf[1] = 8'h00;
        pkt_buf[2] = 8'hFF;
        pkt_buf[3] = 8'hFF;
        pkt_buf[4] = 8'h00;
        pkt_buf[5] = 8'h42;
        pkt_buf[6] = 8'h42;
        pkt_buf[7] = 8'h42;
        for (i = 8; i < 20; i++) pkt_buf[i] = 8'(i);
        send_pkt(20, 16'd28);
    endtask

    // ----------------------------------------------------------------
    // Wait for a valid on a given signal (with timeout)
    // ----------------------------------------------------------------
    task automatic wait_valid(
        ref   logic        valid_sig,
        input string       name,
        input int          timeout_cycles = 200
    );
        automatic int cnt = 0;
        while (!valid_sig && cnt < timeout_cycles) begin
            @(posedge clk);
            cnt++;
        end
        if (!valid_sig) begin
            $display("  FAIL  %s did not fire within %0d cycles", name, timeout_cycles);
            error_count++;
        end
    endtask

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        $display("=== tb_RoCE_udp_rx start ===");

        // Reset
        rst = 1'b1;
        repeat (5) @(posedge clk);
        @(posedge clk);
        rst = 1'b0;
        wait_clk(3);

        // ==============================================================
        // Test 1: RC ACK  -->  AETH output
        // ==============================================================
        $display("--- Test 1: RC ACK (op=0x11) ---");
        fork
            begin
                send_ack_packet(
                    .dest_qp  (24'h000042),
                    .ack_req  (1'b1),
                    .psn      (24'h000005),
                    .syndrome (8'h60),
                    .msn      (24'h000004),
                    .icrc     (32'hDEADBEEF)
                );
            end
            begin
                wait_valid(m_roce_aeth_hdr_valid, "m_roce_aeth_hdr_valid");
                @(posedge clk);
                assert_eq32("aeth_dest_qp",  {8'd0, m_roce_aeth_dest_qp}, {8'd0, 24'h000042});
                assert_eq32("aeth_psn",      {8'd0, m_roce_aeth_psn},     {8'd0, 24'h000005});
                assert_eq32("aeth_syndrome", {24'd0, m_roce_aeth_syndrome},{24'd0, 8'h60});
                assert_eq32("aeth_msn",      {8'd0, m_roce_aeth_msn},     {8'd0, 24'h000004});
                assert_eq32("aeth_icrc",     m_roce_aeth_icrc,            32'hDEADBEEF);
                // CNP must NOT fire
                if (m_roce_cnp_hdr_valid) begin
                    $display("  FAIL  cnp_hdr_valid unexpectedly asserted");
                    error_count++;
                end else begin
                    $display("  OK    cnp_hdr_valid not asserted (correct)");
                end
            end
        join
        wait_clk(5);

        // ==============================================================
        // Test 2: CNP  -->  CNP output
        // ==============================================================
        $display("--- Test 2: CNP (op=0x81) ---");
        fork
            begin
                send_cnp_packet(
                    .dest_qp (24'h0000BB),
                    .icrc    (32'h12345678)
                );
            end
            begin
                wait_valid(m_roce_cnp_hdr_valid, "m_roce_cnp_hdr_valid");
                @(posedge clk);
                assert_eq32("cnp_dest_qp", {8'd0, m_roce_cnp_dest_qp}, {8'd0, 24'h0000BB});
                assert_eq32("cnp_icrc",    m_roce_cnp_icrc,            32'h12345678);
                // AETH must NOT fire
                if (m_roce_aeth_hdr_valid) begin
                    $display("  FAIL  aeth_hdr_valid unexpectedly asserted");
                    error_count++;
                end else begin
                    $display("  OK    aeth_hdr_valid not asserted (correct)");
                end
            end
        join
        wait_clk(5);

        // ==============================================================
        // Test 3: Unknown opcode  -->  dropped silently
        // ==============================================================
        $display("--- Test 3: unknown opcode (op=0x05, should drop) ---");
        send_unknown_packet();
        wait_clk(20);
        if (!m_roce_aeth_hdr_valid && !m_roce_cnp_hdr_valid) begin
            $display("  OK    no output fired (packet dropped correctly)");
        end else begin
            $display("  FAIL  unexpected output fired for unknown opcode");
            error_count++;
        end

        // ==============================================================
        // Test 4: back-to-back – ACK again after drop
        // ==============================================================
        $display("--- Test 4: ACK after drop ---");
        fork
            begin
                send_ack_packet(
                    .dest_qp  (24'h0000CC),
                    .ack_req  (1'b0),
                    .psn      (24'h00000A),
                    .syndrome (8'h00),
                    .msn      (24'h000009),
                    .icrc     (32'hCAFEBABE)
                );
            end
            begin
                wait_valid(m_roce_aeth_hdr_valid, "m_roce_aeth_hdr_valid (test4)");
                @(posedge clk);
                assert_eq32("aeth_dest_qp (t4)", {8'd0, m_roce_aeth_dest_qp}, {8'd0, 24'h0000CC});
                assert_eq32("aeth_psn     (t4)", {8'd0, m_roce_aeth_psn},     {8'd0, 24'h00000A});
                assert_eq32("aeth_icrc    (t4)", m_roce_aeth_icrc,            32'hCAFEBABE);
            end
        join
        wait_clk(5);

        // ==============================================================
        // Test 5: Burst of BURST_N RC ACK packets – no inter-packet gaps
        //
        // tvalid on the payload bus stays continuously high across all
        // packets.  The header handshake for packet i+1 is launched in a
        // background thread while the last payload beat of packet i is
        // being transferred, so the decoder sees a new header ready to
        // accept the moment tlast is processed.
        //
        // QP  = 0x100 + i
        // PSN = 0x010 + i
        // MSN = 0x00F + i
        // ICRC= 0xA0000000 + i
        // ==============================================================
        $display("--- Test 5: burst of %0d ACK packets (continuous tvalid) ---", BURST_N);
        burst_cap_cnt = 0;
        fork
            // --- Sender: drive all packets with no payload gap ---
            begin : burst_tx
                send_udp_hdr(16'd28);   // header for packet 0
                for (int i = 0; i < BURST_N; i++) begin
                    build_ack_bytes(
                        24'h100 + i, 1'b1,
                        24'h010 + i, 8'h60,
                        24'h00F + i, 32'hA000_0000 + i
                    );
                    if (i < BURST_N - 1) begin
                        // Overlap: kick off next UDP header while sending this packet's beats
                        fork send_udp_hdr(16'd28); join_none
                        send_pkt_payload_cont(20);
                    end else begin
                        send_pkt_payload(20);
                    end
                end
            end : burst_tx

            // --- Receiver: capture every AETH output as it fires ---
            begin : burst_rx
                while (burst_cap_cnt < BURST_N) begin
                    @(posedge clk);
                    if (m_roce_aeth_hdr_valid && m_roce_aeth_hdr_ready) begin
                        burst_cap_qp  [burst_cap_cnt] = m_roce_aeth_dest_qp;
                        burst_cap_psn [burst_cap_cnt] = m_roce_aeth_psn;
                        burst_cap_icrc[burst_cap_cnt] = m_roce_aeth_icrc;
                        burst_cap_cnt++;
                    end
                end
            end : burst_rx
        join
        wait_clk(5);

        // Verify all captured outputs in order
        for (int k = 0; k < BURST_N; k++) begin
            assert_eq32($sformatf("burst_qp  [%02d]", k),
                {8'd0, burst_cap_qp  [k]}, 32'h00000100 + k);
            assert_eq32($sformatf("burst_psn [%02d]", k),
                {8'd0, burst_cap_psn [k]}, 32'h00000010 + k);
            assert_eq32($sformatf("burst_icrc[%02d]", k),
                burst_cap_icrc[k],         32'hA0000000 + k);
        end
        wait_clk(5);

        // ==============================================================
        // Results
        // ==============================================================
        if (error_count == 0)
            $display("=== ALL TESTS PASSED ===");
        else
            $display("=== %0d TEST(S) FAILED ===", error_count);

        $finish;
    end

    // Watchdog
    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end

    // Monitor unexpected errors
    always @(posedge clk) begin
        if (error_header_early_termination)
            $display("  [warn] error_header_early_termination at t=%0t", $time);
        if (error_payload_early_termination)
            $display("  [warn] error_payload_early_termination at t=%0t", $time);
    end

endmodule

`resetall
