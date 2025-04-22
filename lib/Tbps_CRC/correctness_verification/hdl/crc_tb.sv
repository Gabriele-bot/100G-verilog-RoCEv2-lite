`timescale 1ns/1ps

`ifndef SIM
    `define SIM
`endif

`include "config.svh"

module crc_tb();
    parameter int N_MESSAGE = `N_MESSAGE;
    parameter int MESSAGE_LEN_MIN = `MESSAGE_LEN_MIN;
    parameter int MESSAGE_LEN_MAX = `MESSAGE_LEN_MAX;
    parameter real flitEn_ratio = `flitEn_ratio;

    parameter int DWIDTH = `DWIDTH;
    parameter int CRC_WIDTH = `CRC_WIDTH;
    parameter int PIPE_LVL = `PIPE_LVL;
    parameter CRC_POLY = `CRC_POLY;
    parameter INIT = `INIT;
    parameter XOR_OUT = `XOR_OUT;
    parameter bit REFIN = `REFIN;
    parameter bit REFOUT = `REFOUT;

    function string hex_str(input bit [CRC_WIDTH-1:0] hex);
        automatic bit [((CRC_WIDTH-1)/8)*8+7:0] new_hex = {(((CRC_WIDTH-1)/8+1)*8){1'b0}};
        automatic string hex_string = "";
        automatic string byte_string = "";
        new_hex[CRC_WIDTH-1:0] = hex;
        for (int i = 0; i <= (CRC_WIDTH-1)/8; i++) begin
            $sformat(byte_string, "%2X", new_hex[((CRC_WIDTH-1)/8)*8+7-i*8-:8]);
            hex_string = {hex_string,byte_string};
        end
        return hex_string;
    endfunction

    bit [8191:0][7:0] message; //here the message is set to be at most 8192 bytes, change it if it's too small for you
    int unsigned message_size;

    logic clk;
    logic rst;
    logic [DWIDTH-1:0] din;
    logic dlast;
    logic flitEn;
    logic [CRC_WIDTH-1:0] crc_out;
    logic crc_out_vld;

    crc_top #(
        .DWIDTH           (DWIDTH           ),
        .CRC_WIDTH        (CRC_WIDTH        ),
        .PIPE_LVL         (PIPE_LVL         ),
        .CRC_POLY         (CRC_POLY         ),
        .INIT             (INIT             ),
        .XOR_OUT          (XOR_OUT          ),
        .REFIN            (REFIN            ),
        .REFOUT           (REFOUT           )
    ) u_crc_top(.*);

    bit [CRC_WIDTH-1:0] crc_sw_out;
    bit [CRC_WIDTH+7:0] crc_sw_tmp;
    bit [7:0] crc_byte_tmp;

    bit [N_MESSAGE-1:0][CRC_WIDTH-1:0] crc_sw_out_fifo;

    int sim_exit = 0;

    initial begin
    //information
        $display("Configuration:");
        $display("    CRC polynomial: %0d'h%s", CRC_WIDTH, hex_str(CRC_POLY));
        $display("    Bus Width: %0d", DWIDTH);
        $display("    INIT: %0d'h%s", CRC_WIDTH, hex_str(INIT));
        $display("    XOR OUT: %0d'h%s", CRC_WIDTH, hex_str(XOR_OUT));
        if (REFIN)
            $display("    Reflect IN: True");
        else
            $display("    Reflect IN: False");
        if (REFOUT)
            $display("    Reflect OUT: True");
        else
            $display("    Reflect OUT: False");
        $display("Run test with %0d messages", N_MESSAGE);
        //reset the hardware
        din <= {DWIDTH{1'b0}};
        dlast <= 1'b0;
        flitEn <= 1'b0;    
        rst <= 1'b1;
        repeat(20) @(posedge clk);
        rst <= 1'b0;
        repeat(10) @(posedge clk);
        //initialize the variables
        message_size = $urandom(111); // Initialize the generator
        for (int i = 0; i < N_MESSAGE; i++) begin
            if (sim_exit)
                break;
            message_size = $urandom_range(MESSAGE_LEN_MIN,MESSAGE_LEN_MAX);
            message_size = (message_size-1)/(DWIDTH/8)*(DWIDTH/8)+DWIDTH/8;
            $display("The message #%0d is %0d bytes:", i, message_size);
        //generate the message
            for (int j = 0; j < message_size; j++) begin
                message[j] = $urandom & 255;
                $write("%02X",message[j]); 
                if (j % 32 == 31)
                    $write("\n");
            end
            $write("\n");
        //calculate the crc in software
            //assign INIT to crcSoFar                
            crc_sw_tmp = {INIT,8'b0};
            for (int j = 0; j < message_size; j++) begin
                if (REFIN)
                    crc_byte_tmp = {<<{message[j]}};
                else
                    crc_byte_tmp = message[j];
                //XOR crcSoFar with the message byte
                crc_sw_tmp[CRC_WIDTH+7-:8] = crc_sw_tmp[CRC_WIDTH+7-:8] ^ crc_byte_tmp;
                //Do 1-bit CRC algorithm
                for (int k = CRC_WIDTH+7; k >= CRC_WIDTH; k--) begin
                    if (crc_sw_tmp[k])
                        crc_sw_tmp[k-1-:CRC_WIDTH] = crc_sw_tmp[k-1-:CRC_WIDTH] ^ CRC_POLY;
                end
                //shift crc_out for another iteration
                crc_sw_tmp = {crc_sw_tmp[CRC_WIDTH-1:0],8'b0};
            end
            crc_sw_out = crc_sw_tmp[CRC_WIDTH+7-:CRC_WIDTH];
            if (REFOUT)
                crc_sw_out = {<<{crc_sw_out}};
            crc_sw_out = crc_sw_out ^ XOR_OUT;
            crc_sw_out_fifo[i] = crc_sw_out;
        //calculate the crc in hardware
            @(posedge clk);
            for (int j = 0; j < (message_size*8-1)/DWIDTH+1; ) begin
                if (real'($urandom_range(1,100))/100.0 <= flitEn_ratio) begin
                    for (int k = 0; k < DWIDTH/8; k++) begin
                        din[DWIDTH-1-k*8-:8] <= message[j*DWIDTH/8+k];
                    end
                    dlast <= (j+1)*DWIDTH/8 >= message_size;
                    flitEn <= 1'b1;
                    j++;
                end
                else
                    flitEn <= 1'b0;
                @(posedge clk);
            end
            din <= {DWIDTH{1'b0}};
            dlast <= 1'b0;
            flitEn <= 1'b0;
        end
    end

    initial begin
        sim_exit = 0;
        for (int i = 0; i < N_MESSAGE; ) begin
            if (crc_out_vld) begin
                if (crc_out != crc_sw_out_fifo[i]) begin
                    sim_exit = 1;
                    for (int j = 0; j < i; j++)
                        $display("Message #%0d: SW CRC result = %0d'h%s, HW CRC result = %0d'h%s, results matched", j, CRC_WIDTH, hex_str(crc_sw_out_fifo[j]), CRC_WIDTH, hex_str(crc_sw_out_fifo[j]));
                    $display("Message #%0d: SW CRC result = %0d'h%s, HW CRC result = %0d'h%s, results did not match", i, CRC_WIDTH, hex_str(crc_sw_out_fifo[i]), CRC_WIDTH, hex_str(crc_out));
                    $display("CRC results did not match for message #%0d, test FAILED", i);
                    repeat(10) @(posedge clk);
                    $finish;
                end
                i++;
            end
            @(posedge clk);
        end

        for (int i = 0; i < N_MESSAGE; i++) begin
            $display("Message #%0d: SW CRC result = %0d'h%s, HW CRC result = %0d'h%s, results matched", i, CRC_WIDTH, hex_str(crc_sw_out_fifo[i]), CRC_WIDTH, hex_str(crc_sw_out_fifo[i]));
        end
        $display("All CRC results matched, test PASSED for %m");
        repeat(50) @(posedge clk);
        $finish;
    end

    initial begin
        clk = 1'b1;
        forever begin
            #(2ns) clk = ~ clk;
        end
    end
endmodule
`undef SIM
