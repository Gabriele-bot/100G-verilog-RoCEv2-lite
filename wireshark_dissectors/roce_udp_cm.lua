-- Custom RoCE UDP Connection manager dissector
-- Big Endian

local roce_udp_cm = Proto("UDP_RoCE_CM", "RoCE UDP Connection Manager")

------------------------------------------------------------
-- Request / Reply Mappings
------------------------------------------------------------

local request_vals = {
    [0x0] = "REQ_NULL",
    [0x1] = "REQ_OPEN_QP",
    [0x2] = "REQ_SEND_QP_INFO",
    [0x3] = "REQ_MODIFY_QP_RTS",
    [0x4] = "REQ_CLOSE_QP",
    [0x7] = "REQ_ERROR"
}

local ack_reply_vals = {
    [0x0] = "ACK_NULL",
    [0x1] = "ACK_ACK",
    [0x2] = "ACK_NO_QP",
    [0x3] = "ACK_NAK",
    [0x7] = "ACK_ERROR"
}

------------------------------------------------------------
-- Field Definitions
------------------------------------------------------------

-- First byte (4 bits each)
local f_request        = ProtoField.uint8("UDP_RoCE_CM.request", "Request", base.HEX, request_vals, 0x0E)
local f_request_valid  = ProtoField.bool("UDP_RoCE_CM.request.valid", "Request Valid", 8, nil, 0x01)

local f_ack_reply          = ProtoField.uint8("UDP_RoCE_CM.ack_reply", "ACK Reply", base.HEX, ack_reply_vals, 0xE0)
local f_ack_reply_valid    = ProtoField.bool("UDP_RoCE_CM.ack_reply.valid", "ACK Reply Valid", 8, nil, 0x10)

-- Local fields
local f_loc_qpn        = ProtoField.uint32("UDP_RoCE_CM.loc_qpn", "Local QPN", base.HEX)
local f_loc_psn        = ProtoField.uint32("UDP_RoCE_CM.loc_psn", "Local PSN", base.DEC)
local f_loc_rkey       = ProtoField.uint32("UDP_RoCE_CM.loc_rkey", "Local R_KEY", base.HEX)
local f_loc_base       = ProtoField.uint64("UDP_RoCE_CM.loc_base", "Local Base Address", base.HEX)
local f_loc_ip         = ProtoField.ipv4("UDP_RoCE_CM.loc_ip", "Local IP Address")

-- Remote fields
local f_rem_qpn        = ProtoField.uint32("UDP_RoCE_CM.rem_qpn", "Remote QPN", base.HEX)
local f_rem_psn        = ProtoField.uint32("UDP_RoCE_CM.rem_psn", "Remote PSN", base.DEC)
local f_rem_rkey       = ProtoField.uint32("UDP_RoCE_CM.rem_rkey", "Remote R_KEY", base.HEX)
local f_rem_base       = ProtoField.uint64("UDP_RoCE_CM.rem_base", "Remote Base Address", base.HEX)
local f_rem_ip         = ProtoField.ipv4("UDP_RoCE_CM.rem_ip", "Remote IP Address")

-- TX Meta
local f_listen_port    = ProtoField.uint16("UDP_RoCE_CM.listen_port", "Listen Port", base.DEC)
local f_tx_flags       = ProtoField.uint8("UDP_RoCE_CM.tx_flags", "TX Meta Flags", base.HEX)
local f_tx_dma_len     = ProtoField.uint32("UDP_RoCE_CM.tx_dma_len", "TX DMA Length", base.DEC)
local f_tx_n_transf    = ProtoField.uint32("UDP_RoCE_CM.tx_n_transf", "TX Number of Transfers", base.DEC)
local f_tx_freq        = ProtoField.uint32("UDP_RoCE_CM.tx_freq", "TX Frequency", base.DEC)

roce_udp_cm.fields = {
    f_request, f_request_valid,
    f_ack_reply, f_ack_reply_valid,
    f_loc_qpn, f_loc_psn, f_loc_rkey, f_loc_base, f_loc_ip,
    f_rem_qpn, f_rem_psn, f_rem_rkey, f_rem_base, f_rem_ip,
    f_listen_port, f_tx_flags, f_tx_dma_len, f_tx_n_transf, f_tx_freq
}

------------------------------------------------------------
-- Main Dissector Function
------------------------------------------------------------

function roce_udp_cm.dissector(buffer, pinfo, tree)
    pinfo.cols.protocol = "UDP_RoCE_CM"

    local subtree = tree:add(roce_udp_cm, buffer(), "RoCE UDP Connection Manager")
    local offset = 0

    -- First byte (4-bit Request / ACK Reply)
    subtree:add(f_request, buffer(offset,1))
    subtree:add(f_request_valid, buffer(offset,1))
    subtree:add(f_ack_reply, buffer(offset,1))
    subtree:add(f_ack_reply_valid, buffer(offset,1))
    offset = offset + 1

    -- Local Section
    local local_tree = subtree:add(roce_udp_cm, buffer(offset), "Local Parameters")
    local_tree:add(f_loc_qpn,  buffer(offset,4));  offset = offset + 4
    local_tree:add(f_loc_psn,  buffer(offset,4));  offset = offset + 4
    local_tree:add(f_loc_rkey, buffer(offset,4));  offset = offset + 4
    local_tree:add(f_loc_base, buffer(offset,8));  offset = offset + 8
    local_tree:add(f_loc_ip,   buffer(offset,4));  offset = offset + 4

    -- Remote Section
    local remote_tree = subtree:add(roce_udp_cm, buffer(offset), "Remote Parameters")
    remote_tree:add(f_rem_qpn,  buffer(offset,4));  offset = offset + 4
    remote_tree:add(f_rem_psn,  buffer(offset,4));  offset = offset + 4
    remote_tree:add(f_rem_rkey, buffer(offset,4));  offset = offset + 4
    remote_tree:add(f_rem_base, buffer(offset,8));  offset = offset + 8
    remote_tree:add(f_rem_ip,   buffer(offset,4));  offset = offset + 4

    -- TX Meta
    local meta_tree = subtree:add(roce_udp_cm, buffer(offset), "TX Meta")
    meta_tree:add(f_listen_port, buffer(offset,2)); offset = offset + 2
    meta_tree:add(f_tx_flags,       buffer(offset,1)); offset = offset + 1
    meta_tree:add(f_tx_dma_len,  buffer(offset,4)); offset = offset + 4
    meta_tree:add(f_tx_n_transf, buffer(offset,4)); offset = offset + 4
    meta_tree:add(f_tx_freq,     buffer(offset,4)); offset = offset + 4
end

------------------------------------------------------------
-- Heuristic Registration for Dynamic UDP Port
------------------------------------------------------------

roce_udp_cm:register_heuristic("udp", function(buffer, pinfo, tree)
    if buffer:len() ~= 64 then
        return false
    end

    -- Basic sanity check: Listen port must not be zero (offset 49 LE)
    local listen_port_offset = 49
    local listen_port = buffer(listen_port_offset,2):le_uint()
    if listen_port == 0 then
        return false
    end

    roce_udp_cm.dissector(buffer, pinfo, tree)
    return true
end)

