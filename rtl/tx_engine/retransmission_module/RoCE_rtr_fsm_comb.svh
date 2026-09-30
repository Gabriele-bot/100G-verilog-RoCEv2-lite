    /*
     * Combinational next-state logic for the TX retransmission FSM.
     *
     * The FSM iterates round-robin over all QPs. Each iteration:
     *   1. CHECK_TIMEOUT  – decide whether to retransmit (timeout / PSN-error / RNR-done / normal)
     *   2. UPDATE_RD_TABLE – roll the read pointer back to the retransmit point
     *   3. FETCH_TABLES   – one-cycle latency to read rd/wr/cpl PSN tables
     *   4. COMPARE        – decide whether there is unsent data; apply DCQCN credit
     *   5. FETCH_HDR      – read per-packet header from header RAM
     *   6. SEND_HDR       – wait for BTH-ready handshake
     *   7. WAIT_DMA       – wait for DMA command to be accepted
     *   8. CHANGE_QPN     – advance round-robin pointer then return to CHECK_TIMEOUT
     *   9. WAIT_1CLK      – generic one-cycle delay slot (used when state_cached_reg holds target)
     */
    always @(*) begin

        state_next = STATE_CHANGE_QPN;

        round_robin_qpn_next = round_robin_qpn_reg;

        s_rd_table_re_next  = 1'b0;
        s_wr_table_re_next  = 1'b0;
        s_cpl_table_re_next = 1'b0;

        s_rd_table_qpn_next  = s_rd_table_qpn_reg;
        s_wr_table_qpn_next  = s_wr_table_qpn_reg;
        s_cpl_table_qpn_next = s_cpl_table_qpn_reg;

        m_rd_table_we_next  = 1'b0;
        m_rd_table_psn_next = m_rd_table_psn_reg;
        m_rd_table_qpn_next = m_rd_table_qpn_reg;

        hdr_ram_re_next   = 1'b0;
        hdr_ram_addr_next = hdr_ram_addr_reg;

        roce_bth_valid_next   = roce_bth_valid_reg && !roce_bth_ready;
        roce_bth_op_code_next = roce_bth_op_code_reg;
        roce_bth_p_key_next   = roce_bth_p_key_reg;
        roce_bth_psn_next     = roce_bth_psn_reg;
        roce_bth_dest_qp_next = roce_bth_dest_qp_reg;
        roce_bth_src_qp_next  = roce_bth_src_qp_reg;
        roce_bth_ack_req_next = roce_bth_ack_req_reg;

        roce_reth_valid_next  = roce_reth_valid_reg && !roce_bth_ready;;
        roce_reth_v_addr_next = roce_reth_v_addr_reg;
        roce_reth_r_key_next  = roce_reth_r_key_reg;
        roce_reth_length_next = roce_reth_length_reg;

        roce_immdh_valid_next = roce_immdh_valid_reg && !roce_bth_ready;;
        roce_immdh_data_next  = roce_immdh_data_reg;

        udp_length_next = udp_length_reg;

        ip_dest_ip_next = ip_dest_ip_reg;

        qp_transmission_complete_next = qp_transmission_complete_reg;

        dma_read_desc_valid_next = dma_read_desc_valid_reg && !dma_read_desc_ready;
        dma_read_desc_len_next   = dma_read_desc_len_reg;
        dma_read_desc_addr_next  = dma_read_desc_addr_reg;

        dma_rd_cmd_sent_next = dma_rd_cmd_sent_reg;

        retry_counter_next           = retry_counter_reg;
        rnr_retry_counter_next       = rnr_retry_counter_reg;
        total_retry_counter_next     = total_retry_counter_reg;
        total_rnr_retry_counter_next = total_rnr_retry_counter_reg;
        total_psn_seq_errors_next    = total_psn_seq_errors_reg;
        total_timeout_errors_next    = total_timeout_errors_reg;

        retry_psn_mark_next     = retry_psn_mark_reg;
        rnr_retry_psn_mark_next = rnr_retry_psn_mark_reg;

        m_qp_close_valid_next   = m_qp_close_valid_reg && !m_qp_close_ready;
        m_qp_close_loc_qpn_next = m_qp_close_loc_qpn_reg;
        m_qp_close_rem_psn_next = m_qp_close_rem_psn_reg;

        qp_closed_next = qp_closed_reg;

        qp_started_retrans_next     = qp_started_retrans_reg;
        qp_started_rnr_retrans_next = qp_started_rnr_retrans_reg;

        // Latch per-QP stats for the monitored QP onto the output registers
        if (round_robin_qpn_reg == (monitor_qpn-BASE_LOC_QPN)) begin
            n_retransmit_triggers_next     = total_retry_counter_reg[round_robin_qpn_reg];
            n_rnr_retransmit_triggers_next = total_rnr_retry_counter_reg[round_robin_qpn_reg];
            n_total_psn_seq_errors_next    = total_psn_seq_errors_reg[round_robin_qpn_reg];
            n_total_timeout_errors_next    = total_timeout_errors_reg[round_robin_qpn_reg];
        end else begin
            n_retransmit_triggers_next     = n_retransmit_triggers_reg;
            n_rnr_retransmit_triggers_next = n_rnr_retransmit_triggers_reg;
            n_total_psn_seq_errors_next    = n_total_psn_seq_errors_reg;
            n_total_timeout_errors_next    = n_total_timeout_errors_reg;
        end

        credit_next = credit_reg;

        flow_ctrl_pause_next = flow_ctrl_pause;

        state_cached_next = state_cached_reg;

        case(state_reg)

            // ----------------------------------------------------------------
            // STATE_CHECK_TIMEOUT
            // Decide the action for the current QP before reading tables:
            //   - irreversible error  → close QP
            //   - RNR wait ongoing    → fetch tables anyway (needed for stall check)
            //   - timeout             → check retry count, update rd pointer
            //   - PSN error / RNR done → update rd pointer
            //   - normal              → fetch tables
            // ----------------------------------------------------------------
            STATE_CHECK_TIMEOUT: begin
                if (qp_error_reg[round_robin_qpn_reg]) begin
                    m_qp_close_valid_next   = 1'b1;
                    m_qp_close_loc_qpn_next = BASE_LOC_QPN + round_robin_qpn_reg;
                    qp_closed_next[round_robin_qpn_reg]             = 1'b1;
                    qp_started_retrans_next[round_robin_qpn_reg]    = 1'b0;
                    qp_started_rnr_retrans_next[round_robin_qpn_reg]= 1'b0;

                    if (MAX_QPS == 1)
                        round_robin_qpn_next = round_robin_qpn_reg;
                    else
                        round_robin_qpn_next = round_robin_qpn_reg + 1;
                    state_next = STATE_CHECK_TIMEOUT;

                end else begin
                    if (qp_rnr_wait_reg[round_robin_qpn_reg] && !qp_rnr_wait_done_reg[round_robin_qpn_reg]) begin
                        // RNR timer still running – fetch tables to decide stall
                        qp_started_retrans_next[round_robin_qpn_reg]     = 1'b0;
                        qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;

                        s_rd_table_re_next  = 1'b1;
                        s_wr_table_re_next  = 1'b1;
                        s_cpl_table_re_next = 1'b1;

                        s_rd_table_qpn_next  = round_robin_qpn_reg;
                        s_wr_table_qpn_next  = round_robin_qpn_reg;
                        s_cpl_table_qpn_next = round_robin_qpn_reg;

                        state_next = STATE_FETCH_TABLES;

                    end else if (qp_timed_out_reg[round_robin_qpn_reg]) begin
                        if (retry_counter_reg[round_robin_qpn_reg] == retry_count) begin
                            // retry limit reached → close QP
                            m_qp_close_valid_next   = 1'b1;
                            m_qp_close_loc_qpn_next = BASE_LOC_QPN + round_robin_qpn_reg;
                            qp_closed_next[round_robin_qpn_reg]              = 1'b1;
                            qp_started_retrans_next[round_robin_qpn_reg]     = 1'b0;
                            qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;
                            retry_psn_mark_next[round_robin_qpn_reg]         = 24'd0;

                            state_cached_next = STATE_CHANGE_QPN;
                            state_next        = STATE_WAIT_1CLK;
                        end else begin
                            // trigger retransmission from completion pointer
                            s_cpl_table_re_next  = 1'b1;
                            s_cpl_table_qpn_next = round_robin_qpn_reg;
                            state_cached_next    = STATE_UPDATE_RD_TABLE;
                            state_next           = STATE_WAIT_1CLK;
                        end

                    end else if (qp_psn_error_reg[round_robin_qpn_reg] || qp_rnr_wait_done_reg[round_robin_qpn_reg]) begin
                        // PSN sequence error or RNR timer expired → roll back rd pointer
                        state_next = STATE_UPDATE_RD_TABLE;

                    end else begin
                        // Normal path
                        qp_started_retrans_next[round_robin_qpn_reg]     = 1'b0;
                        qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;

                        s_rd_table_re_next  = 1'b1;
                        s_wr_table_re_next  = 1'b1;
                        s_cpl_table_re_next = 1'b1;

                        s_rd_table_qpn_next  = round_robin_qpn_reg;
                        s_wr_table_qpn_next  = round_robin_qpn_reg;
                        s_cpl_table_qpn_next = round_robin_qpn_reg;

                        state_next = STATE_FETCH_TABLES;
                    end
                end
            end

            // ----------------------------------------------------------------
            // STATE_UPDATE_RD_TABLE
            // Write the corrected read pointer back into the rd table, then
            // re-read all three tables so COMPARE has fresh values.
            // ----------------------------------------------------------------
            STATE_UPDATE_RD_TABLE: begin
                if (!m_rd_table_we_reg) begin
                    m_rd_table_we_next = 1'b1;
                    if (qp_timed_out_reg[round_robin_qpn_reg]) begin
                        total_timeout_errors_next[round_robin_qpn_reg] = total_timeout_errors_reg[round_robin_qpn_reg] + 1;
                        retry_psn_mark_next[round_robin_qpn_reg]       = s_cpl_table_psn + 1;
                        retry_counter_next[round_robin_qpn_reg]        = retry_counter_reg[round_robin_qpn_reg] + 1;
                        total_retry_counter_next[round_robin_qpn_reg]  = total_retry_counter_reg[round_robin_qpn_reg] + 1;
                        m_rd_table_psn_next                            = s_cpl_table_psn;
                        qp_started_retrans_next[round_robin_qpn_reg]   = 1'b1;

                    end else if (qp_psn_error_reg[round_robin_qpn_reg]) begin
                        total_psn_seq_errors_next[round_robin_qpn_reg] = total_psn_seq_errors_reg[round_robin_qpn_reg] + 1;
                        retry_psn_mark_next[round_robin_qpn_reg]       = psn_nak_reg[round_robin_qpn_reg];
                        retry_counter_next[round_robin_qpn_reg]        = retry_counter_reg[round_robin_qpn_reg] + 1;
                        total_retry_counter_next[round_robin_qpn_reg]  = total_retry_counter_reg[round_robin_qpn_reg] + 1;
                        m_rd_table_psn_next                            = psn_nak_reg[round_robin_qpn_reg] - 1;
                        qp_started_retrans_next[round_robin_qpn_reg]   = 1'b1;
                        qp_started_rnr_retrans_next[round_robin_qpn_reg] = 1'b0;

                    end else if (qp_rnr_wait_done_reg[round_robin_qpn_reg]) begin
                        rnr_retry_psn_mark_next[round_robin_qpn_reg]      = psn_nak_reg[round_robin_qpn_reg];
                        rnr_retry_counter_next[round_robin_qpn_reg]       = rnr_retry_counter_reg[round_robin_qpn_reg] + 1;
                        total_rnr_retry_counter_next[round_robin_qpn_reg] = total_rnr_retry_counter_reg[round_robin_qpn_reg] + 1;
                        m_rd_table_psn_next                               = psn_nak_reg[round_robin_qpn_reg] - 1;
                        qp_started_retrans_next[round_robin_qpn_reg]      = 1'b1;
                        qp_started_rnr_retrans_next[round_robin_qpn_reg]  = 1'b1;
                    end
                    m_rd_table_qpn_next = round_robin_qpn_reg;
                    state_next = STATE_UPDATE_RD_TABLE;

                end else begin
                    // Write accepted; now read fresh table values
                    s_rd_table_re_next  = 1'b1;
                    s_wr_table_re_next  = 1'b1;
                    s_cpl_table_re_next = 1'b1;

                    s_rd_table_qpn_next  = round_robin_qpn_reg;
                    s_wr_table_qpn_next  = round_robin_qpn_reg;
                    s_cpl_table_qpn_next = round_robin_qpn_reg;
                    state_next = STATE_FETCH_TABLES;
                end
            end

            // ----------------------------------------------------------------
            // STATE_FETCH_TABLES
            // One pipeline bubble waiting for table read data to be valid.
            // ----------------------------------------------------------------
            STATE_FETCH_TABLES: begin
                state_next = STATE_COMPARE;
            end

            // ----------------------------------------------------------------
            // STATE_COMPARE
            // Compare rd vs wr pointers. If data is available and the QP is
            // not rate-limited, kick off a header RAM read (→ FETCH_HDR).
            // ----------------------------------------------------------------
            STATE_COMPARE: begin
                if (qp_closed_reg[round_robin_qpn_reg]) begin
                    qp_closed_next[round_robin_qpn_reg] = 1'b0;
                    retry_counter_next[round_robin_qpn_reg] = 3'd0;
                    if (MAX_QPS == 1)
                        round_robin_qpn_next = round_robin_qpn_reg;
                    else
                        round_robin_qpn_next = round_robin_qpn_reg + 1;
                    state_next = STATE_CHECK_TIMEOUT;

                end else begin
                    // Reset retry counters once a valid ACK moves the completion pointer past the mark
                    if (s_cpl_table_psn != (retry_psn_mark_reg[round_robin_qpn_reg] - 24'd1))
                        retry_counter_next[round_robin_qpn_reg] = 3'd0;
                    if (s_cpl_table_psn != (rnr_retry_psn_mark_reg[round_robin_qpn_reg] - 24'd1))
                        rnr_retry_counter_next[round_robin_qpn_reg] = 3'd0;

                    qp_transmission_complete_next[round_robin_qpn_reg] = s_cpl_table_psn == s_rd_table_psn;

                    if (s_wr_table_psn == s_rd_table_psn) begin
                        // Nothing to send
                        if (MAX_QPS == 1)
                            round_robin_qpn_next = round_robin_qpn_reg;
                        else
                            round_robin_qpn_next = round_robin_qpn_reg + 1;
                        state_next = STATE_CHECK_TIMEOUT;

                    end else begin
                        if (qp_rnr_wait_reg[round_robin_qpn_reg]) begin
                            // RNR wait still active – skip this QP
                            if (MAX_QPS == 1)
                                round_robin_qpn_next = round_robin_qpn_reg;
                            else
                                round_robin_qpn_next = round_robin_qpn_reg + 1;
                            state_next = STATE_CHECK_TIMEOUT;

                        end else begin
                            if (roce_bth_ready) begin
                                // Compute the next header RAM address
                                if (s_rd_table_psn - s_cpl_table_psn < 24'hff_0000) begin
                                    // rd is ahead of cpl – read next packet
                                    if (MAX_QPS == 1)
                                        hdr_ram_addr_next[HEADER_ADDR_WIDTH-1:0] = s_rd_table_psn[HEADER_ADDR_WIDTH-1:0] + 1;
                                    else
                                        hdr_ram_addr_next[HEADER_ADDR_WIDTH-MAX_QPS_WIDTH-1:0] = s_rd_table_psn[HEADER_ADDR_WIDTH-MAX_QPS_WIDTH-1:0] + 1;
                                end else begin
                                    // cpl is ahead of rd – rd pointer stale, snap it forward
                                    if (MAX_QPS == 1)
                                        hdr_ram_addr_next[HEADER_ADDR_WIDTH-1:0] = s_cpl_table_psn[HEADER_ADDR_WIDTH-1:0] + 1;
                                    else
                                        hdr_ram_addr_next[HEADER_ADDR_WIDTH-MAX_QPS_WIDTH-1:0] = s_cpl_table_psn[HEADER_ADDR_WIDTH-MAX_QPS_WIDTH-1:0] + 1;
                                    m_rd_table_we_next  = 1'b1;
                                    m_rd_table_qpn_next = round_robin_qpn_reg;
                                    m_rd_table_psn_next = s_cpl_table_psn;
                                end

                                // DCQCN credit check
                                if (rate_lim_reg[round_robin_qpn_reg] >= 11'h400 || !dcqcn_en || !EN_DCQCN_LOGIC) begin
                                    // Full rate or DCQCN disabled
                                    credit_next[round_robin_qpn_reg] = PACKET_COST;
                                    hdr_ram_re_next = 1'b1;
                                    if (MAX_QPS != 1)
                                        hdr_ram_addr_next[HEADER_ADDR_WIDTH-1 -: MAX_QPS_WIDTH] = round_robin_qpn_reg[MAX_QPS_WIDTH-1:0];
                                    state_next = STATE_FETCH_HDR;

                                end else begin
                                    if (credit_reg[round_robin_qpn_reg] <= PACKET_COST) begin
                                        // Insufficient credit – stall this QP for one round
                                        hdr_ram_re_next = 1'b0;
                                        credit_next[round_robin_qpn_reg] = credit_reg[round_robin_qpn_reg] + rate_lim_reg[round_robin_qpn_reg];
                                        if (MAX_QPS == 1)
                                            round_robin_qpn_next = round_robin_qpn_reg;
                                        else
                                            round_robin_qpn_next = round_robin_qpn_reg + 1;
                                        state_next = STATE_CHECK_TIMEOUT;
                                    end else begin
                                        // Enough credit – consume and send
                                        credit_next[round_robin_qpn_reg] = credit_reg[round_robin_qpn_reg] - PACKET_COST + rate_lim_reg[round_robin_qpn_reg];
                                        hdr_ram_re_next = 1'b1;
                                        if (MAX_QPS != 1)
                                            hdr_ram_addr_next[HEADER_ADDR_WIDTH-1 -: MAX_QPS_WIDTH] = round_robin_qpn_reg[MAX_QPS_WIDTH-1:0];
                                        state_next = STATE_FETCH_HDR;
                                    end
                                end

                            end else begin
                                // Header output not ready yet
                                state_next = STATE_COMPARE;
                            end
                        end
                    end
                end
            end

            // ----------------------------------------------------------------
            // STATE_FETCH_HDR
            // Wait for header RAM to return valid data, then populate all
            // header registers and issue the DMA read command.
            // ----------------------------------------------------------------
            STATE_FETCH_HDR: begin
                if (hdr_ram_data_valid) begin
                    roce_bth_op_code_next = hdr_ram_data[RAM_OP_CODE_OFFSET+:8];
                    roce_bth_valid_next   = 1'b1;
                    roce_reth_valid_next  = roce_bth_op_code_next == RC_RDMA_WRITE_ONLY     ||
                                           roce_bth_op_code_next == RC_RDMA_WRITE_ONLY_IMD ||
                                           roce_bth_op_code_next == RC_RDMA_WRITE_FIRST;
                    roce_immdh_valid_next = roce_bth_op_code_next == RC_RDMA_WRITE_ONLY_IMD ||
                                           roce_bth_op_code_next == RC_RDMA_WRITE_LAST_IMD ||
                                           roce_bth_op_code_next == RC_SEND_ONLY_IMD       ||
                                           roce_bth_op_code_next == RC_SEND_LAST_IMD;
                    roce_bth_psn_next     = hdr_ram_data[RAM_PSN_OFFSET+:24];
                    roce_bth_p_key_next   = 16'hFFFF;
                    roce_bth_dest_qp_next = cached_rem_qpn_reg[round_robin_qpn_reg];
                    roce_bth_src_qp_next  = BASE_LOC_QPN + round_robin_qpn_reg;
                    roce_bth_ack_req_next = 1'b1;
                    // RETH fields
                    roce_reth_v_addr_next = hdr_ram_data[RAM_VADDR_OFFSET+:64];
                    roce_reth_r_key_next  = cached_r_key_reg[round_robin_qpn_reg];
                    roce_reth_length_next = hdr_ram_data[RAM_RETH_LEN_OFFSET+:32];
                    // Immediate field
                    roce_immdh_data_next  = hdr_ram_data[RAM_IMMD_DATA_OFFSET+:32];
                    // UDP length
                    udp_length_next       = hdr_ram_data[RAM_UDP_LEN_OFFSET+:16];

                    ip_dest_ip_next = cached_dest_ip_reg[round_robin_qpn_reg];

                    // DMA read command – length depends on which optional headers are present
                    dma_read_desc_valid_next = 1'b1;
                    if (dma_read_desc_ready) dma_rd_cmd_sent_next = 1'b1;

                    if (roce_reth_valid_next && roce_immdh_valid_next)
                        dma_read_desc_len_next = hdr_ram_data[RAM_UDP_LEN_OFFSET+:13] - 12 - 16 - 4 - 8; // bth+reth+immdh
                    else if (roce_reth_valid_next && !roce_immdh_valid_next)
                        dma_read_desc_len_next = hdr_ram_data[RAM_UDP_LEN_OFFSET+:13] - 12 - 16 - 8;     // bth+reth
                    else if (!roce_reth_valid_next && roce_immdh_valid_next)
                        dma_read_desc_len_next = hdr_ram_data[RAM_UDP_LEN_OFFSET+:13] - 12 - 4 - 8;      // bth+immdh
                    else
                        dma_read_desc_len_next = hdr_ram_data[RAM_UDP_LEN_OFFSET+:13] - 12 - 8;          // bth only

                    // DMA address: per-QP region offset by (rd_psn+1) * packet_size
                    dma_read_desc_addr_next[BUFFER_ADDR_WIDTH-MAX_QPS_WIDTH-1:0]  = ((s_rd_table_psn + 1) << memory_steps);
                    dma_read_desc_addr_next[BUFFER_ADDR_WIDTH-1 -: MAX_QPS_WIDTH] = round_robin_qpn_reg[MAX_QPS_WIDTH-1:0];

                    // Advance rd pointer
                    m_rd_table_we_next  = 1'b1;
                    m_rd_table_psn_next = s_rd_table_psn + 1;
                    m_rd_table_qpn_next = round_robin_qpn_reg;

                    if (roce_bth_ready) begin
                        if (dma_read_desc_ready) begin
                            dma_rd_cmd_sent_next = 1'b0;
                            if (MAX_QPS == 1) round_robin_qpn_next = round_robin_qpn_reg;
                            else              round_robin_qpn_next = round_robin_qpn_reg + 1;
                            state_next = STATE_CHECK_TIMEOUT;
                        end else begin
                            state_next = STATE_WAIT_DMA;
                        end
                    end else begin
                        state_next = STATE_SEND_HDR;
                    end

                end else begin
                    state_next = STATE_FETCH_HDR;
                end
            end

            // ----------------------------------------------------------------
            // STATE_SEND_HDR
            // Wait for the BTH-ready handshake, then either go back to the
            // start or wait for the DMA command to be accepted.
            // ----------------------------------------------------------------
            STATE_SEND_HDR: begin
                if (roce_bth_valid & roce_bth_ready) begin
                    if (dma_rd_cmd_sent_reg) begin
                        dma_rd_cmd_sent_next = 1'b0;
                        if (MAX_QPS == 1) round_robin_qpn_next = round_robin_qpn_reg;
                        else              round_robin_qpn_next = round_robin_qpn_reg + 1;
                        state_next = STATE_CHECK_TIMEOUT;
                    end else begin
                        if (dma_read_desc_ready & dma_read_desc_valid_reg) begin
                            dma_rd_cmd_sent_next = 1'b0;
                            if (MAX_QPS == 1) round_robin_qpn_next = round_robin_qpn_reg;
                            else              round_robin_qpn_next = round_robin_qpn_reg + 1;
                            state_next = STATE_CHECK_TIMEOUT;
                        end else begin
                            state_next = STATE_WAIT_DMA;
                        end
                    end
                end else begin
                    if (dma_read_desc_ready & dma_read_desc_valid_reg)
                        dma_rd_cmd_sent_next = 1'b1;
                    state_next = STATE_SEND_HDR;
                end
            end

            // ----------------------------------------------------------------
            // STATE_WAIT_DMA
            // Header was accepted; wait until the DMA command is also accepted.
            // ----------------------------------------------------------------
            STATE_WAIT_DMA: begin
                if (dma_read_desc_ready & dma_read_desc_valid_reg) begin
                    dma_rd_cmd_sent_next = 1'b0;
                    if (MAX_QPS == 1) round_robin_qpn_next = round_robin_qpn_reg;
                    else              round_robin_qpn_next = round_robin_qpn_reg + 1;
                    state_next = STATE_CHECK_TIMEOUT;
                end else begin
                    state_next = STATE_WAIT_DMA;
                end
            end

            // ----------------------------------------------------------------
            // STATE_CHANGE_QPN
            // Advance the round-robin QPN counter and re-enter CHECK_TIMEOUT.
            // ----------------------------------------------------------------
            STATE_CHANGE_QPN: begin
                if (MAX_QPS == 1) round_robin_qpn_next = round_robin_qpn_reg;
                else              round_robin_qpn_next = round_robin_qpn_reg + 1;
                state_next = STATE_CHECK_TIMEOUT;
            end

            // ----------------------------------------------------------------
            // STATE_WAIT_1CLK
            // Generic one-cycle delay; next state is held in state_cached_reg.
            // ----------------------------------------------------------------
            STATE_WAIT_1CLK: begin
                state_next = state_cached_reg;
            end

        endcase
    end
