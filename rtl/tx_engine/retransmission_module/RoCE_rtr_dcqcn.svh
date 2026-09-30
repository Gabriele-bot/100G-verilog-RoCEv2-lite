    // One DCQCN rate-limiter instance per QP.
    // When DCQCN is disabled, rate_lim_reg is held at full rate (0x3ff).
    generate
        for (genvar i = 0; i < MAX_QPS; i++) begin : gen_dcqcn

            wire rx_cnp = rx_cnp_reg && rx_cnp_qpn_reg == (i + BASE_LOC_QPN);

            if (EN_DCQCN_LOGIC) begin
                RoCE_dcqcn RoCE_dcqcn_instance (
                    .clk(clk),
                    .rst(rst),
                    .rx_cnp(rx_cnp),
                    .rate_lim(rate_lim[i]),

                    .par_alpha_g          (dcqcn_par_g),
                    .par_alpha_min        (dcqcn_alpha_min),
                    .par_alpha_update_time(dcqcn_alpha_upd_time),

                    .par_rate_decr_min(dcqcn_rate_decr_min),
                    .par_rate_min     (dcqcn_rate_min),

                    .par_rate_update_time(dcqcn_upd_time),
                    .par_rate_ai_time    (dcqcn_rate_ai_time),
                    .par_rate_hai_time   (dcqcn_rate_hai_time),
                    .par_rate_incr_ai    (dcqcn_rate_incr_ai),
                    .par_rate_incr_hai   (dcqcn_rate_incr_hai)
                );

                always @(posedge clk) begin
                    rate_lim_reg[i] <= rate_lim[i];
                end

            end else begin
                always @(posedge clk) begin
                    rate_lim_reg[i] <= 11'h3ff;
                end
            end

        end
    endgenerate

    // Derive memory_steps (log2 of per-packet buffer size) and pmtu_val from the pmtu config input.
    always @(posedge clk) begin
        memory_steps <= 4'd8 + pmtu;
        pmtu_val     <= 13'd1 << ( pmtu + 13'd8);
    end
