`timescale 1ns/1ps
`default_nettype none

/*
 * Testbench for RoCE_aeth_bth_rx
 */
module tb_RoCE_aeth_bth_rx;

    localparam DATA_WIDTH = 64;
    localparam KEEP_WIDTH = DATA_WIDTH/8;
    localparam CLK_PERIOD = 10;
    localparam int BURST_N = 10;

    // ------------------------------------------------------------------
    // Clock / Reset
    // ------------------------------------------------------------------
    logic clk = 1'b0;
    logic rst = 1'b1;

    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------
    // DUT ports
    // ------------------------------------------------------------------
    logic        s_roce_bth_hdr_valid   = 1'b0;
    logic        s_roce_bth_hdr_ready;
    logic [ 7:0] s_roce_bth_op_code     = 8'h11; // RC_ACK
    logic        s_roce_bth_sol_event   = 1'b0;
    logic        s_roce_bth_mig_req     = 1'b1;
    logic [ 1:0] s_roce_bth_pad_count  = 2'd0;
    logic [ 3:0] s_roce_bth_hdr_version = 4'd0;
    logic [15:0] s_roce_bth_p_key      = 16'hFFFF;
    logic        s_roce_bth_fecn       = 1'b0;
    logic        s_roce_bth_becn       = 1'b0;
    logic [23:0] s_roce_bth_dest_qp   = 24'h000099;
    logic        s_roce_bth_ack_req    = 1'b1;
    logic [23:0] s_roce_bth_psn       = 24'h0000AA;

    logic [DATA_WIDTH-1:0] s_roce_bth_payload_axis_tdata  = '0;
    logic [KEEP_WIDTH-1:0] s_roce_bth_payload_axis_tkeep  = '0;
    logic                  s_roce_bth_payload_axis_tvalid = 1'b0;
    logic                  s_roce_bth_payload_axis_tready;
    logic                  s_roce_bth_payload_axis_tlast  = 1'b0;
    logic                  s_roce_bth_payload_axis_tuser  = 1'b0;

    logic        m_roce_aeth_hdr_valid;
    logic        m_roce_aeth_hdr_ready  = 1'b1;
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
    logic [ 7:0] m_roce_aeth_syndrome;
    logic [23:0] m_roce_aeth_msn;
    logic [31:0] m_roce_icrc;
    logic busy;
    logic error_header_early_termination;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    RoCE_aeth_bth_rx #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (.*);

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    int error_count = 0;

    // Burst test (Test 4) capture storage
    logic [ 7:0] burst_cap_syn [0:BURST_N-1];
    logic [23:0] burst_cap_msn [0:BURST_N-1];
    logic [31:0] burst_cap_icrc[0:BURST_N-1];
    int          burst_cap_cnt;

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

    // Drive one payload beat keeping tvalid asserted (burst mode)
    task drive_beat_cont(
        input logic [DATA_WIDTH-1:0] data,
        input logic [KEEP_WIDTH-1:0] keep,
        input logic                  last
    );
        s_roce_bth_payload_axis_tdata  = data;
        s_roce_bth_payload_axis_tkeep  = keep;
        s_roce_bth_payload_axis_tlast  = last;
        s_roce_bth_payload_axis_tvalid = 1'b1;
        do @(posedge clk); while (!s_roce_bth_payload_axis_tready);
        // tvalid intentionally left high for next beat
    endtask

    // ------------------------------------------------------------------
    // Task: send one BTH header + AETH payload
    // ------------------------------------------------------------------
    task send_aeth_frame(
        input logic [ 7:0] syndrome,
        input logic [23:0] msn,
        input logic [31:0] icrc
    );
        // Drive BTH header sideband
        @(posedge clk);
        s_roce_bth_hdr_valid = 1'b1;
        wait (s_roce_bth_hdr_ready) @(posedge clk);
        s_roce_bth_hdr_valid = 1'b0;

        // One payload beat: syndrome(1B) + MSN(3B) + ICRC(4B)
        // Little-endian bus: byte offset 0 at tdata[7:0]
        @(posedge clk);
        s_roce_bth_payload_axis_tdata = {
            icrc[7:0], icrc[15:8], icrc[23:16], icrc[31:24],   // bytes 7..4 = ICRC big-endian
            msn[7:0],  msn[15:8],  msn[23:16],                 // bytes 3..1 = MSN big-endian
            syndrome                                             // byte 0 = Syndrome
        };
        s_roce_bth_payload_axis_tkeep  = 8'hFF;
        s_roce_bth_payload_axis_tvalid = 1'b1;
        s_roce_bth_payload_axis_tlast  = 1'b1;
        wait (s_roce_bth_payload_axis_tready) @(posedge clk);

        s_roce_bth_payload_axis_tvalid = 1'b0;
        s_roce_bth_payload_axis_tlast  = 1'b0;
        s_roce_bth_payload_axis_tkeep  = '0;

        // Wait for output valid
        wait (m_roce_aeth_hdr_valid);
        @(posedge clk);

        $display("--- AETH header received ---");
        assert_eq("syndrome", {56'd0, m_roce_aeth_syndrome}, {56'd0, syndrome});
        assert_eq("msn",      {40'd0, m_roce_aeth_msn},     {40'd0, msn});
        assert_eq("icrc",     {32'd0, m_roce_icrc},          {32'd0, icrc});
        assert_eq("bth_op_code", {56'd0, m_roce_bth_op_code}, {56'd0, s_roce_bth_op_code});
        assert_eq("bth_psn",     {40'd0, m_roce_bth_psn},     {40'd0, s_roce_bth_psn});
    endtask

    // ------------------------------------------------------------------
    // Task: send a truncated payload (early termination)
    // ------------------------------------------------------------------
    task send_short_frame;
        @(posedge clk);
        s_roce_bth_hdr_valid = 1'b1;
        wait (s_roce_bth_hdr_ready) @(posedge clk);
        s_roce_bth_hdr_valid = 1'b0;

        // Only 3 bytes – too short (AETH needs 8)
        @(posedge clk);
        s_roce_bth_payload_axis_tdata  = 64'hAABBCC00_00000000;
        s_roce_bth_payload_axis_tkeep  = 8'h07;
        s_roce_bth_payload_axis_tvalid = 1'b1;
        s_roce_bth_payload_axis_tlast  = 1'b1;
        wait (s_roce_bth_payload_axis_tready) @(posedge clk);

        s_roce_bth_payload_axis_tvalid = 1'b0;
        s_roce_bth_payload_axis_tlast  = 1'b0;
        wait_clk(3);

        if (error_header_early_termination) begin
            $display("OK    error_header_early_termination asserted as expected");
        end else begin
            $display("FAIL  error_header_early_termination NOT asserted");
            error_count++;
        end
    endtask

    // ------------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------------
    initial begin
        $display("=== tb_RoCE_aeth_bth_rx start ===");

        rst = 1'b1;
        repeat (5) @(posedge clk);
        @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // Test 1: normal AETH
        $display("--- Test 1: normal AETH frame ---");
        send_aeth_frame(
            .syndrome (8'h60),          // ACK syndrome (credit=3, code=ACK)
            .msn      (24'h000007),
            .icrc     (32'hDEADBEEF)
        );

        repeat (3) @(posedge clk);

        // Test 2: back-to-back
        $display("--- Test 2: second AETH frame ---");
        send_aeth_frame(
            .syndrome (8'h00),
            .msn      (24'hABCDEF),
            .icrc     (32'h12345678)
        );

        repeat (3) @(posedge clk);

        // Test 3: early-termination
        $display("--- Test 3: early termination ---");
        send_short_frame();

        repeat (3) @(posedge clk);

        // ==============================================================
        // Test 4: Burst of BURST_N AETH frames – tvalid continuous
        //
        // AETH payload = 1 beat (8B, tkeep=0xFF, tlast=1).
        // The BTH header handshake for frame i+1 is forked concurrently
        // with the single payload beat of frame i, so the decoder sees
        // back-to-back frames with no idle on the payload bus.
        //
        // syndrome = 0x60 + i,  msn = 0x000010 + i,  icrc = 0xB0000000 + i
        // ==============================================================
        $display("--- Test 4: burst of %0d AETH frames (continuous tvalid) ---", BURST_N);
        burst_cap_cnt = 0;
        fork
            // Sender: BURST_N frames, payload bus stays high between frames
            begin : burst_tx
                logic [ 7:0] b_syn;
                logic [23:0] b_msn;
                logic [31:0] b_ic;

                // BTH header for frame 0
                s_roce_bth_hdr_valid = 1'b1;
                do @(posedge clk); while (!s_roce_bth_hdr_ready);
                s_roce_bth_hdr_valid = 1'b0;

                for (int i = 0; i < BURST_N; i++) begin
                    b_syn = 8'h60  + i;
                    b_msn = 24'h000010 + i;
                    b_ic  = 32'hB000_0000 + i;

                    if (i < BURST_N - 1) begin
                        // Overlap: launch next BTH header while sending this frame's beat
                        fork
                            begin
                                s_roce_bth_hdr_valid = 1'b1;
                                do @(posedge clk); while (!s_roce_bth_hdr_ready);
                                s_roce_bth_hdr_valid = 1'b0;
                            end
                        join_none
                        drive_beat_cont(
                            {b_ic[7:0], b_ic[15:8], b_ic[23:16], b_ic[31:24],
                             b_msn[7:0], b_msn[15:8], b_msn[23:16], b_syn},
                            8'hFF, 1'b1
                        );
                    end else begin
                        // Last frame: deassert tvalid normally
                        s_roce_bth_payload_axis_tdata  = {
                            b_ic[7:0], b_ic[15:8], b_ic[23:16], b_ic[31:24],
                            b_msn[7:0], b_msn[15:8], b_msn[23:16], b_syn};
                        s_roce_bth_payload_axis_tkeep  = 8'hFF;
                        s_roce_bth_payload_axis_tlast  = 1'b1;
                        s_roce_bth_payload_axis_tvalid = 1'b1;
                        do @(posedge clk); while (!s_roce_bth_payload_axis_tready);
                        s_roce_bth_payload_axis_tvalid = 1'b0;
                        s_roce_bth_payload_axis_tlast  = 1'b0;
                        s_roce_bth_payload_axis_tkeep  = '0;
                        s_roce_bth_payload_axis_tdata  = '0;
                    end
                end
            end : burst_tx

            // Capture every AETH output as it fires
            begin : burst_rx
                while (burst_cap_cnt < BURST_N) begin
                    @(posedge clk);
                    if (m_roce_aeth_hdr_valid && m_roce_aeth_hdr_ready) begin
                        burst_cap_syn [burst_cap_cnt] = m_roce_aeth_syndrome;
                        burst_cap_msn [burst_cap_cnt] = m_roce_aeth_msn;
                        burst_cap_icrc[burst_cap_cnt] = m_roce_icrc;
                        burst_cap_cnt++;
                    end
                end
            end : burst_rx
        join
        repeat (3) @(posedge clk);

        // Verify captured outputs in order
        for (int k = 0; k < BURST_N; k++) begin
            assert_eq($sformatf("burst_syn [%02d]", k),
                {56'd0, burst_cap_syn [k]}, 64'h60 + k);
            assert_eq($sformatf("burst_msn [%02d]", k),
                {40'd0, burst_cap_msn [k]}, 64'h10 + k);
            assert_eq($sformatf("burst_icrc[%02d]", k),
                {32'd0, burst_cap_icrc[k]}, 64'hB0000000 + k);
        end
        repeat (3) @(posedge clk);

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

    // Monitor errors
    always @(posedge clk) begin
        if (error_header_early_termination)
            $display("  [event] error_header_early_termination at t=%0t", $time);
    end

endmodule

`resetall
