`resetall
`timescale 1ns / 1ps
`default_nettype none

module RoCE_arb_mux #
(
    parameter S_COUNT = 4,
    parameter DATA_WIDTH = 8,
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    parameter USER_ENABLE = 1,
    parameter USER_WIDTH = 1,
    // select round robin arbitration
    parameter ARB_TYPE_ROUND_ROBIN = 0,
    // LSB priority selection
    parameter ARB_LSB_HIGH_PRIORITY = 1
)
(
    input  wire                          clk,
    input  wire                          rst,

    /*
     * RoCE TX frame input
     */
    // BTH
    input  wire [S_COUNT   -1:0] s_roce_bth_valid,
    output wire [S_COUNT   -1:0] s_roce_bth_ready,
    input  wire [S_COUNT*8 -1:0] s_roce_bth_op_code,
    input  wire [S_COUNT*16-1:0] s_roce_bth_p_key,
    input  wire [S_COUNT*24-1:0] s_roce_bth_psn,
    input  wire [S_COUNT*24-1:0] s_roce_bth_dest_qp,
    input  wire [S_COUNT*24-1:0] s_roce_bth_src_qp,
    input  wire [S_COUNT   -1:0] s_roce_bth_ack_req,
    // RETH
    input  wire [S_COUNT   -1:0] s_roce_reth_valid,
    output wire [S_COUNT   -1:0] s_roce_reth_ready,
    input  wire [S_COUNT*64-1:0] s_roce_reth_v_addr,
    input  wire [S_COUNT*32-1:0] s_roce_reth_r_key,
    input  wire [S_COUNT*32-1:0] s_roce_reth_length,
    // IMMD
    input  wire [S_COUNT   -1:0] s_roce_immdh_valid,
    output wire [S_COUNT   -1:0] s_roce_immdh_ready,
    input  wire [S_COUNT*32-1:0] s_roce_immdh_data,

    input  wire [S_COUNT*32-1:0] s_ip_dest_ip,
    input  wire [S_COUNT*16-1:0] s_udp_source_port,
    input  wire [S_COUNT*16-1:0] s_udp_length,
    // payload
    input  wire [S_COUNT*DATA_WIDTH-1:0] s_roce_payload_axis_tdata,
    input  wire [S_COUNT*KEEP_WIDTH-1:0] s_roce_payload_axis_tkeep,
    input  wire [S_COUNT           -1:0] s_roce_payload_axis_tvalid,
    output wire [S_COUNT           -1:0] s_roce_payload_axis_tready,
    input  wire [S_COUNT           -1:0] s_roce_payload_axis_tlast,
    input  wire [S_COUNT*USER_WIDTH-1:0] s_roce_payload_axis_tuser,

    output  wire         m_roce_bth_valid,
    input   wire         m_roce_bth_ready,
    output  wire [  7:0] m_roce_bth_op_code,
    output  wire [ 15:0] m_roce_bth_p_key,
    output  wire [ 23:0] m_roce_bth_psn,
    output  wire [ 23:0] m_roce_bth_dest_qp,
    output  wire [ 23:0] m_roce_bth_src_qp,
    output  wire         m_roce_bth_ack_req,
    // RETH
    output  wire         m_roce_reth_valid,
    input   wire         m_roce_reth_ready,
    output  wire [ 63:0] m_roce_reth_v_addr,
    output  wire [ 31:0] m_roce_reth_r_key,
    output  wire [ 31:0] m_roce_reth_length,
    // IMMD
    output  wire         m_roce_immdh_valid,
    input wire           m_roce_immdh_ready,
    output  wire [ 31:0] m_roce_immdh_data,

    output  wire [ 31:0] m_ip_dest_ip,
    output  wire [ 15:0] m_udp_source_port,
    output  wire [ 15:0] m_udp_length,
    // payload
    output  wire [DATA_WIDTH   - 1 :0] m_roce_payload_axis_tdata,
    output  wire [KEEP_WIDTH   - 1 :0] m_roce_payload_axis_tkeep,
    output  wire                       m_roce_payload_axis_tvalid,
    input   wire                       m_roce_payload_axis_tready,
    output  wire                       m_roce_payload_axis_tlast,
    output  wire [USER_WIDTH   - 1 :0] m_roce_payload_axis_tuser
);

    import RoCE_params::*; // Imports RoCE parameters

    parameter CL_S_COUNT = $clog2(S_COUNT);

    reg frame_reg = 1'b0, frame_next;
    reg single_frame_pkt_reg = 1'b0, single_frame_pkt_next;

    reg [S_COUNT-1:0] s_roce_bth_ready_reg = {S_COUNT{1'b0}}, s_roce_bth_ready_next;

    reg m_roce_bth_valid_reg = 1'b0, m_roce_bth_valid_next;
    reg [7 :0] m_roce_bth_op_code_reg = 8'd0, m_roce_bth_op_code_next;
    reg [15:0] m_roce_bth_p_key_reg = 16'd0, m_roce_bth_p_key_next;
    reg [23:0] m_roce_bth_psn_reg = 24'd0, m_roce_bth_psn_next;
    reg [23:0] m_roce_bth_dest_qp_reg = 24'd0, m_roce_bth_dest_qp_next;
    reg [23:0] m_roce_bth_src_qp_reg = 24'd0, m_roce_bth_src_qp_next;
    reg        m_roce_bth_ack_req_reg = 1'b0, m_roce_bth_ack_req_next;
    reg m_roce_reth_valid_reg = 1'b0, m_roce_reth_valid_next;
    reg [63:0] m_roce_reth_v_addr_reg = 64'd0, m_roce_reth_v_addr_next;
    reg [31:0] m_roce_reth_r_key_reg = 32'd0, m_roce_reth_r_key_next;
    reg [31:0] m_roce_reth_length_reg = 32'd0, m_roce_reth_length_next;
    reg m_roce_immdh_valid_reg = 1'b0, m_roce_immdh_valid_next;
    reg [31:0] m_roce_immdh_data_reg = 32'd0, m_roce_immdh_data_next;
    reg [31:0] m_ip_dest_ip_reg = 32'd0, m_ip_dest_ip_next;
    reg [15:0] m_udp_source_port_reg = 16'd0, m_udp_source_port_next;
    reg [15:0] m_udp_length_reg = 16'd0, m_udp_length_next;

    wire [S_COUNT-1:0] request;
    wire [S_COUNT-1:0] acknowledge;
    wire [S_COUNT-1:0] grant;
    wire grant_valid;
    wire [CL_S_COUNT-1:0] grant_encoded;

    // internal datapath
    reg  [DATA_WIDTH-1:0] m_roce_payload_axis_tdata_int;
    reg  [KEEP_WIDTH-1:0] m_roce_payload_axis_tkeep_int;
    reg                   m_roce_payload_axis_tvalid_int;
    reg                   m_roce_payload_axis_tready_int_reg = 1'b0;
    reg                   m_roce_payload_axis_tlast_int;
    reg  [USER_WIDTH-1:0] m_roce_payload_axis_tuser_int;
    wire                  m_roce_payload_axis_tready_int_early;

    wire [S_COUNT-1:0] ack_hdr;
    reg  [S_COUNT-1:0] ack_hdr_reg;
    wire [S_COUNT-1:0] ack_payload;
    reg  [S_COUNT-1:0] ack_payload_reg;

    reg hdr_first;
    reg payload_first;

    wire output_has_reth =
    m_roce_bth_op_code == RC_RDMA_WRITE_FIRST ||
    m_roce_bth_op_code == RC_RDMA_WRITE_ONLY ||
    m_roce_bth_op_code == RC_RDMA_WRITE_ONLY_IMD;

    wire output_has_immediate =
    m_roce_bth_op_code == RC_RDMA_WRITE_LAST_IMD ||
    m_roce_bth_op_code == RC_RDMA_WRITE_ONLY_IMD ||
    m_roce_bth_op_code == RC_SEND_LAST_IMD ||
    m_roce_bth_op_code == RC_SEND_ONLY_IMD ;


    assign s_roce_bth_ready = s_roce_bth_ready_reg;
    assign s_roce_reth_ready = s_roce_bth_ready_reg;
    assign s_roce_immdh_ready = s_roce_bth_ready_reg;

    assign s_roce_payload_axis_tready = (m_roce_payload_axis_tready_int_reg && grant_valid) << grant_encoded;
    //assign s_udp_payload_axis_tready = m_udp_payload_axis_tready_int_reg << grant_encoded;

    assign m_roce_bth_valid = m_roce_bth_valid_reg;
    assign m_roce_reth_valid = m_roce_bth_valid_reg && output_has_reth;
    assign m_roce_immdh_valid = m_roce_bth_valid_reg && output_has_immediate;

    assign m_roce_bth_op_code = m_roce_bth_op_code_reg;
    assign m_roce_bth_p_key = m_roce_bth_p_key_reg;
    assign m_roce_bth_psn = m_roce_bth_psn_reg;
    assign m_roce_bth_dest_qp = m_roce_bth_dest_qp_reg;
    assign m_roce_bth_src_qp = m_roce_bth_src_qp_reg;
    assign m_roce_bth_ack_req = m_roce_bth_ack_req_reg;
    assign m_roce_reth_v_addr = m_roce_reth_v_addr_reg;
    assign m_roce_reth_r_key = m_roce_reth_r_key_reg;
    assign m_roce_reth_length = m_roce_reth_length_reg;
    assign m_roce_immdh_data = m_roce_immdh_data_reg;
    assign m_ip_dest_ip = m_ip_dest_ip_reg;
    assign m_udp_source_port = m_udp_source_port_reg;
    assign m_udp_length = m_udp_length_reg;

    // mux for incoming packet
    wire [DATA_WIDTH-1:0] current_s_tdata  = s_roce_payload_axis_tdata[grant_encoded*DATA_WIDTH +: DATA_WIDTH];
    wire [KEEP_WIDTH-1:0] current_s_tkeep  = s_roce_payload_axis_tkeep[grant_encoded*KEEP_WIDTH +: KEEP_WIDTH];
    wire                  current_s_tvalid = s_roce_payload_axis_tvalid[grant_encoded];
    wire                  current_s_tready = s_roce_payload_axis_tready[grant_encoded];
    wire                  current_s_tlast  = s_roce_payload_axis_tlast[grant_encoded];
    wire [USER_WIDTH-1:0] current_s_tuser  = s_roce_payload_axis_tuser[grant_encoded*USER_WIDTH +: USER_WIDTH];

    // arbiter instance
    arbiter #(
        .PORTS(S_COUNT),
        .ARB_TYPE_ROUND_ROBIN(ARB_TYPE_ROUND_ROBIN),
        .ARB_BLOCK(1),
        .ARB_BLOCK_ACK(1),
        .ARB_LSB_HIGH_PRIORITY(ARB_LSB_HIGH_PRIORITY)
    )
    arb_inst (
        .clk(clk),
        .rst(rst),
        .request(request),
        .acknowledge(acknowledge),
        .grant(grant),
        .grant_valid(grant_valid),
        .grant_encoded(grant_encoded)
    );

    // case if tlast comes before hdr_ready
    assign ack_hdr     = grant & s_roce_bth_valid & s_roce_bth_ready;
    assign ack_payload = grant & s_roce_payload_axis_tvalid & s_roce_payload_axis_tready & s_roce_payload_axis_tlast;

    always @(posedge clk) begin

        if (rst) begin
            ack_hdr_reg <= 0;
            ack_payload_reg <= 0;
            hdr_first <= 1'b0;
            payload_first <= 1'b0;
        end else begin
            // case if hdr comes before tlast (usual case)
            if (ack_hdr != 0) begin
                if (ack_hdr != ack_payload && ~payload_first) begin
                    ack_hdr_reg <= ack_hdr;
                    hdr_first <= 1'b1;
                end
            end
            if (ack_hdr_reg != 0) begin
                if (ack_hdr_reg == ack_payload && hdr_first) begin
                    ack_hdr_reg <= 0;
                    hdr_first <= 1'b0;
                end
            end

            // case if tlast comes before hdr (happens if payload is only 1 frame)
            if (ack_payload != 0) begin
                if (ack_payload != ack_hdr && ~hdr_first) begin
                    ack_payload_reg <= ack_payload;
                    payload_first <= 1'b1;
                end
            end
            if (ack_payload_reg != 0) begin
                if (ack_payload_reg == ack_hdr && payload_first) begin
                    ack_payload_reg <= 0;
                    payload_first <= 1'b0;
                end
            end
        end
    end

    //assign request = s_udp_hdr_valid & ~grant;
    assign request = s_roce_bth_valid & ~grant;
    //assign acknowledge = grant & s_udp_payload_axis_tvalid & s_udp_payload_axis_tready & s_udp_payload_axis_tlast;
    assign acknowledge = hdr_first ? ack_hdr_reg & ack_payload : (payload_first ? ack_hdr & ack_payload_reg : ack_hdr & ack_payload);

    always @* begin
        frame_next = frame_reg;
        single_frame_pkt_next = single_frame_pkt_reg;

        s_roce_bth_ready_next = {S_COUNT{1'b0}};

        m_roce_bth_valid_next = m_roce_bth_valid_reg && !m_roce_bth_ready;

        m_roce_bth_op_code_next = m_roce_bth_op_code_reg;
        m_roce_bth_p_key_next = m_roce_bth_p_key_reg;
        m_roce_bth_psn_next = m_roce_bth_psn_reg;
        m_roce_bth_dest_qp_next = m_roce_bth_dest_qp_reg;
        m_roce_bth_src_qp_next = m_roce_bth_src_qp_reg;
        m_roce_bth_ack_req_next = m_roce_bth_ack_req_reg;
        m_roce_reth_v_addr_next = m_roce_reth_v_addr_reg;
        m_roce_reth_r_key_next = m_roce_reth_r_key_reg;
        m_roce_reth_length_next = m_roce_reth_length_reg;
        m_roce_immdh_data_next = m_roce_immdh_data_reg;
        m_ip_dest_ip_next = m_ip_dest_ip_reg;
        m_udp_source_port_next = m_udp_source_port_reg;
        m_udp_length_next = m_udp_length_reg;



        if (s_roce_payload_axis_tvalid[grant_encoded] && s_roce_payload_axis_tready[grant_encoded]) begin
            // end of frame detection
            if (s_roce_payload_axis_tlast[grant_encoded]) begin
                frame_next = 1'b0;
            end
            //end else if (single_frame_pkt_reg) begin
            //frame_next = 1'b0;
        end

        // case if frame_next is stuck to 1'b1
        if (frame_reg && acknowledge != 0) begin
            frame_next = 1'b0;
        end


        if ((!frame_reg) && grant_valid && (m_roce_bth_ready || !m_roce_bth_valid)) begin
            // start of frame
            frame_next = 1'b1;

            single_frame_pkt_next = s_roce_payload_axis_tvalid[grant_encoded] & s_roce_payload_axis_tlast[grant_encoded];

            s_roce_bth_ready_next = grant;

            m_roce_bth_valid_next = 1'b1;

            m_roce_bth_op_code_next = s_roce_bth_op_code[grant_encoded*8 +: 8];
            m_roce_bth_p_key_next = s_roce_bth_p_key[grant_encoded*16 +: 16];
            m_roce_bth_psn_next = s_roce_bth_psn[grant_encoded*24 +: 24];
            m_roce_bth_dest_qp_next = s_roce_bth_dest_qp[grant_encoded*24 +: 24];
            m_roce_bth_src_qp_next = s_roce_bth_src_qp[grant_encoded*24 +: 24];
            m_roce_bth_ack_req_next = s_roce_bth_ack_req[grant_encoded*1 +: 1];
            m_roce_reth_v_addr_next = s_roce_reth_v_addr[grant_encoded*64 +: 64];
            m_roce_reth_r_key_next = s_roce_reth_r_key[grant_encoded*32 +: 32];
            m_roce_reth_length_next = s_roce_reth_length[grant_encoded*32 +: 32];
            m_roce_immdh_data_next = s_roce_immdh_data[grant_encoded*32 +: 32];
            m_ip_dest_ip_next = s_ip_dest_ip[grant_encoded*32 +: 32];
            m_udp_source_port_next = s_udp_source_port[grant_encoded*16 +: 16];
            m_udp_length_next = s_udp_length[grant_encoded*16 +: 16];
        end

        if (single_frame_pkt_reg) begin
            single_frame_pkt_next = 1'b0;
        end

        // pass through selected packet data
        m_roce_payload_axis_tdata_int  = current_s_tdata;
        m_roce_payload_axis_tkeep_int  = current_s_tkeep;
        m_roce_payload_axis_tvalid_int = current_s_tvalid && m_roce_payload_axis_tready_int_reg && grant_valid;
        //m_udp_payload_axis_tvalid_int = current_s_tvalid && m_udp_payload_axis_tready_int_reg;
        m_roce_payload_axis_tlast_int  = current_s_tlast;
        m_roce_payload_axis_tuser_int  = current_s_tuser;
    end

    always @(posedge clk) begin
        frame_reg <= frame_next;

        s_roce_bth_ready_reg <= s_roce_bth_ready_next;

        m_roce_bth_valid_reg <= m_roce_bth_valid_next;
        m_roce_bth_op_code_reg <= m_roce_bth_op_code_next;
        m_roce_bth_p_key_reg <= m_roce_bth_p_key_next;
        m_roce_bth_psn_reg <= m_roce_bth_psn_next;
        m_roce_bth_dest_qp_reg <= m_roce_bth_dest_qp_next;
        m_roce_bth_src_qp_reg <= m_roce_bth_src_qp_next;
        m_roce_bth_ack_req_reg <= m_roce_bth_ack_req_next;
        m_roce_reth_v_addr_reg <= m_roce_reth_v_addr_next;
        m_roce_reth_r_key_reg <= m_roce_reth_r_key_next;
        m_roce_reth_length_reg <= m_roce_reth_length_next;
        m_roce_immdh_data_reg <= m_roce_immdh_data_next;
        m_ip_dest_ip_reg <= m_ip_dest_ip_next;
        m_udp_source_port_reg <= m_udp_source_port_next;
        m_udp_length_reg <= m_udp_length_next;

        if (rst) begin
            frame_reg <= 1'b0;
            s_roce_bth_ready_reg <= {S_COUNT{1'b0}};
            m_roce_bth_valid_reg <= 1'b0;
        end
    end

    // output datapath logic
    reg [DATA_WIDTH-1:0] m_roce_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] m_roce_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
    reg                  m_roce_payload_axis_tvalid_reg = 1'b0, m_roce_payload_axis_tvalid_next;
    reg                  m_roce_payload_axis_tlast_reg  = 1'b0;
    reg [USER_WIDTH-1:0] m_roce_payload_axis_tuser_reg  = {USER_WIDTH{1'b0}};

    reg [DATA_WIDTH-1:0] temp_m_roce_payload_axis_tdata_reg  = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] temp_m_roce_payload_axis_tkeep_reg  = {KEEP_WIDTH{1'b0}};
    reg                  temp_m_roce_payload_axis_tvalid_reg = 1'b0, temp_m_roce_payload_axis_tvalid_next;
    reg                  temp_m_roce_payload_axis_tlast_reg  = 1'b0;
    reg [USER_WIDTH-1:0] temp_m_roce_payload_axis_tuser_reg  = {USER_WIDTH{1'b0}};

    // datapath control
    reg store_axis_int_to_output;
    reg store_axis_int_to_temp;
    reg store_roce_payload_axis_temp_to_output;

    assign m_roce_payload_axis_tdata  = m_roce_payload_axis_tdata_reg;
    assign m_roce_payload_axis_tkeep  = KEEP_ENABLE ? m_roce_payload_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
    assign m_roce_payload_axis_tvalid = m_roce_payload_axis_tvalid_reg;
    assign m_roce_payload_axis_tlast  = m_roce_payload_axis_tlast_reg;
    assign m_roce_payload_axis_tuser  = USER_ENABLE ? m_roce_payload_axis_tuser_reg : {USER_WIDTH{1'b0}};

    // enable ready input next cycle if output is ready or if both output registers are empty
    assign m_roce_payload_axis_tready_int_early = m_roce_payload_axis_tready || (!temp_m_roce_payload_axis_tvalid_reg && !m_roce_payload_axis_tvalid_reg);

    always @* begin
        // transfer sink ready state to source
        m_roce_payload_axis_tvalid_next = m_roce_payload_axis_tvalid_reg;
        temp_m_roce_payload_axis_tvalid_next = temp_m_roce_payload_axis_tvalid_reg;

        store_axis_int_to_output = 1'b0;
        store_axis_int_to_temp = 1'b0;
        store_roce_payload_axis_temp_to_output = 1'b0;

        if (m_roce_payload_axis_tready_int_reg) begin
            // input is ready
            if (m_roce_payload_axis_tready || !m_roce_payload_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_roce_payload_axis_tvalid_next = m_roce_payload_axis_tvalid_int;
                store_axis_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_roce_payload_axis_tvalid_next = m_roce_payload_axis_tvalid_int;
                store_axis_int_to_temp = 1'b1;
            end
        end else if (m_roce_payload_axis_tready) begin
            // input is not ready, but output is ready
            m_roce_payload_axis_tvalid_next = temp_m_roce_payload_axis_tvalid_reg;
            temp_m_roce_payload_axis_tvalid_next = 1'b0;
            store_roce_payload_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        m_roce_payload_axis_tvalid_reg <= m_roce_payload_axis_tvalid_next;
        m_roce_payload_axis_tready_int_reg <= m_roce_payload_axis_tready_int_early;
        temp_m_roce_payload_axis_tvalid_reg <= temp_m_roce_payload_axis_tvalid_next;

        // datapath
        if (store_axis_int_to_output) begin
            m_roce_payload_axis_tdata_reg <= m_roce_payload_axis_tdata_int;
            m_roce_payload_axis_tkeep_reg <= m_roce_payload_axis_tkeep_int;
            m_roce_payload_axis_tlast_reg <= m_roce_payload_axis_tlast_int;
            m_roce_payload_axis_tuser_reg <= m_roce_payload_axis_tuser_int;
        end else if (store_roce_payload_axis_temp_to_output) begin
            m_roce_payload_axis_tdata_reg <= temp_m_roce_payload_axis_tdata_reg;
            m_roce_payload_axis_tkeep_reg <= temp_m_roce_payload_axis_tkeep_reg;
            m_roce_payload_axis_tlast_reg <= temp_m_roce_payload_axis_tlast_reg;
            m_roce_payload_axis_tuser_reg <= temp_m_roce_payload_axis_tuser_reg;
        end

        if (store_axis_int_to_temp) begin
            temp_m_roce_payload_axis_tdata_reg <= m_roce_payload_axis_tdata_int;
            temp_m_roce_payload_axis_tkeep_reg <= m_roce_payload_axis_tkeep_int;
            temp_m_roce_payload_axis_tlast_reg <= m_roce_payload_axis_tlast_int;
            temp_m_roce_payload_axis_tuser_reg <= m_roce_payload_axis_tuser_int;
        end

        if (rst) begin
            m_roce_payload_axis_tvalid_reg <= 1'b0;
            m_roce_payload_axis_tready_int_reg <= 1'b0;
            temp_m_roce_payload_axis_tvalid_reg <= 1'b0;
        end
    end

endmodule

`resetall
