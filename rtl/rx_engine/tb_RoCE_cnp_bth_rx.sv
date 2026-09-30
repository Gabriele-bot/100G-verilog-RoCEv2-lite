`timescale 1ns/1ps
`default_nettype none

/*
 * Testbench for RoCE_cnp_bth_rx
 *
 * DATA_WIDTH=64 (8 bytes/cycle).
 * CNP BTH payload = 8 reserved bytes + 4 ICRC bytes = 12 bytes → 2 beats.
 *
 *   Beat 0: reserved bytes 0-7,  tkeep=0xFF, tlast=0
 *   Beat 1: ICRC bytes 0-3 + zeros, tkeep=0x0F, tlast=1
 *
 * Test 1: normal CNP frame – check ICRC extracted correctly.
 * Test 2: back-to-back frames.
 * Test 3: early-termination error.
 */
module tb_RoCE_cnp_bth_rx;

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
    logic        s_roce_bth_hdr_valid    = 1'b0;
    logic        s_roce_bth_hdr_ready;
    logic [ 7:0] s_roce_bth_op_code      = 8'h81; // CNP opcode
    logic        s_roce_bth_sol_event    = 1'b0;
    logic        s_roce_bth_mig_req      = 1'b0;
    logic [ 1:0] s_roce_bth_pad_count   = 2'd0;
    logic [ 3:0] s_roce_bth_hdr_version  = 4'd0;
    logic [15:0] s_roce_bth_p_key       = 16'hFFFF;
    logic        s_roce_bth_fecn        = 1'b0;
    logic        s_roce_bth_becn        = 1'b0;
    logic [23:0] s_roce_bth_dest_qp    = 24'h000055;
    logic        s_roce_bth_ack_req     = 1'b0;
    logic [23:0] s_roce_bth_psn        = 24'h000000;

    logic [DATA_WIDTH-1:0] s_roce_bth_payload_axis_tdata  = '0;
    logic [KEEP_WIDTH-1:0] s_roce_bth_payload_axis_tkeep  = '0;
    logic                  s_roce_bth_payload_axis_tvalid = 1'b0;
    logic                  s_roce_bth_payload_axis_tready;
    logic                  s_roce_bth_payload_axis_tlast  = 1'b0;
    logic                  s_roce_bth_payload_axis_tuser  = 1'b0;

    logic        m_roce_cnp_hdr_valid;
    logic        m_roce_cnp_hdr_ready   = 1'b1;
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
    logic [31:0] m_roce_icrc;
    logic busy;
    logic error_header_early_termination;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    RoCE_cnp_bth_rx #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (.*);

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    int error_count = 0;

    // Burst test (Test 4) capture storage
    logic [23:0] burst_cap_qp  [0:BURST_N-1];
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
    // Task: send one CNP frame and check ICRC
    // ------------------------------------------------------------------
    task send_cnp_frame(
        input logic [23:0] dest_qp,
        input logic [31:0] icrc
    );
        s_roce_bth_dest_qp = dest_qp;

        // Assert BTH header
        @(posedge clk);
        s_roce_bth_hdr_valid = 1'b1;
        wait (s_roce_bth_hdr_ready) @(posedge clk);
        s_roce_bth_hdr_valid = 1'b0;

        // Beat 0: 8 reserved bytes (all zero)
        @(posedge clk);
        s_roce_bth_payload_axis_tdata  = 64'h0000_0000_0000_0000;
        s_roce_bth_payload_axis_tkeep  = 8'hFF;
        s_roce_bth_payload_axis_tvalid = 1'b1;
        s_roce_bth_payload_axis_tlast  = 1'b0;
        wait (s_roce_bth_payload_axis_tready) @(posedge clk);

        // Beat 1: ICRC (4 bytes, big-endian) + 4 don't-care bytes
        // Byte offset 8 at tdata[7:0] → ICRC[31:24] at tdata[7:0]
        s_roce_bth_payload_axis_tdata  = { 32'h0,
                                            icrc[7:0], icrc[15:8],
                                            icrc[23:16], icrc[31:24] };
        s_roce_bth_payload_axis_tkeep  = 8'h0F;
        s_roce_bth_payload_axis_tlast  = 1'b1;
        wait (s_roce_bth_payload_axis_tready) @(posedge clk);

        s_roce_bth_payload_axis_tvalid = 1'b0;
        s_roce_bth_payload_axis_tlast  = 1'b0;
        s_roce_bth_payload_axis_tkeep  = '0;

        // Wait for output valid
        wait (m_roce_cnp_hdr_valid);
        @(posedge clk);

        $display("--- CNP header received ---");
        assert_eq("icrc",     {32'd0, m_roce_icrc},          {32'd0, icrc});
        assert_eq("op_code",  {56'd0, m_roce_bth_op_code},   {56'd0, 8'h81});
        assert_eq("dest_qp",  {40'd0, m_roce_bth_dest_qp},   {40'd0, dest_qp});
    endtask

    // ------------------------------------------------------------------
    // Task: early-termination (only 4 bytes – missing ICRC)
    // ------------------------------------------------------------------
    task send_short_frame;
        @(posedge clk);
        s_roce_bth_hdr_valid = 1'b1;
        wait (s_roce_bth_hdr_ready) @(posedge clk);
        s_roce_bth_hdr_valid = 1'b0;

        // Only 4 bytes – way short of the required 12
        @(posedge clk);
        s_roce_bth_payload_axis_tdata  = 64'h0;
        s_roce_bth_payload_axis_tkeep  = 8'h0F;
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
        $display("=== tb_RoCE_cnp_bth_rx start ===");

        rst = 1'b1;
        repeat (5) @(posedge clk);
        @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // Test 1
        $display("--- Test 1: normal CNP ---");
        send_cnp_frame(.dest_qp(24'h000055), .icrc(32'hDEADBEEF));

        repeat (3) @(posedge clk);

        // Test 2: back-to-back, different QP
        $display("--- Test 2: second CNP ---");
        send_cnp_frame(.dest_qp(24'h0000AA), .icrc(32'h12345678));

        repeat (3) @(posedge clk);

        // Test 3: early termination
        $display("--- Test 3: early termination ---");
        send_short_frame();

        repeat (3) @(posedge clk);

        // ==============================================================
        // Test 4: Burst of BURST_N CNP frames – tvalid continuous
        //
        // CNP payload = 2 beats:
        //   Beat 0: 8 reserved bytes (tkeep=0xFF, tlast=0)  → drive_beat_cont
        //   Beat 1: ICRC 4B (tkeep=0x0F, tlast=1)
        // The BTH header for frame i+1 is forked concurrently with
        // beat 1 of frame i, keeping the payload bus gapless.
        //
        // dest_qp fixed at module-level default (0x000055)
        // icrc = 0xC0000000 + i
        // ==============================================================
        $display("--- Test 4: burst of %0d CNP frames (continuous tvalid) ---", BURST_N);
        burst_cap_cnt = 0;
        fork
            // Sender: BURST_N frames, payload bus stays high between frames
            begin : burst_tx
                logic [31:0] b_ic;

                // BTH header for frame 0
                s_roce_bth_hdr_valid = 1'b1;
                do @(posedge clk); while (!s_roce_bth_hdr_ready);
                s_roce_bth_hdr_valid = 1'b0;

                for (int i = 0; i < BURST_N; i++) begin
                    b_ic = 32'hC000_0000 + i;

                    // Beat 0: 8 reserved bytes, keep tvalid high
                    drive_beat_cont(64'h0, 8'hFF, 1'b0);

                    // Beat 1 (tlast, ICRC): overlap next BTH header
                    if (i < BURST_N - 1) begin
                        fork
                            begin
                                s_roce_bth_hdr_valid = 1'b1;
                                do @(posedge clk); while (!s_roce_bth_hdr_ready);
                                s_roce_bth_hdr_valid = 1'b0;
                            end
                        join_none
                        drive_beat_cont(
                            {32'h0, b_ic[7:0], b_ic[15:8], b_ic[23:16], b_ic[31:24]},
                            8'h0F, 1'b1
                        );
                    end else begin
                        // Last frame: deassert tvalid normally
                        s_roce_bth_payload_axis_tdata  = {
                            32'h0, b_ic[7:0], b_ic[15:8], b_ic[23:16], b_ic[31:24]};
                        s_roce_bth_payload_axis_tkeep  = 8'h0F;
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

            // Capture every CNP output as it fires
            begin : burst_rx
                while (burst_cap_cnt < BURST_N) begin
                    @(posedge clk);
                    if (m_roce_cnp_hdr_valid && m_roce_cnp_hdr_ready) begin
                        burst_cap_qp  [burst_cap_cnt] = m_roce_bth_dest_qp;
                        burst_cap_icrc[burst_cap_cnt] = m_roce_icrc;
                        burst_cap_cnt++;
                    end
                end
            end : burst_rx
        join
        repeat (3) @(posedge clk);

        // Verify captured outputs in order
        for (int k = 0; k < BURST_N; k++) begin
            assert_eq($sformatf("burst_qp  [%02d]", k),
                {40'd0, burst_cap_qp  [k]}, {40'd0, 24'h000055});
            assert_eq($sformatf("burst_icrc[%02d]", k),
                {32'd0, burst_cap_icrc[k]}, 64'hC0000000 + k);
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
