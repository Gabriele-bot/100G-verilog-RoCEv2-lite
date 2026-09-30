`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Testbench for axi_seg_2_axis_v2.
 *
 * Drives DCMAC-style segmented AXI input, collects plain AXIS output, and
 * verifies that every output packet matches the corresponding input packet
 * in both data and arrival order.
 *
 * Byte layout per segment (128-bit / 16-byte):
 *   tdata[8*b +: 8]  = byte b of segment  (b=0 is first byte, b=15 is last)
 *   MTY = number of empty bytes at the HIGH end of the last segment
 *         (MTY=0 → all 16 bytes valid, MTY=15 → only byte 0 valid)
 *
 * Packet encoding:
 *   Bytes [3:0] = 32-bit sequence number (big-endian)
 *   Remaining   = byte index within packet (mod 256)
 *
 * Generator API:
 *   send_stream(pkts, back_to_back)
 *     back_to_back=1: packets packed consecutively with no idle gaps.
 *                     The next packet's SOP immediately follows the previous EOP.
 *     back_to_back=0: idle beats inserted between packets; per the AMD-Xilinx
 *                     DCMAC spec, each packet always starts at segment 0
 *                     when idle cycles precede it.
 *
 *   send_packet(seq, size)
 *     Single-packet convenience. Always flushes before/after, so the
 *     packet starts at seg 0. Insert idle_beats() between calls as needed.
 */
module tb_axi_seg_2_axis;

    // ---------------------------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------------------------
    localparam real S_CLK_PERIOD = 1000/391.0; // ns – ~391 MHz (DCMAC side)
    localparam real M_CLK_PERIOD = 1000/411.0; // ns – ~411 MHz (output side)
    localparam int  DRAIN_TIMEOUT_CYCLES = 100_000;

    // ---------------------------------------------------------------------------
    // DUT signals
    // ---------------------------------------------------------------------------
    logic           s_clk = 0, s_rst = 1;
    logic           m_clk = 0, m_rst = 1;

    logic [1023:0]  s_axis_seg_tdata   = '0;
    wire            s_axis_seg_tready;
    logic           s_axis_seg_tvalid  = '0;
    logic [7:0]     s_axis_seg_tuser_ena = '0;
    logic [7:0]     s_axis_seg_tuser_sop = '0;
    logic [7:0]     s_axis_seg_tuser_eop = '0;
    logic [7:0]     s_axis_seg_tuser_err = '0;
    logic [31:0]    s_axis_seg_tuser_mty = '0;

    wire [1023:0]   m_axis_tdata;
    wire [127:0]    m_axis_tkeep;
    wire            m_axis_tvalid;
    logic           m_axis_tready = 1; // always ready by default; tests can override
    wire            m_axis_tlast;
    wire            m_axis_tuser;

    // ---------------------------------------------------------------------------
    // DUT
    // ---------------------------------------------------------------------------
    axi_seg_2_axis #(
        .AXIS_FIFO_DEPTH   (8192),
        .ASYNC_FIFO        (1),
        .INPUT_REGS        (0)
    ) dut (
        .s_clk               (s_clk),
        .s_rst               (s_rst),
        .s_axis_seg_tdata    (s_axis_seg_tdata),
        .s_axis_seg_tready   (s_axis_seg_tready),
        .s_axis_seg_tvalid   (s_axis_seg_tvalid),
        .s_axis_seg_tuser_ena(s_axis_seg_tuser_ena),
        .s_axis_seg_tuser_sop(s_axis_seg_tuser_sop),
        .s_axis_seg_tuser_eop(s_axis_seg_tuser_eop),
        .s_axis_seg_tuser_err(s_axis_seg_tuser_err),
        .s_axis_seg_tuser_mty(s_axis_seg_tuser_mty),
        .m_clk               (m_clk),
        .m_rst               (m_rst),
        .m_axis_tdata        (m_axis_tdata),
        .m_axis_tkeep        (m_axis_tkeep),
        .m_axis_tvalid       (m_axis_tvalid),
        .m_axis_tready       (m_axis_tready),
        .m_axis_tlast        (m_axis_tlast),
        .m_axis_tuser        (m_axis_tuser)
    );

    // ---------------------------------------------------------------------------
    // Clocks
    // ---------------------------------------------------------------------------
    always #(S_CLK_PERIOD / 2.0) s_clk = ~s_clk;
    always #(M_CLK_PERIOD / 2.0) m_clk = ~m_clk;

    // ---------------------------------------------------------------------------
    // Scoreboard
    // ---------------------------------------------------------------------------
    typedef byte unsigned bu_t;
    typedef bu_t bu_q_t[$];

    bu_q_t scoreboard[$]; // queue of expected packets (each = byte array)
    int    pkts_sent   = 0;
    int    pkts_recvd  = 0;
    int    errors      = 0;

    // ---------------------------------------------------------------------------
    // Output checker (runs on m_clk)
    // ---------------------------------------------------------------------------
    bu_q_t rx_buf; // accumulates bytes for the packet currently being received

    always @(posedge m_clk) begin
        if (!m_rst && m_axis_tvalid && m_axis_tready) begin
            // Collect all bytes where tkeep=1
            for (int b = 0; b < 128; b++) begin
                if (m_axis_tkeep[b]) begin
                    rx_buf.push_back(m_axis_tdata[8*b +: 8]);
                end
            end

            if (m_axis_tlast) begin
                if (scoreboard.size() == 0) begin
                    $error("[%0t ns] Received unexpected extra packet (size=%0d)",
                        $time, rx_buf.size());
                    errors++;
                end else begin
                    automatic bu_q_t exp = scoreboard.pop_front();
                    pkts_recvd++;

                    if (rx_buf.size() != exp.size()) begin
                        $error("[%0t ns] Pkt#%0d size mismatch: got %0d B, expected %0d B",
                            $time, pkts_recvd, rx_buf.size(), exp.size());
                        errors++;
                    end else begin
                        automatic int mismatches = 0;
                        for (int i = 0; i < int'(rx_buf.size()); i++) begin
                            if (rx_buf[i] !== exp[i]) begin
                                if (mismatches == 0)
                                    $error("[%0t ns] Pkt#%0d data error at byte[%0d]: got 0x%02x exp 0x%02x",
                                        $time, pkts_recvd, i, rx_buf[i], exp[i]);
                                mismatches++;
                            end
                        end
                        if (mismatches > 1)
                            $error("[%0t ns] Pkt#%0d had %0d total byte mismatches",
                                $time, pkts_recvd, mismatches);
                        if (mismatches > 0)
                            errors++;
                        else
                            $display("[%0t ns] Pkt#%0d OK (%0d bytes)",
                                $time, pkts_recvd, rx_buf.size());
                    end
                end
                rx_buf = {};
            end
        end
    end

    // ---------------------------------------------------------------------------
    // Helper: build a packet byte array
    //   Bytes 0-3 : seq (big-endian)
    //   Bytes 4.. : byte-index mod 256
    // ---------------------------------------------------------------------------
    function automatic bu_q_t make_pkt(int seq, int size);
        bu_q_t p;
        p = {};
        p.push_back(bu_t'((seq >> 24) & 8'hFF));
        p.push_back(bu_t'((seq >> 16) & 8'hFF));
        p.push_back(bu_t'((seq >>  8) & 8'hFF));
        p.push_back(bu_t'( seq        & 8'hFF));
        for (int i = 4; i < size; i++)
            p.push_back(bu_t'(i & 8'hFF));
        return p;
    endfunction

    // ---------------------------------------------------------------------------
    // idle_beats: drive N idle (tvalid=0) clock cycles on s_clk
    // ---------------------------------------------------------------------------
    task automatic idle_beats(int n = 1);
        repeat (n) begin
            @(posedge s_clk); #1;
            s_axis_seg_tvalid    <= 0;
            s_axis_seg_tuser_ena <= '0;
            s_axis_seg_tuser_sop <= '0;
            s_axis_seg_tuser_eop <= '0;
            s_axis_seg_tuser_err <= '0;
            s_axis_seg_tuser_mty <= '0;
        end
    endtask

    // ---------------------------------------------------------------------------
    // Stateful beat-builder
    //
    // These module-level registers hold one beat that is being assembled
    // before it is driven to the bus. Tasks share this state across calls,
    // which is what makes back-to-back packing work.
    // ---------------------------------------------------------------------------
    logic [1023:0] gen_bd  = '0;
    logic [7:0]    gen_be  = '0;   // ena
    logic [7:0]    gen_bs  = '0;   // sop
    logic [7:0]    gen_bo  = '0;   // eop
    logic [31:0]   gen_bm  = '0;   // mty
    int            gen_seg = 0;    // next free segment index (0-7)
    bit            gen_dirty = 0;  // true when beat buffer has unsent data

    // Drive the current beat buffer to the bus (1 clock cycle) and reset state.
    task automatic gen_flush_beat();
        @(posedge s_clk); #1;
        s_axis_seg_tdata     <= gen_bd;
        s_axis_seg_tuser_ena <= gen_be;
        s_axis_seg_tuser_sop <= gen_bs;
        s_axis_seg_tuser_eop <= gen_bo;
        s_axis_seg_tuser_err <= '0;
        s_axis_seg_tuser_mty <= gen_bm;
        s_axis_seg_tvalid    <= 1;
        gen_bd    = '0;
        gen_be    = '0;
        gen_bs    = '0;
        gen_bo    = '0;
        gen_bm    = '0;
        gen_seg   = 0;
        gen_dirty = 0;
    endtask

    // Flush only if there is pending data.
    task automatic gen_flush_if_dirty();
        if (gen_dirty) gen_flush_beat();
    endtask

    // Append one packet to the current beat stream.
    //
    // SOP/EOP/MTY/ENA are computed automatically from pkt.size().
    // Beats are flushed as soon as they fill up (gen_seg reaches 8).
    // The last partial beat is left buffered (gen_dirty=1) so the caller
    // can either pack more packets (back-to-back) or flush at will.
    //
    // After this task returns, gen_seg points to the first FREE segment
    // in the pending beat (or 0 if the last beat was exactly full and
    // was already flushed).
    task automatic gen_add_packet(input bu_q_t pkt);
        int pkt_size = int'(pkt.size());
        int byte_idx = 0;
        int bytes_this_seg;

        gen_bs[gen_seg] = 1'b1;  // SOP at current free segment
        gen_dirty       = 1;

        while (byte_idx < pkt_size) begin
            bytes_this_seg = ((pkt_size - byte_idx) >= 16) ? 16 : (pkt_size - byte_idx);

            gen_be[gen_seg] = 1'b1;
            for (int b = 0; b < bytes_this_seg; b++)
                gen_bd[128*gen_seg + 8*b +: 8] = pkt[byte_idx + b];
            byte_idx += bytes_this_seg;

            if (byte_idx >= pkt_size) begin
                // Last segment of this packet: mark EOP and MTY
                gen_bo[gen_seg]         = 1'b1;
                gen_bm[4*gen_seg +: 4] = 4'(16 - bytes_this_seg);
            end

            gen_seg++;
            // Flush as soon as the beat is full (8 segments consumed).
            // gen_flush_beat() resets gen_dirty=0, so if more bytes remain
            // (packet continues into the next beat) we re-arm gen_dirty so
            // the caller's gen_flush_if_dirty() will send that continuation beat.
            if (gen_seg >= 8) begin
                gen_flush_beat();
                if (byte_idx < pkt_size) gen_dirty = 1;
            end
        end
    endtask

    // ---------------------------------------------------------------------------
    // send_stream: drive a list of packets with selectable gap mode.
    //
    //   back_to_back = 1
    //     All packets are packed consecutively in the segment stream.
    //     A new packet's SOP immediately follows the previous packet's EOP
    //     within the same beat (if space allows), with no idle cycles.
    //
    //   back_to_back = 0  (DCMAC idle rule)
    //     Two idle beats are inserted between packets.
    //     Per the AMD-Xilinx DCMAC specification, whenever idle cycles
    //     precede a packet, that packet MUST start at segment 0.
    //     This is enforced by flushing the current beat before each
    //     new packet, leaving gen_seg=0 for the next gen_add_packet call.
    // ---------------------------------------------------------------------------
    task automatic send_stream(input bu_q_t pkts[$], input bit back_to_back = 0);
        if (back_to_back) begin
            // Pack all packets consecutively; flush only the final partial beat.
            foreach (pkts[i]) gen_add_packet(pkts[i]);
            gen_flush_if_dirty();
        end else begin
            foreach (pkts[i]) begin
                if (i > 0) idle_beats(2);     // gap between packets
                gen_flush_if_dirty();          // guarantee gen_seg=0 for next packet
                gen_add_packet(pkts[i]);
                gen_flush_if_dirty();          // flush EOP beat immediately
            end
        end
    endtask

    // ---------------------------------------------------------------------------
    // send_packet: convenience wrapper for a single packet in idle mode.
    //   Always starts at seg 0 (flushes any pending beat first).
    //   Insert idle_beats() between calls to add gaps.
    // ---------------------------------------------------------------------------
    task automatic send_packet(int seq, int size);
        automatic bu_q_t pkt = make_pkt(seq, size);
        scoreboard.push_back(pkt);
        pkts_sent++;
        gen_flush_if_dirty();    // ensure seg 0 start (AMD-Xilinx spec)
        gen_add_packet(pkt);
        gen_flush_if_dirty();    // flush EOP beat
    endtask

    // ---------------------------------------------------------------------------
    // send_back_to_back: build N packets from a generic sizes list and stream
    //   them with no idle gaps.  Packet i gets sequence number (base_seq + i).
    //
    //   Example – send 3 packets of different sizes back-to-back:
    //     send_back_to_back(500, '{142, 92, 138});
    // ---------------------------------------------------------------------------
    task automatic send_back_to_back(input int base_seq, input int sizes[$]);
        automatic bu_q_t pkts[$];
        foreach (sizes[i]) begin
            automatic bu_q_t pkt = make_pkt(base_seq + i, sizes[i]);
            scoreboard.push_back(pkt);
            pkts_sent++;
            pkts.push_back(pkt);
        end
        send_stream(pkts, .back_to_back(1));
    endtask

    // ---------------------------------------------------------------------------
    // send_idle_separated: build N packets from a generic sizes list and send
    //   them one by one with 'gap' idle beats between each (starts at seg 0
    //   per the AMD-Xilinx DCMAC spec).  Packet i gets sequence (base_seq + i).
    //
    //   Example – send 5 packets with 3 idle beats between each:
    //     send_idle_separated(100, '{64, 128, 256, 64, 512}, .gap(3));
    // ---------------------------------------------------------------------------
    task automatic send_idle_separated(input int base_seq, input int sizes[$], input int gap = 2);
        foreach (sizes[i]) begin
            if (i > 0) idle_beats(gap);
            send_packet(base_seq + i, sizes[i]);
        end
    endtask

    // ---------------------------------------------------------------------------
    // wait_drain: spin on m_clk until all sent packets are received or timeout.
    // ---------------------------------------------------------------------------
    task automatic wait_drain(int cycles = DRAIN_TIMEOUT_CYCLES);
        int cnt = 0;
        while (pkts_recvd < pkts_sent && cnt < cycles) begin
            @(posedge m_clk);
            cnt++;
        end
        if (cnt >= cycles) begin
            $error("Drain timeout: sent=%0d received=%0d", pkts_sent, pkts_recvd);
            errors++;
        end
    endtask

    // ---------------------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------------------
    localparam int N_PACKETS_SENT_PER_TEST = 50;
    initial begin
        // --- Reset ---
        s_rst = 1; m_rst = 1;
        repeat (20) @(posedge s_clk);
        s_rst = 0;
        repeat (20) @(posedge m_clk);
        m_rst = 0;
        repeat (5)  @(posedge s_clk);

        // ===========================================================
        // Test 1: Sequential minimum-size packets (64 B = 4 segments)
        //         Idle beats between each → every packet starts at seg 0
        // ===========================================================
        $display("--- Test 1: Sequential 64-byte packets (idle between) ---");
        for (int i = 0; i < N_PACKETS_SENT_PER_TEST; i++) begin
            send_packet(i, 64);
            idle_beats(2);
        end
        wait_drain();
        $display("Test 1 done. errors so far: %0d", errors);
        idle_beats(20);

        // ===========================================================
        // Test 2: Multi-beat packets (256 B = 16 segments = 2 beats)
        // ===========================================================
        $display("--- Test 2: Multi-beat 256-byte packets (idle between) ---");
        for (int i = 0; i < N_PACKETS_SENT_PER_TEST; i++) begin
            send_packet(100 + i, 256);
            idle_beats(3);
        end
        wait_drain();
        $display("Test 2 done. errors so far: %0d", errors);
        idle_beats(20);

        // ===========================================================
        // Test 3: Non-aligned sizes (last segment not fully used)
        // ===========================================================
        $display("--- Test 3: Non-16-aligned sizes ---");
        begin
            int sizes[20] = '{64, 65, 79, 128, 130, 255, 300, 430, 512,
                               513, 600, 700, 800, 900, 1000, 1023, 1024,
                               1025, 1500, 2000};
            for (int i = 0; i < 20; i++) begin
                send_packet(200 + i, sizes[i]);
                idle_beats(3);
            end
        end
        wait_drain();
        $display("Test 3 done. errors so far: %0d", errors);
        idle_beats(20);

        // ===========================================================
        // Test 4: EOP of packet A and SOP of packet B in the same beat.
        //   pktA = 80 B  → segs 0-4  (EOP at seg 4)
        //   pktB = 64 B  → SOP at seg 5, spans into next beat (EOP at seg 0)
        //
        //   send_stream with back_to_back=1 computes SOP/EOP/MTY/ENA
        //   automatically and packs pktB right after pktA's EOP.
        // ===========================================================
        $display("--- Test 4: EOP+SOP in same beat (back-to-back) ---");
        begin
            automatic bu_q_t pkts[$];
            pkts.push_back(make_pkt(300, 80));
            pkts.push_back(make_pkt(301, 64));
            foreach (pkts[i]) begin
                scoreboard.push_back(pkts[i]);
                pkts_sent++;
            end
            send_stream(pkts, .back_to_back(1));
        end
        idle_beats(2);
        wait_drain();
        $display("Test 4 done. errors so far: %0d", errors);
        idle_beats(20);

        // ===========================================================
        // Test 5: Two complete 64-byte packets packed in a single beat.
        //   pktA = 64 B → segs 0-3  (SOP@0, EOP@3)
        //   pktB = 64 B → segs 4-7  (SOP@4, EOP@7)  ← same beat
        // ===========================================================
        $display("--- Test 5: Two 64-byte packets in one beat ---");
        begin
            automatic bu_q_t pkts[$];
            pkts.push_back(make_pkt(400, 64));
            pkts.push_back(make_pkt(401, 64));
            foreach (pkts[i]) begin
                scoreboard.push_back(pkts[i]);
                pkts_sent++;
            end
            send_stream(pkts, .back_to_back(1));
        end
        idle_beats(2);
        wait_drain();
        $display("Test 5 done. errors so far: %0d", errors);
        idle_beats(20);

        // ===========================================================
        // Test 6: Back-to-back packets, one frame boundary per beat.
        //
        //
        //   send_stream computes every SOP/EOP/MTY/ENA automatically.
        // ===========================================================
        $display("--- Test 6: Back-to-back packets ---");
        begin
            automatic bu_q_t pkts[$];
            int base = 500;
            pkts.push_back(make_pkt(base + 0, 144));
            pkts.push_back(make_pkt(base + 1, 64));
            pkts.push_back(make_pkt(base + 2, 64));
            pkts.push_back(make_pkt(base + 3, 144));
            base = 504;
            for (int i = 0; i < 496; i++) begin
                automatic int sz = 64 + ($urandom % 437); // 64-500 bytes
                pkts.push_back(make_pkt(base + i, sz));
            end
            foreach (pkts[i]) begin
                scoreboard.push_back(pkts[i]);
                pkts_sent++;
            end
            send_stream(pkts, .back_to_back(1));
        end
        idle_beats(2);
        wait_drain();
        $display("Test 6 done. errors so far: %0d", errors);
        idle_beats(20);

        // ===========================================================
        // Test 7: Back-pressure stress - random sizes, random tready
        // ===========================================================
        $display("--- Test 7: Random packets with back-pressure ---");
        fork
            begin : tready_driver
                forever begin
                    @(posedge m_clk); #1;
                    m_axis_tready <= ($urandom % 4 != 0); // ~75% ready
                end
            end
        join_none

        begin
            int base = 1000;
            for (int i = 0; i < 40; i++) begin
                automatic int sz = 64 + ($urandom % 449); // 64-512 bytes
                send_packet(base + i, sz);
                idle_beats($urandom % 4); // 0-3 idle beats between packets
            end
        end
        wait_drain(500_000);
        disable tready_driver;
        m_axis_tready <= 1;
        $display("Test 7 done. errors so far: %0d", errors);
        idle_beats(50);

        // ===========================================================
        // Test 8: Back-pressure stress -back-to-back
        // ===========================================================
        $display("--- Test 8: Back-To-Back packets with back-pressure ---");
        fork
            begin : tready_driver_2
                forever begin
                    @(posedge m_clk); #1;
                    m_axis_tready <= ($urandom % 4 != 0); // ~75% ready
                end
            end
        join_none

        begin
            automatic bu_q_t pkts[$];
            int base = 1000;
            pkts.push_back(make_pkt(base + 0, 144));
            pkts.push_back(make_pkt(base + 1, 64));
            pkts.push_back(make_pkt(base + 2, 64));
            pkts.push_back(make_pkt(base + 3, 144));
            base = 504;
            for (int i = 0; i < 496; i++) begin
                automatic int sz = 64 + ($urandom % 437); // 64-500 bytes
                pkts.push_back(make_pkt(base + i, sz));
            end
            foreach (pkts[i]) begin
                scoreboard.push_back(pkts[i]);
                pkts_sent++;
            end
            send_stream(pkts, .back_to_back(1));
        end
        wait_drain(500_000);
        disable tready_driver_2;
        m_axis_tready <= 1;
        $display("Test 8 done. errors so far: %0d", errors);
        idle_beats(50);

        // ===========================================================
        // Final report
        // ===========================================================
        $display("=========================================");
        $display("  Packets sent:     %0d", pkts_sent);
        $display("  Packets received: %0d", pkts_recvd);
        $display("  Total errors:     %0d", errors);
        if (errors == 0 && pkts_sent == pkts_recvd)
            $display("  RESULT: PASS");
        else
            $display("  RESULT: FAIL");
        $display("=========================================");
        $finish;
    end

    // Safety watchdog
    initial begin
        #50_000_000;
        $error("Watchdog timeout at 50 ms simulation time");
        $finish;
    end

endmodule
