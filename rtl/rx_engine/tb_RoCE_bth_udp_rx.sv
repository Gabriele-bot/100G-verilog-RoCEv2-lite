`timescale 1ns/1ps
`default_nettype none

/*
 * Testbench for RoCE_bth_udp_rx
 *
 * DATA_WIDTH=64 is used so the 12-byte BTH header spans two bus cycles,
 * exercising the multi-cycle header-parsing path and the shift register.
 *
 * Frame under test:
 *   UDP payload = BTH (12 bytes) + RoCE payload (8 bytes) = 20 bytes
 *   With DATA_WIDTH=64 (8 bytes/cycle):
 *     Beat 0: BTH bytes 0-7,         tkeep=0xFF, tlast=0
 *     Beat 1: BTH bytes 8-11 + pl 0-3, tkeep=0xFF, tlast=0
 *     Beat 2: pl bytes 4-7 + zeros,   tkeep=0x0F, tlast=1
 *
 *   Expected output payload (via shift register, OFFSET=4):
 *     Beat 0: pl bytes 0-7,           tkeep=0xFF, tlast=1
 */
module tb_RoCE_bth_udp_rx;

    localparam DATA_WIDTH = 64;
    localparam KEEP_WIDTH = DATA_WIDTH/8;
    localparam CLK_PERIOD  = 10;
    localparam int MAX_PL  = 512;   // max payload bytes for vlen tasks

    // ------------------------------------------------------------------
    // Clock / Reset
    // ------------------------------------------------------------------
    logic clk = 1'b0;
    logic rst = 1'b1;

    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------
    // DUT ports
    // ------------------------------------------------------------------
    // UDP input
    logic        s_udp_hdr_valid   = 1'b0;
    logic        s_udp_hdr_ready;
    logic [47:0] s_eth_dest_mac    = 48'hAABBCCDDEEFF;
    logic [47:0] s_eth_src_mac     = 48'h112233445566;
    logic [15:0] s_eth_type        = 16'h0800;
    logic [ 3:0] s_ip_version      = 4'd4;
    logic [ 3:0] s_ip_ihl          = 4'd5;
    logic [ 5:0] s_ip_dscp         = 6'd0;
    logic [ 1:0] s_ip_ecn          = 2'd0;
    logic [15:0] s_ip_length       = 16'd48;
    logic [15:0] s_ip_identification = 16'd0;
    logic [ 2:0] s_ip_flags        = 3'b010;
    logic [12:0] s_ip_fragment_offset = 13'd0;
    logic [ 7:0] s_ip_ttl          = 8'd64;
    logic [ 7:0] s_ip_protocol     = 8'd17;
    logic [15:0] s_ip_header_checksum = 16'd0;
    logic [31:0] s_ip_source_ip    = {8'd10, 8'd0, 8'd0, 8'd1};
    logic [31:0] s_ip_dest_ip      = {8'd10, 8'd0, 8'd0, 8'd2};
    logic [15:0] s_udp_source_port = 16'd12345;
    logic [15:0] s_udp_dest_port   = 16'd4791;
    // s_udp_length = 8B UDP hdr + 12B BTH + 8B payload = 28
    logic [15:0] s_udp_length      = 16'd28;
    logic [15:0] s_udp_checksum    = 16'd0;

    logic [DATA_WIDTH-1:0] s_udp_payload_axis_tdata  = '0;
    logic [KEEP_WIDTH-1:0] s_udp_payload_axis_tkeep  = '0;
    logic                  s_udp_payload_axis_tvalid = 1'b0;
    logic                  s_udp_payload_axis_tready;
    logic                  s_udp_payload_axis_tlast  = 1'b0;
    logic                  s_udp_payload_axis_tuser  = 1'b0;

    // BTH output
    logic        m_roce_bth_hdr_valid;
    logic        m_roce_bth_hdr_ready  = 1'b1;
    logic [47:0] m_eth_dest_mac;
    logic [47:0] m_eth_src_mac;
    logic [15:0] m_eth_type;
    logic [ 3:0] m_ip_version;
    logic [ 3:0] m_ip_ihl;
    logic [ 5:0] m_ip_dscp;
    logic [ 1:0] m_ip_ecn;
    logic [15:0] m_ip_length;
    logic [15:0] m_ip_identification;
    logic [ 2:0] m_ip_flags;
    logic [12:0] m_ip_fragment_offset;
    logic [ 7:0] m_ip_ttl;
    logic [ 7:0] m_ip_protocol;
    logic [15:0] m_ip_header_checksum;
    logic [31:0] m_ip_source_ip;
    logic [31:0] m_ip_dest_ip;
    logic [15:0] m_udp_source_port;
    logic [15:0] m_udp_dest_port;
    logic [15:0] m_udp_length;
    logic [15:0] m_udp_checksum;
    logic [ 7:0] m_roce_bth_op_code;
    logic        m_roce_bth_sol_event;
    logic        m_roce_bth_mig_req;
    logic [ 1:0] m_roce_bth_pad_count;
    logic [ 3:0] m_roce_bth_hdr_version;
    logic [15:0] m_roce_bth_p_key;
    logic        m_roce_bth_fecn;
    logic        m_roce_bth_becn;
    logic [23:0] m_roce_bth_dest_qp;
    logic        m_roce_bth_ack_req;
    logic [23:0] m_roce_bth_psn;

    logic [DATA_WIDTH-1:0] m_roce_bth_payload_axis_tdata;
    logic [KEEP_WIDTH-1:0] m_roce_bth_payload_axis_tkeep;
    logic                  m_roce_bth_payload_axis_tvalid;
    logic                  m_roce_bth_payload_axis_tready = 1'b1;
    logic                  m_roce_bth_payload_axis_tlast;
    logic                  m_roce_bth_payload_axis_tuser;

    logic busy;
    logic error_header_early_termination;
    logic error_payload_early_termination;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    RoCE_bth_udp_rx #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (.*);

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    int error_count = 0;

    // Variable-length test buffers
    logic [7:0] tx_payload_buf [0:MAX_PL-1];
    logic [7:0] rx_payload_buf [0:MAX_PL-1];

    // Latched BTH header (captures the one-cycle hdr_valid pulse)
    logic [ 7:0] latch_op_code;
    logic [15:0] latch_p_key;
    logic [23:0] latch_dest_qp;
    logic        latch_ack_req;
    logic [23:0] latch_psn;
    logic        latch_bth_seen;

    task wait_clk(input int n = 1);
        repeat (n) @(posedge clk);
    endtask

    task assert_eq(input string name, input logic [63:0] got, input logic [63:0] exp);
        if (got !== exp) begin
            $display("FAIL  %s: got=0x%0h  exp=0x%0h", name, got, exp);
            error_count++;
        end else begin
            $display("OK    %s = 0x%0h", name, got);
        end
    endtask

    // ------------------------------------------------------------------
    // Task: send one UDP frame (BTH + payload) and check outputs
    // ------------------------------------------------------------------
    task send_bth_frame(
        input logic [ 7:0] op_code,
        input logic [15:0] p_key,
        input logic [23:0] dest_qp,
        input logic        ack_req,
        input logic [23:0] psn,
        input logic [63:0] payload_data  // 8-byte test payload
    );
        // Build BTH bytes (big-endian over the bus)
        logic [95:0] bth;
        bth[95:88] = op_code;
        bth[87:80] = 8'b1_1_00_0000;  // SE=1, MigReq=1, PadCount=0, HdrVer=0
        bth[79:64] = p_key;
        bth[63:56] = 8'b0_0_000000;   // FECN=0, BECN=0, reserved
        bth[55:32] = dest_qp;
        bth[31:24] = {ack_req, 7'b0};
        bth[23: 0] = psn;

        // Assert UDP header
        @(posedge clk);
        s_udp_hdr_valid = 1'b1;
        wait (s_udp_hdr_ready) @(posedge clk);
        s_udp_hdr_valid = 1'b0;

        // Beat 0: BTH bytes 0-7 (big-endian: byte0 at tdata[7:0])
        @(posedge clk);
        s_udp_payload_axis_tdata  = {bth[31:0], bth[95:32]};  // bytes 7..0 in little-endian bus
        // Re-map: byte offset 0 at tdata[7:0], so beat0 = bth bytes [0..7]
        s_udp_payload_axis_tdata  = { bth[32+:8], bth[40+:8], bth[48+:8], bth[56+:8],
                                       bth[64+:8], bth[72+:8], bth[80+:8], bth[88+:8] };
        s_udp_payload_axis_tkeep  = 8'hFF;
        s_udp_payload_axis_tvalid = 1'b1;
        s_udp_payload_axis_tlast  = 1'b0;
        wait (s_udp_payload_axis_tready) @(posedge clk);

        // Beat 1: BTH bytes 8-11 + payload bytes 0-3
        s_udp_payload_axis_tdata  = { payload_data[7:0], payload_data[15:8],
                                       payload_data[23:16], payload_data[31:24],
                                       bth[0+:8], bth[8+:8], bth[16+:8], bth[24+:8] };
        s_udp_payload_axis_tkeep  = 8'hFF;
        s_udp_payload_axis_tlast  = 1'b0;
        wait (s_udp_payload_axis_tready) @(posedge clk);

        // Beat 2: payload bytes 4-7
        s_udp_payload_axis_tdata  = { 32'h0,
                                       payload_data[39:32], payload_data[47:40],
                                       payload_data[55:48], payload_data[63:56] };
        s_udp_payload_axis_tkeep  = 8'h0F;
        s_udp_payload_axis_tlast  = 1'b1;
        wait (s_udp_payload_axis_tready) @(posedge clk);

        s_udp_payload_axis_tvalid = 1'b0;
        s_udp_payload_axis_tlast  = 1'b0;
        s_udp_payload_axis_tkeep  = '0;

        // Wait for BTH header valid
        wait (m_roce_bth_hdr_valid);
        @(posedge clk);

        $display("--- BTH header received ---");
        assert_eq("op_code",  {56'd0, m_roce_bth_op_code}, {56'd0, op_code});
        assert_eq("p_key",    {48'd0, m_roce_bth_p_key},   {48'd0, p_key});
        assert_eq("dest_qp",  {40'd0, m_roce_bth_dest_qp}, {40'd0, dest_qp});
        assert_eq("ack_req",  {63'd0, m_roce_bth_ack_req}, {63'd0, ack_req});
        assert_eq("psn",      {40'd0, m_roce_bth_psn},     {40'd0, psn});
        assert_eq("sol_event",{63'd0, m_roce_bth_sol_event},64'd1);
        assert_eq("mig_req",  {63'd0, m_roce_bth_mig_req}, 64'd1);
    endtask

    // ------------------------------------------------------------------
    // Task: send BTH frame with arbitrary-length payload
    //
    // Caller fills tx_payload_buf[0:payload_len-1] before calling.
    // Computes udp_length and tkeep automatically.
    // The combined stream (BTH 12B + payload) is packed into 8-byte
    // beats; the last beat carries (total % 8) bytes if non-zero.
    //
    // OFFSET=4: last input beat with tkeep=0xFF triggers an extra
    // shift-register cycle, so the DUT emits one additional output beat.
    // The capture task handles this transparently by watching tlast.
    // ------------------------------------------------------------------
    task send_bth_frame_vlen(
        input logic [ 7:0] op_code,
        input logic [15:0] p_key,
        input logic [23:0] dest_qp,
        input logic        ack_req,
        input logic [23:0] psn,
        input int          payload_len
    );
        logic [7:0] stream [0:MAX_PL+11];
        logic [DATA_WIDTH-1:0] bdata;
        logic [KEEP_WIDTH-1:0] bkeep;
        int total, nbeats, last_b, bidx, i, boff;

        // BTH header (big-endian on wire)
        stream[ 0] = op_code;
        stream[ 1] = 8'b1_1_00_0000;
        stream[ 2] = p_key[15:8];
        stream[ 3] = p_key[7:0];
        stream[ 4] = 8'h00;
        stream[ 5] = dest_qp[23:16];
        stream[ 6] = dest_qp[15:8];
        stream[ 7] = dest_qp[7:0];
        stream[ 8] = {ack_req, 7'b0};
        stream[ 9] = psn[23:16];
        stream[10] = psn[15:8];
        stream[11] = psn[7:0];
        for (i = 0; i < payload_len; i++)
            stream[12 + i] = tx_payload_buf[i];

        total  = 12 + payload_len;
        nbeats = (total + 7) / 8;
        last_b = total % 8;   // 0 means full beat (8 bytes)

        // UDP header handshake
        s_udp_length    = 8 + total;
        s_udp_hdr_valid = 1'b1;
        do @(posedge clk); while (!s_udp_hdr_ready);
        s_udp_hdr_valid = 1'b0;

        // Drive payload beats
        for (bidx = 0; bidx < nbeats; bidx++) begin
            bdata = '0;
            bkeep = (bidx == nbeats-1 && last_b != 0)
                    ? ((1 << last_b) - 1) : {KEEP_WIDTH{1'b1}};
            for (i = 0; i < 8; i++) begin
                boff = bidx * 8 + i;
                if (boff < total)
                    bdata[i*8 +: 8] = stream[boff];
            end
            s_udp_payload_axis_tdata  = bdata;
            s_udp_payload_axis_tkeep  = bkeep;
            s_udp_payload_axis_tlast  = (bidx == nbeats - 1);
            s_udp_payload_axis_tvalid = 1'b1;
            do @(posedge clk); while (!s_udp_payload_axis_tready);
        end
        s_udp_payload_axis_tvalid = 1'b0;
        s_udp_payload_axis_tlast  = 1'b0;
        s_udp_payload_axis_tkeep  = '0;
        s_udp_payload_axis_tdata  = '0;
    endtask

    // Capture all output payload beats into rx_payload_buf
    task capture_bth_payload(output int captured_len);
        bit done;
        int i;
        done = 1'b0;
        captured_len = 0;
        while (!done) begin
            @(posedge clk);
            if (m_roce_bth_payload_axis_tvalid && m_roce_bth_payload_axis_tready) begin
                for (i = 0; i < 8; i++) begin
                    if (m_roce_bth_payload_axis_tkeep[i]) begin
                        rx_payload_buf[captured_len] = m_roce_bth_payload_axis_tdata[i*8 +: 8];
                        captured_len++;
                    end
                end
                if (m_roce_bth_payload_axis_tlast)
                    done = 1'b1;
            end
        end
    endtask

    // Compare rx_payload_buf against tx_payload_buf for exp_len bytes
    task verify_payload(input int exp_len, input int cap_len);
        int k;
        if (cap_len !== exp_len) begin
            $display("  FAIL  payload_len: captured=%0d  expected=%0d", cap_len, exp_len);
            error_count++;
            return;
        end
        $display("  OK    payload_len = %0d bytes", cap_len);
        for (k = 0; k < exp_len; k++) begin
            if (rx_payload_buf[k] !== tx_payload_buf[k]) begin
                $display("  FAIL  payload[%0d]: got=0x%02h  exp=0x%02h",
                    k, rx_payload_buf[k], tx_payload_buf[k]);
                error_count++;
            end
        end
        if (error_count == 0)
            $display("  OK    all %0d payload bytes match", exp_len);
    endtask

    // ------------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------------
    initial begin
        $display("=== tb_RoCE_bth_udp_rx start ===");

        // Reset
        rst = 1'b1;
        wait_clk(5);
        @(posedge clk);
        rst = 1'b0;
        wait_clk(2);

        // Test 1: normal frame
        $display("--- Test 1: normal frame ---");
        send_bth_frame(
            .op_code  (8'h0A),
            .p_key    (16'hFFFF),
            .dest_qp  (24'h000042),
            .ack_req  (1'b1),
            .psn      (24'h000001),
            .payload_data(64'hDEADBEEF_CAFEBABE)
        );

        wait_clk(5);

        // Test 2: back-to-back frames (different PSN)
        $display("--- Test 2: second frame ---");
        send_bth_frame(
            .op_code  (8'h06),
            .p_key    (16'hFFFF),
            .dest_qp  (24'h000042),
            .ack_req  (1'b0),
            .psn      (24'h000002),
            .payload_data(64'h0102030405060708)
        );

        wait_clk(5);

        // ==============================================================
        // Test 3: variable-length payload – 20 bytes
        //   total stream = 12 (BTH) + 20 = 32 B → 4 full input beats
        //   OFFSET=4: last input beat tkeep=0xFF → extra shift-reg cycle
        //   expected output: 3 beats (8+8+4 B)
        // ==============================================================
        $display("--- Test 3: variable-length payload (20 B, extra-cycle path) ---");
        begin : test3
            int cap_len;
            latch_bth_seen = 1'b0;
            for (int i = 0; i < 20; i++)
                tx_payload_buf[i] = 8'(i + 8'hA0);
            fork
                send_bth_frame_vlen(8'h06, 16'hFFFF, 24'h000042, 1'b1, 24'h000010, 20);
                capture_bth_payload(cap_len);
            join
            wait_clk(2);
            assert_eq("op_code", {56'd0, latch_op_code}, {56'd0, 8'h06});
            assert_eq("dest_qp", {40'd0, latch_dest_qp}, {40'd0, 24'h000042});
            assert_eq("psn",     {40'd0, latch_psn},     {40'd0, 24'h000010});
            verify_payload(20, cap_len);
        end : test3
        wait_clk(5);

        // ==============================================================
        // Test 4: variable-length payload – 64 bytes
        //   total stream = 76 B → 10 beats, last beat 4 B (tkeep=0x0F)
        //   no extra-cycle → 8 full output beats
        // ==============================================================
        $display("--- Test 4: variable-length payload (64 B, no extra-cycle) ---");
        begin : test4
            int cap_len;
            latch_bth_seen = 1'b0;
            for (int i = 0; i < 64; i++)
                tx_payload_buf[i] = 8'(i ^ 8'h55);
            fork
                send_bth_frame_vlen(8'h07, 16'hFFFF, 24'h000099, 1'b0, 24'h000020, 64);
                capture_bth_payload(cap_len);
            join
            wait_clk(2);
            assert_eq("op_code", {56'd0, latch_op_code}, {56'd0, 8'h07});
            assert_eq("dest_qp", {40'd0, latch_dest_qp}, {40'd0, 24'h000099});
            assert_eq("psn",     {40'd0, latch_psn},     {40'd0, 24'h000020});
            verify_payload(64, cap_len);
        end : test4
        wait_clk(5);

        // Results
        if (error_count == 0)
            $display("=== ALL TESTS PASSED ===");
        else
            $display("=== %0d TEST(S) FAILED ===", error_count);

        $finish;
    end

    // Watchdog
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

    // Latch BTH header when hdr_valid fires (one-cycle pulse)
    always @(posedge clk) begin
        if (m_roce_bth_hdr_valid && m_roce_bth_hdr_ready) begin
            latch_op_code  = m_roce_bth_op_code;
            latch_p_key    = m_roce_bth_p_key;
            latch_dest_qp  = m_roce_bth_dest_qp;
            latch_ack_req  = m_roce_bth_ack_req;
            latch_psn      = m_roce_bth_psn;
            latch_bth_seen = 1'b1;
        end
    end

    // Monitor payload output
    always @(posedge clk) begin
        if (m_roce_bth_payload_axis_tvalid && m_roce_bth_payload_axis_tready) begin
            $display("  payload beat: data=0x%0h  keep=0x%0h  last=%0b",
                m_roce_bth_payload_axis_tdata,
                m_roce_bth_payload_axis_tkeep,
                m_roce_bth_payload_axis_tlast);
        end
        if (error_header_early_termination)
            $display("  [!] error_header_early_termination");
        if (error_payload_early_termination)
            $display("  [!] error_payload_early_termination");
    end

endmodule

`resetall
