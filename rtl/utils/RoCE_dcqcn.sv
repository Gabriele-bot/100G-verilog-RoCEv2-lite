`resetall `timescale 1ns / 1ps `default_nettype none

module RoCE_dcqcn #(
)(
    input wire clk,
    input wire rst,

    input  wire rx_cnp,
    output wire [10:0] rate_lim, // 0(0%) to 1024(100%) ,

    // configuration
    // alpha update
    input wire [9 :0]  par_alpha_g, // 10'h0 --> 0 10'h3ff --> 0.9990234375
    input wire [9 :0]  par_alpha_min,
    input wire [31:0]  par_alpha_update_time, // in clock cylces
    // rate decrase
    input wire [9:0]   par_rate_decr_min,
    input wire [10:0]  par_rate_min,
    // rate increase
    input wire [31:0]  par_rate_update_time, // in clock cycles
    input wire [31:0]  par_rate_ai_time, // in clock cycles, before this time active increase is used
    input wire [31:0]  par_rate_hai_time, // in clock cycles, time after which hyper active increase is used
    input wire [9 :0]  par_rate_incr_ai, // active increase, 0(10'h0) to 0.9990234375(10'hFF)
    input wire [9 :0]  par_rate_incr_hai // hyper active  increase, 0(10'h0) to 0.9990234375(10'hFF)

);
    localparam [10:0] RATE_MAX = 11'h400; //--> 1 max rate

    reg [10:0] alpha_next, alpha_reg = 11'h400;
    reg [10:0] alpha_pre_add_next, alpha_pre_add_reg = 11'h400;
    reg [20:0] alpha_mult_next, alpha_mult_reg = 21'h100000;
    reg [10:0] alpha_del = 11'h400;
    reg [10:0] rc_next, rc_reg = 11'h3ff; // 1023
    reg [10:0] rc_pre_add_next, rc_pre_add_reg = 11'h400;
    reg [20:0] rc_mult_next, rc_mult_reg = 21'h100000;
    reg [19:0] rt_next, rt_reg = 20'h400;

    reg active_incr_next, active_incr_reg = 1'b0;
    reg hyper_active_incr_next, hyper_active_incr_reg = 1'b0;

    wire [10:0] alpha_val, rc_val, rt_val;

    reg rx_cnp_del;
    reg [4:0] rx_cnp_pipes;

    reg [31:0] update_ctr_next, update_ctr_reg = 32'd0;
    reg [31:0] update_alpha_crt_next, update_alpha_crt_reg = 32'd0;
    reg [31:0] incr_timer_next, incr_timer_reg = 32'd0;

    always @(*) begin
        alpha_next = alpha_reg;
        alpha_pre_add_next = alpha_pre_add_reg;
        alpha_mult_next = alpha_mult_reg;
        rc_next = rc_reg;
        rc_pre_add_next = rc_pre_add_reg;
        rc_mult_next = rc_mult_reg;
        rt_next = rt_reg;

        update_ctr_next = update_ctr_reg + 1;
        update_alpha_crt_next = update_alpha_crt_reg + 1;

        incr_timer_next        = incr_timer_reg;
        active_incr_next       = active_incr_reg;
        hyper_active_incr_next = hyper_active_incr_reg;

        if (rx_cnp) begin
            incr_timer_next        = 32'd0;
            active_incr_next       = 1'b0;
            hyper_active_incr_next = 1'b0;
        end else begin
            if (incr_timer_reg >= par_rate_hai_time) begin
                active_incr_next = 1'b0;
                hyper_active_incr_next = 1'b1;
            end else begin
                incr_timer_next = incr_timer_reg + 1;
                hyper_active_incr_next = 1'b0;
                if (incr_timer_reg >= par_rate_ai_time) begin
                    active_incr_next = 1'b1;
                end else begin
                    active_incr_next = 1'b0;
                end
            end
        end

        // update apha
        alpha_pre_add_next = 11'h400-par_alpha_g;
        alpha_mult_next    = alpha_pre_add_reg * alpha_reg;
        if (rx_cnp_pipes[0]) begin // CNP received
            if (alpha_reg > 11'h400) begin
                alpha_next = 11'h400;
            end else begin
                alpha_next = alpha_mult_reg[20:10] + par_alpha_g;
            end
            update_alpha_crt_next = 32'd0;
        end else if (update_alpha_crt_reg >= par_alpha_update_time) begin
            if (alpha_mult_reg[19:10] < par_alpha_min) begin
                alpha_next = par_alpha_min;
            end else begin
                alpha_next = alpha_mult_reg[20:10];
            end
            update_alpha_crt_next = 32'd0;
        end

        // update rate (decrease)
        rc_pre_add_next = 11'h400-(alpha_del >> 1);
        rc_mult_next = rc_reg * rc_pre_add_reg;
        if (rx_cnp_pipes[4]) begin // CNP received, delayed. Updated alpha value used to calculate new rate
            if (rc_mult_reg[20:10] < par_rate_min) begin
                rc_next = par_rate_min;
            end else begin
                rc_next = rc_mult_reg[20:10];
            end
            rt_next = rc_reg;
            update_ctr_next = 32'd0;
        end else if (update_ctr_reg >= par_rate_update_time) begin
            // current rate update (increase)
            if (((rc_reg + rt_reg) >> 1) > RATE_MAX) begin
                rc_next = RATE_MAX;
            end else begin
                rc_next = (rc_reg + rt_reg) >> 1;
            end
            // target rate update
            if (active_incr_reg) begin
                if (rt_reg < (RATE_MAX-par_rate_incr_ai)) begin
                    rt_next = rt_reg + par_rate_incr_ai;
                end else begin
                    rt_next = RATE_MAX;
                end
            end else if (hyper_active_incr_reg) begin
                if (rt_reg < (RATE_MAX-par_rate_incr_hai)) begin
                    rt_next = rt_reg + par_rate_incr_hai;
                end else begin
                    rt_next = RATE_MAX;
                end
            end else begin // fast recovery
                rt_next = rt_reg;
            end
            update_ctr_next = 32'd0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            alpha_reg <= 11'h400;
            alpha_pre_add_reg <= 11'h400;
            alpha_mult_reg    <= 21'h100000;
            alpha_del <= 11'h400;
            rc_reg    <= 20'h0400;
            rc_pre_add_reg <= 11'h400;
            rc_mult_reg <= 21'h100000;
            rt_reg    <= 20'h0400;
            update_alpha_crt_reg <= 32'd0;
            update_ctr_reg       <= 32'd0;
            rx_cnp_del <= 1'b0;
            active_incr_reg <= 1'b0;
            hyper_active_incr_reg <= 1'b0;
            incr_timer_reg <= 32'd0;
        end else begin
            alpha_reg <= alpha_next;
            alpha_pre_add_reg <= alpha_pre_add_next;
            alpha_mult_reg <= alpha_mult_next;
            alpha_del <= alpha_reg;
            rc_reg <= rc_next;
            rc_pre_add_reg <= rc_pre_add_next;
            rc_mult_reg <= rc_mult_next;
            rt_reg <= rt_next;
            update_alpha_crt_reg <= update_alpha_crt_next;
            update_ctr_reg       <= update_ctr_next;
            rx_cnp_del <= rx_cnp;
            rx_cnp_pipes <= {rx_cnp_pipes[3:0], rx_cnp};
            active_incr_reg       <= active_incr_next;
            hyper_active_incr_reg <= hyper_active_incr_next;
            incr_timer_reg <= incr_timer_next;
        end
    end

    assign alpha_val = alpha_reg[10:0];
    assign rc_val    = rc_reg[10:0];
    assign rt_val    = rt_reg[10:0];

    assign rate_lim = rc_reg[10:0];


endmodule