`timescale 1ns / 1ps

module tb_histogrammer;

    // Parameters
    parameter BRAM_SIZE        = 2048;
    parameter INPUT_DATA_WIDTH = 32;
    parameter HISTO_DATA_WIDTH = 24;
    parameter INPUT_VALUE_LSB  = 5;

    parameter CLOCK_PERIOD = 5ns;

    parameter N_TEST_VALUES = 53;


    // Testbench signals
    reg clk;
    reg rst;
    reg valid;
    reg [INPUT_DATA_WIDTH-1:0] data_in;
    reg [$clog2(BRAM_SIZE)-1:0] raddr;
    wire [HISTO_DATA_WIDTH-1:0] dout;
    wire rst_done;

    int test_values_counts [0:N_TEST_VALUES-1];
    int test_values_counts_temp [0:N_TEST_VALUES-1];
    int random_index;
    int test_count;

    histogrammer #(
        .BRAM_SIZE(BRAM_SIZE),
        .INPUT_DATA_WIDTH(INPUT_DATA_WIDTH),
        .HISTO_DATA_WIDTH(HISTO_DATA_WIDTH),
        .INPUT_VALUE_LSB(INPUT_VALUE_LSB)
    ) uut (
        .clk(clk),
        .rst(rst),
        .valid(valid),
        .data_in(data_in),
        .raddr(raddr),
        .dout(dout),
        .rst_done(rst_done)
    );

    initial begin
        clk = 0;
        forever #(CLOCK_PERIOD/2) clk = ~clk; // 100 MHz clock
    end

    initial begin
        for (int i = 0; i < N_TEST_VALUES; i++) begin
            test_values_counts[i] = $urandom % 256;
        end
        test_values_counts_temp = test_values_counts;
    end

    initial begin
        rst = 1;
        valid = 0;
        data_in = 0;
        raddr = 0;

        // Reset the histogrammer
        #10;
        rst = 0;

        

        // Stimulus: Write values to the histogram
        #(CLOCK_PERIOD/2)
        wait (rst_done == 1'b1);
        while (1) begin
            test_count = 0;
            random_index = $urandom_range(0, N_TEST_VALUES);
            // check if there is a value to insert
            if (test_values_counts_temp[random_index] > 0) begin
                #CLOCK_PERIOD
                data_in = random_index << INPUT_VALUE_LSB; // Shift to align with input value LSB
                valid = 1;
                #CLOCK_PERIOD
                valid = 0;
                // reduce by one
                test_values_counts_temp[random_index]  = test_values_counts_temp[random_index]  -1;
            end
            // check if all test numbers are sent
            for (int i = 0; i < N_TEST_VALUES; i++) begin
                test_count = test_count + test_values_counts_temp[i];
            end

            if (test_count == 0) begin
                break;
            end 
        end

        // Read back the histogram
        for (int i = 0; i < N_TEST_VALUES; i++) begin
            #CLOCK_PERIOD
            raddr = i; // Read address
            $display("Histogram[%0d]: %0d", i, dout);
            if (dout == test_values_counts[i]) begin
                $display("Error foundHistogram[%0d]: %0d", i, dout);
                $error("[%t] Mismatch found on histogramm entry %0d\n",
                    $time, i);
            end
        end

        // End simulation
        #50;
        $finish;
    end

endmodule