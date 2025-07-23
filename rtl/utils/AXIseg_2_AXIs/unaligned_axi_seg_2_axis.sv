`resetall `timescale 1ns / 1ps `default_nettype none

/*
8 AXI segmented to 1 AXI Stream, minimum frame length is supposed to be 64 Bytes or 4 segments.axi_seg_2_axis
This means that up to 2 frames can be sent in the same clock cycles  
 */
module unaligned_axi_seg_2_axis #(
    parameter FIFO_DEPTH = 4096,
    parameter ASYNC_FIFO = 1
)(
    input  wire s_clk,
    input  wire s_rst,

    input  wire [128*8-1:0] s_axis_seg_tdata,
    input  wire             s_axis_seg_tvalid,
    output wire             s_axis_seg_tready,
    input  wire [7:0]       s_ena,
    input  wire [7:0]       s_sop,
    input  wire [7:0]       s_eop,
    input  wire [7:0]       s_err,
    input  wire [4*8-1:0]   s_mty,

    input  wire m_clk,
    input  wire m_rst,

    output  wire [1023:0]  m_axis_tdata,
    output  wire [127 :0]  m_axis_tkeep,
    output  wire           m_axis_tvalid,
    input   wire           m_axis_tready,
    output  wire           m_axis_tlast,
    output  wire           m_axis_tuser
);

    reg [1023:0]  m_axis_tdata_int;
    reg [127 :0]  m_axis_tkeep_int;
    reg           m_axis_tvalid_int;
    reg           m_axis_tlast_int;
    reg           m_axis_tuser_int;

    reg [1023:0]  m_axis_tdata_reg;
    reg [127 :0]  m_axis_tkeep_reg;
    reg           m_axis_tvalid_reg;
    reg           m_axis_tlast_reg;
    reg           m_axis_tuser_reg;

    reg [2:0] current_align_reg, current_align_next;

    reg [128*8-1:0] prev_tdata_reg, prev_tdata_next;
    reg [7:0] prev_ena_reg, prev_ena_next;
    reg [7:0] prev_sop_reg, prev_sop_next;
    reg [7:0] prev_eop_reg, prev_eop_next;
    reg [7:0] prev_err_reg, prev_err_next;
    reg [4*8-1:0] prev_mty_reg, prev_mty_next;

    reg [1023:0] out_axis_tdata_reg, out_axis_tdata_next;
    reg  out_axis_tvalid_reg, out_axis_tvalid_next;
    reg  out_axis_tlast_reg, out_axis_tlast_next;
    reg  out_axis_tuser_reg, out_axis_tuser_next;

    reg [1023:0] s_axis_seg_tdata_del;
    reg       s_axis_seg_tvalid_del;
    reg [7:0] s_ena_del;
    reg [7:0] s_sop_del;
    reg [7:0] s_eop_del;
    reg [7:0] s_err_del;
    reg [31:0] s_mty_del;

    reg extra_cycle_reg, extra_cycle_next;

    reg [128*8-1:0] shift_axi_seg_tdata;
    reg shift_axi_seg_tvalid;
    reg [7:0] shift_axi_seg_ena;
    reg [7:0] shift_axi_seg_sop;
    reg [7:0] shift_axi_seg_eop;
    reg [7:0] shift_axi_seg_err;
    reg [4*8-1:0] shift_axi_seg_mty;

    wire [16*8-1:0] shift_axis_tkeep;

    reg [128*8-1:0] save_axi_seg_tdata_reg;
    reg [7:0] save_axi_seg_ena_reg;
    reg [7:0] save_axi_seg_sop_reg;
    reg [7:0] save_axi_seg_eop_reg;
    reg [7:0] save_axi_seg_err_reg;
    reg [4*8-1:0] save_axi_seg_mty_reg;

    reg shift_axi_seg_extra_cycle_reg;

    reg transfer_in_save;
    reg flush_save;

    reg wait_1_cycle;

    reg enable_read_reg, enable_read_next;

    always @(*) begin

        m_axis_tdata_int = {1024{1'b0}};
        m_axis_tkeep_int = {128{1'b0}};
        m_axis_tvalid_int = 1'b0;
        m_axis_tlast_int = 1'b0;
        m_axis_tuser_int = 1'b0;

        enable_read_next = enable_read_reg;

        wait_1_cycle = 1'b0;

        if (s_axis_seg_tvalid) begin

            case (s_ena & s_sop)
                8'h01: begin
                    current_align_next = 3'd0;
                end
                8'h02: begin
                    current_align_next = 3'd1;
                end
                8'h04: begin
                    current_align_next = 3'd2;
                end
                8'h08: begin
                    current_align_next = 3'd3;
                end
                8'h10: begin
                    current_align_next = 3'd4;
                end
                8'h20: begin
                    current_align_next = 3'd5;
                end
                8'h40: begin
                    current_align_next = 3'd6;
                end
                8'h80: begin
                    current_align_next = 3'd7;
                end
                default : begin
                    current_align_next = current_align_reg;
                end
            endcase
        end else begin
            current_align_next = current_align_reg;
        end

        case(current_align_reg)
            4'd0: begin

                // passthrough if no overlap
                shift_axi_seg_tdata   = s_axis_seg_tdata_del;
                shift_axi_seg_tvalid  = s_axis_seg_tvalid_del;
                shift_axi_seg_ena     = s_ena_del;
                shift_axi_seg_sop     = s_sop_del;
                shift_axi_seg_eop     = s_eop_del;
                shift_axi_seg_err     = s_err_del;
                shift_axi_seg_mty     = s_mty_del;

            end
            4'd1: begin
                if (shift_axi_seg_extra_cycle_reg) begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> 128;
                    shift_axi_seg_tvalid  = 1'b1;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 1;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 1;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 1;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 1;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (1*4);
                end else begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> 128;
                    shift_axi_seg_tvalid  = s_axis_seg_tvalid_del;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 1;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 1;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 1;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 1;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (1*4);
                end
            end
            4'd2: begin
                if (shift_axi_seg_extra_cycle_reg) begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> (2*128);
                    shift_axi_seg_tvalid  = 1'b1;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 2;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 2;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 2;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 2;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (2*4);
                end else begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> (2*128);
                    shift_axi_seg_tvalid  = s_axis_seg_tvalid_del;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 2;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 2;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 2;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 2;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (2*4);
                end
            end
            4'd3: begin
                if (shift_axi_seg_extra_cycle_reg) begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> (3*128);
                    shift_axi_seg_tvalid  = 1'b1;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 3;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 3;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 3;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 3;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (3*4);
                end else begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> (3*128);
                    shift_axi_seg_tvalid  = s_axis_seg_tvalid_del;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 3;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 3;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 3;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 3;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (3*4);
                end
            end
            4'd4: begin
                if (shift_axi_seg_extra_cycle_reg) begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> (4*128);
                    shift_axi_seg_tvalid  = 1'b1;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 4;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 4;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 4;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 4;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (4*4);
                end else begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> (4*128);
                    shift_axi_seg_tvalid  = s_axis_seg_tvalid_del;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 4;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 4;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 4;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 4;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (4*4);
                end
            end
            4'd5: begin
                if (shift_axi_seg_extra_cycle_reg) begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> (5*128);
                    shift_axi_seg_tvalid  = 1'b1;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 5;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 5;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 5;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 5;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (5*4);
                end else begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> (5*128);
                    shift_axi_seg_tvalid  = s_axis_seg_tvalid_del;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 5;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 5;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 5;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 5;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (5*4);
                end
            end
            4'd6: begin
                if (shift_axi_seg_extra_cycle_reg) begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> (6*128);
                    shift_axi_seg_tvalid  = 1'b1;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 6;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 6;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 6;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 6;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (6*4);
                end else begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> (6*128);
                    shift_axi_seg_tvalid  = s_axis_seg_tvalid_del;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 6;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 6;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 6;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 6;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (6*4);
                end
            end
            4'd7: begin
                if (shift_axi_seg_extra_cycle_reg) begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> (7*128);
                    shift_axi_seg_tvalid  = 1'b1;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 7;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 7;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 7;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 7;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (7*4);
                end else begin
                    shift_axi_seg_tdata   = {s_axis_seg_tdata_del, save_axi_seg_tdata_reg} >> (7*128);
                    shift_axi_seg_tvalid  = s_axis_seg_tvalid_del;
                    shift_axi_seg_ena     = {s_ena_del, save_axi_seg_ena_reg} >> 7;
                    shift_axi_seg_sop     = {s_sop_del, save_axi_seg_sop_reg} >> 7;
                    shift_axi_seg_eop     = {s_eop_del, save_axi_seg_eop_reg} >> 7;
                    shift_axi_seg_err     = {s_err_del, save_axi_seg_err_reg} >> 7;
                    shift_axi_seg_mty     = {s_mty_del, save_axi_seg_mty_reg} >> (7*4);
                end
            end
        endcase

        flush_save = 1'b0;
        transfer_in_save = 1'b0;

        if (s_axis_seg_tvalid_del || shift_axi_seg_extra_cycle_reg ) begin
            transfer_in_save = 1'b1;

            if (current_align_reg > 3'd0) begin
                enable_read_next  = 1'b1;
            end



            if (|(shift_axi_seg_eop & shift_axi_seg_ena) & shift_axi_seg_tvalid) begin
                flush_save = 1'b1;
                enable_read_next = 1'b0;
            end

        end

        if (enable_read_reg || (current_align_reg == 3'd0)) begin
            m_axis_tdata_int = shift_axi_seg_tdata;
            m_axis_tkeep_int = shift_axis_tkeep;
            m_axis_tvalid_int = |(shift_axi_seg_ena) & shift_axi_seg_tvalid;
            m_axis_tlast_int = |(shift_axi_seg_ena & shift_axi_seg_eop) & shift_axi_seg_tvalid;
            m_axis_tuser_int = |(shift_axi_seg_ena & shift_axi_seg_err) & shift_axi_seg_tvalid;
        end

    end

    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin
            mapmty2tkeep #(
            .REGISTER(1'b0)
            ) mapmty2tkeep_instance (
                .clk(s_clk),
                .rst(s_rst),
                .s_mty(shift_axi_seg_mty[4*k+:4]),
                .s_ena(shift_axi_seg_ena[k] & shift_axi_seg_tvalid),
                .m_axis_tkeep(shift_axis_tkeep[16*k+:16])
            );

        end
    endgenerate



    always @(posedge s_clk) begin
        if (s_rst) begin
            enable_read_reg <= 1'b0;

            s_axis_seg_tdata_del  <= {1024{1'b0}};
            s_axis_seg_tvalid_del <= 1'b0;
            s_ena_del <= 8'h0;
            s_sop_del <= 8'h0;
            s_eop_del <= 8'h0;
            s_err_del <= 8'h0;
            s_mty_del <= 32'h00000000;

            current_align_reg <= 3'd0;

            save_axi_seg_tdata_reg <= {1024{1'b0}};
            save_axi_seg_ena_reg   <= 8'h0;
            save_axi_seg_sop_reg   <= 8'h0;
            save_axi_seg_eop_reg   <= 8'h0;
            save_axi_seg_err_reg   <= 8'h0;
            save_axi_seg_mty_reg   <= 32'h00000000;

            shift_axi_seg_extra_cycle_reg <= 1'b0;

            m_axis_tdata_reg  <= {1024{1'b0}} ;
            m_axis_tkeep_reg  <= {128{1'b0}}; ;
            m_axis_tvalid_reg <= 1'b0;
            m_axis_tlast_reg  <= 1'b0;
            m_axis_tuser_reg  <= 1'b0;

        end else begin
            s_axis_seg_tdata_del <= s_axis_seg_tdata;
            s_axis_seg_tvalid_del <= s_axis_seg_tvalid;
            s_ena_del <= s_ena;
            s_sop_del <= s_sop;
            s_eop_del <= s_eop;
            s_err_del <= s_err;
            s_mty_del <= s_mty;

            enable_read_reg <= enable_read_next;


            current_align_reg <= current_align_next;

            if (transfer_in_save) begin
                save_axi_seg_tdata_reg <= s_axis_seg_tdata_del;
                save_axi_seg_ena_reg   <= s_ena_del;
                save_axi_seg_sop_reg   <= s_sop_del;
                save_axi_seg_err_reg   <= s_err_del;
                save_axi_seg_mty_reg   <= s_mty_del;
            end

            if (flush_save) begin
                save_axi_seg_eop_reg          <= 8'h0;
                shift_axi_seg_extra_cycle_reg <= 1'b0;
            end else if (transfer_in_save) begin
                save_axi_seg_eop_reg          <= s_eop_del;
                shift_axi_seg_extra_cycle_reg <= current_align_reg != 3'd0 ? |(s_ena_del & s_eop_del) : 1'b0;
            end

            m_axis_tdata_reg  <= m_axis_tdata_int ;
            m_axis_tkeep_reg  <= m_axis_tkeep_int ;
            m_axis_tvalid_reg <= m_axis_tvalid_int;
            m_axis_tlast_reg  <= m_axis_tlast_int ;
            m_axis_tuser_reg  <= m_axis_tuser_int ;
        end

    end

    generate

        if (ASYNC_FIFO) begin
            axis_async_fifo #(
                .DEPTH(FIFO_DEPTH),
                .DATA_WIDTH(1024),
                .KEEP_ENABLE(1),
                .RAM_PIPELINE(1),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .DROP_WHEN_FULL(1), 
                .FRAME_FIFO(1)
            ) axis_fifo_instance (
                .s_clk(s_clk),
                .s_rst(s_rst),
                .s_axis_tdata(m_axis_tdata_reg),
                .s_axis_tkeep(m_axis_tkeep_reg),
                .s_axis_tvalid(m_axis_tvalid_reg),
                .s_axis_tready(),
                .s_axis_tlast(m_axis_tlast_reg),
                .s_axis_tid(0),
                .s_axis_tdest(0),
                .s_axis_tuser(m_axis_tuser_reg),

                .m_clk(m_clk),
                .m_rst(m_rst),
                .m_axis_tdata(m_axis_tdata),
                .m_axis_tkeep(m_axis_tkeep),
                .m_axis_tvalid(m_axis_tvalid),
                .m_axis_tready(m_axis_tready),
                .m_axis_tlast(m_axis_tlast),
                .m_axis_tid(),
                .m_axis_tdest(),
                .m_axis_tuser(m_axis_tuser)
            );
        end else begin
            axis_fifo #(
                .DEPTH(FIFO_DEPTH),
                .DATA_WIDTH(1024),
                .KEEP_ENABLE(1),
                .RAM_PIPELINE(1),
                .USER_ENABLE(1),
                .USER_WIDTH(1),
                .DROP_WHEN_FULL(1),
                .FRAME_FIFO(1)
            ) axis_fifo_instance (
                .clk(m_clk),
                .rst(m_rst),
                .s_axis_tdata(m_axis_tdata_reg),
                .s_axis_tkeep(m_axis_tkeep_reg),
                .s_axis_tvalid(m_axis_tvalid_reg),
                .s_axis_tready(),
                .s_axis_tlast(m_axis_tlast_reg),
                .s_axis_tid(0),
                .s_axis_tdest(0),
                .s_axis_tuser(m_axis_tuser_reg),

                .m_axis_tdata(m_axis_tdata),
                .m_axis_tkeep(m_axis_tkeep),
                .m_axis_tvalid(m_axis_tvalid),
                .m_axis_tready(m_axis_tready),
                .m_axis_tlast(m_axis_tlast),
                .m_axis_tid(),
                .m_axis_tdest(),
                .m_axis_tuser(m_axis_tuser)
            );
        end
    endgenerate

endmodule

`resetall