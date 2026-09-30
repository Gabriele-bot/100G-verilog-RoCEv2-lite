`resetall
`timescale 1ns / 1ps
`default_nettype none

module tb_RoCE_dcqcn;

    // --------------------------------------------------------------------------
    // Clock / reset
    // --------------------------------------------------------------------------
    localparam real CLK_PERIOD = 4.0; // ns → 250 MHz

    reg clk = 0;
    reg rst = 1;

    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // --------------------------------------------------------------------------
    // DUT signals
    // --------------------------------------------------------------------------
    reg        rx_cnp = 0;
    wire [10:0] rate_lim;

    reg  [9 :0] par_alpha_g           = 10'h008; // alpha update gain 1/64
    reg  [9 :0] par_alpha_min         = 10'h010; // minimum alpha value
    reg  [31:0] par_alpha_update_time = 32'd1000;

    reg  [9:0] par_rate_decr_init = 10'd0; // not used
    reg  [9:0] par_rate_decr_min  = 10'h155; // 33% (341) max decrease in a single event
    reg  [9:0] par_rate_min      = 11'h66; // min rate reachable 1% (102)

    reg [31:0] par_rate_update_time = 32'd2000;
    reg [31:0] par_rate_ai_time     = 32'd5000;
    reg [31:0] par_rate_hai_time    = 32'd10000;
    reg [9 :0] par_rate_incr_ai     = 10'h008;
    reg [9 :0] par_rate_incr_hai    = 10'h010;
    

    // --------------------------------------------------------------------------
    // DUT
    // --------------------------------------------------------------------------
    RoCE_dcqcn RoCE_dcqcn_instance (
        .clk(clk),
        .rst(rst),
        .rx_cnp(rx_cnp),
        .rate_lim(rate_lim),

        .par_alpha_g          (par_alpha_g),
        .par_alpha_min        (par_alpha_min),
        .par_alpha_update_time(par_alpha_update_time),

        .par_rate_decr_min(par_rate_decr_min),
        .par_rate_min     (par_rate_min),

        .par_rate_update_time(par_rate_update_time),
        .par_rate_ai_time    (par_rate_ai_time),
        .par_rate_hai_time   (par_rate_hai_time),
        .par_rate_incr_ai    (par_rate_incr_ai),
        .par_rate_incr_hai   (par_rate_incr_hai)
    );

    // --------------------------------------------------------------------------
    // Task: send CNP pulses at a given rate for a given duration
    //   rate_mhz   – CNP pulse rate in MHz (pulses per microsecond)
    //   duration_us – how long to keep sending, in microseconds
    // --------------------------------------------------------------------------
    task send_cnp(
        input real rate_mhz,
        input real duration_us
    );
        real period_ns;
        integer period_cycles;
        integer total_cycles;
        integer i;
        begin
            period_ns    = 1000.0 / rate_mhz; // ns between pulses
            period_cycles = $rtoi(period_ns / CLK_PERIOD); // cycles between pulses
            total_cycles  = $rtoi(duration_us * 1000.0 / CLK_PERIOD); // total run cycles

            if (period_cycles < 1) period_cycles = 1;

            $display("[%0t ns] send_cnp: rate=%.2f MHz, period=%0d cycles, duration=%.1f us (%0d cycles)",
                $time, rate_mhz, period_cycles, duration_us, total_cycles);

            i = 0;
            while (i < total_cycles) begin
                @(posedge clk);
                rx_cnp = 1;
                @(posedge clk);
                rx_cnp = 0;
                // wait for remainder of the inter-pulse period
                repeat (period_cycles - 1) @(posedge clk);
                i = i + period_cycles + 1;
            end
        end
    endtask

    // --------------------------------------------------------------------------
    // Monitor: print rate_lim whenever it changes
    // --------------------------------------------------------------------------
    reg [10:0] rate_lim_prev = 11'h400;
    always @(posedge clk) begin
        if (rate_lim !== rate_lim_prev) begin
            $display("[%0t ns] rate_lim changed: %0d → %0d  (%.1f%%)",
                $time, rate_lim_prev, rate_lim,
                (real'(rate_lim) / 1024.0) * 100.0);
            rate_lim_prev <= rate_lim;
        end
    end

    // --------------------------------------------------------------------------
    // Stimulus
    // --------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_RoCE_dcqcn.vcd");
        $dumpvars(0, tb_RoCE_dcqcn);

        // Reset for 10 cycles
        repeat (10) @(posedge clk);
        rst = 0;
        $display("[%0t ns] Reset released", $time);

        // Let the module run freely for 1 ms (rate should recover to max)
        #1000000;

        $display("[%0t ns] --- Sending CNPs at 0.1 MHz for 20 us ---", $time);
        send_cnp(0.1, 20.0);

        $display("[%0t ns] --- No CNPs, waiting 1 ms for recovery ---", $time);
        #1000000;

        $display("[%0t ns] --- Sending CNPs at 1 MHz for 10 us ---", $time);
        send_cnp(1.0, 10.0);

        $display("[%0t ns] --- No CNPs, waiting 1 ms for recovery ---", $time);
        #1000000;

        $display("[%0t ns] --- Sending CNPs at 10 MHz for 10 us ---", $time);
        send_cnp(10.0, 10.0);

        // Recovery
        $display("[%0t ns] --- No CNPs, waiting 1 ms for recovery ---", $time);
        #1000000;

        $display("[%0t ns] --- Sending CNPs at 250 kHz for 10 ms ---", $time);
        send_cnp(0.25, 10000.0);

        // Recovery
        $display("[%0t ns] --- No CNPs, waiting 200 us for recovery ---", $time);
        #200000;

         $display("[%0t ns] --- Sending CNPs at 100 kHz for 10 ms ---", $time);
        send_cnp(0.1, 10000.0);

        // Recovery
        $display("[%0t ns] --- No CNPs, waiting 200 us for recovery ---", $time);
        #200000;

        $display("[%0t ns] --- Sending CNPs at 50 kHz for 10 ms ---", $time);
        send_cnp(0.05, 10000.0);

        // Recovery
        $display("[%0t ns] --- No CNPs, waiting 200 us for recovery ---", $time);
        #200000;

        $display("[%0t ns] --- Sending CNPs at 25 kHz for 10 ms ---", $time);
        send_cnp(0.025, 10000.0);

        // Recovery
        $display("[%0t ns] --- No CNPs, waiting 200 us for recovery ---", $time);
        #200000;

        $display("[%0t ns] Simulation done", $time);
        //$finish;
    end

endmodule
