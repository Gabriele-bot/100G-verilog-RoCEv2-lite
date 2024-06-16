import struct
import numpy as np
import sys
import socket

RC_RDMA_WRITE_FIRST = 0x06
RC_RDMA_WRITE_MIDDLE = 0x07
RC_RDMA_WRITE_LAST = 0x08
RC_RDMA_WRITE_LAST_IMD = 0x09
RC_RDMA_WRITE_ONLY = 0x0a
RC_RDMA_WRITE_ONLY_IMD = 0x0b
RC_RDMA_ACK = 0x11

OP_codes = {
    0x06: 'RC_RDMA_WRITE_FIRST',
    0x07: 'RC_RDMA_WRITE_MIDDLE',
    0x08: 'RC_RDMA_WRITE_LAST',
    0x09: 'RC_RDMA_WRITE_LAST_IMD',
    0x0a: 'RC_RDMA_WRITE_ONLY',
    0x0b: 'RC_RDMA_WRITE_ONLY_IMD',
    0x11: 'RC_RDMA_ACK'
}


def reverse_poly_bits(x):
    x = np.array(x)
    n_bits = x.dtype.itemsize * 8

    x_reversed = np.zeros_like(x)
    for i in range(n_bits):
        x_reversed = (x_reversed << 1) | x & np.uint32(1)
        x >>= np.uint32(1)
    return x_reversed


def compute_crc(data, poly, crc_init):
    poly_reversed = reverse_poly_bits(np.uint32(poly))
    crc = crc_init
    for i in range(4):
        crc ^= data >> (8 * i) & 0xFF
        for j in range(8):
            mask = -(crc & 1);
            crc = (crc >> 1) ^ (poly_reversed & mask);
    return crc


class EthFrame(object):
    def __init__(self, raw_frame=b'', payload=b'', eth_dest_mac=0, eth_src_mac=0, eth_type=0, eth_fcs=None):
        self.raw_frame = raw_frame
        self._payload = payload
        self.eth_dest_mac = eth_dest_mac
        self.eth_src_mac = eth_src_mac
        self.eth_type = eth_type
        self.ip_version = 0
        self.ip_ihl = 0
        self.ip_dscp = 0
        self.ip_ecn = 0
        self.ip_length = 0
        self.ip_identification = 0
        self.ip_flags = 0
        self.ip_fragment_offset = 0
        self.ip_ttl = 0
        self.ip_protocol = 0
        self.ip_header_checksum = 0
        self.ip_source_ip = 0
        self.ip_dest_ip = 0
        self.udp_source_port = 0
        self.udp_dest_port = 0
        self.udp_length = 0
        self.udp_checksum = 0
        self.roce_bth_opcode = 0
        self.roce_bth_pkey = 0
        self.roce_bth_psn = 0
        self.roce_bth_dest_qp = 0
        self.roce_bth_ack_req = 0
        self.roce_reth_vaddr = 0
        self.roce_reth_rkey = 0
        self.roce_reth_dma_length = 0
        self.roce_icrc = 0xDEADBEEF
        self.eth_fcs = eth_fcs
        self.frame_length = len(raw_frame)

    def decode_eth_header(self):
        ethernet_frame = self.raw_frame[0:14]

        self.eth_dest_mac = struct.unpack('>Q', b'\x00\x00' + ethernet_frame[0:6])[0]
        self.eth_src_mac = struct.unpack('>Q', b'\x00\x00' + ethernet_frame[6:12])[0]
        self.eth_type = struct.unpack('>H', ethernet_frame[12:14])[0]

        self._payload = self.raw_frame[-(len(self.raw_frame) - 14):]

    def decode_ip_header(self):
        ip_header = self.raw_frame[14:34]

        v = struct.unpack('B', ip_header[0:1])[0]
        self.ip_version = (v >> 4) & 0xF
        self.ip_ihl = v & 0xF

        v = struct.unpack('B', ip_header[1:2])[0]
        self.ip_dscp = (v >> 2) & 0x3F
        self.ip_ecn = v & 0x3
        self.ip_length = struct.unpack('>H', ip_header[2:4])[0]
        self.ip_identification = struct.unpack('>H', ip_header[4:6])[0]

        v = struct.unpack('>H', ip_header[6:8])[0]
        self.ip_flags = (v >> 13) & 0x7
        self.ip_fragment_offset = v & 0x1FFF
        self.ip_ttl = struct.unpack('B', ip_header[8:9])[0]
        self.ip_protocol = struct.unpack('B', ip_header[9:10])[0]
        self.ip_header_checksum = struct.unpack('>H', ip_header[10:12])[0]
        self.ip_source_ip = struct.unpack('>L', ip_header[12:16])[0]
        self.ip_dest_ip = struct.unpack('>L', ip_header[16:20])[0]

    def decode_udp_header(self):
        udp_header = self.raw_frame[34:42]

        self.udp_source_port = struct.unpack('>H', udp_header[0:2])[0]
        self.udp_dest_port = struct.unpack('>H', udp_header[2:4])[0]
        self.udp_length = struct.unpack('>H', udp_header[4:6])[0]
        self.udp_checksum = struct.unpack('>H', udp_header[6:8])[0]

    def decode_BTH(self):
        BTH = self.raw_frame[42:54]

        self.roce_bth_opcode = struct.unpack('>B', BTH[0:1])[0]
        #reserved = struct.unpack('>B', BTH[1:2])[0]
        self.roce_bth_pkey = struct.unpack('>H', BTH[2:4])[0]
        # reserved = struct.unpack('>B', BTH[4:5])[0]
        self.roce_bth_dest_qp = struct.unpack('>L', b'\x00' + BTH[5:8])[0]
        self.roce_bth_ack_req = struct.unpack('>B', BTH[8:9])[0]
        self.roce_bth_psn = struct.unpack('>L', b'\x00' + BTH[9:12])[0]

    def decode_RETH(self):
        RETH = self.raw_frame[54:70]

        self.roce_reth_vaddr = struct.unpack('>Q', RETH[0:8])[0]
        self.roce_reth_rkey = struct.unpack('>L', RETH[8:12])[0]
        self.roce_reth_dma_length = struct.unpack('>L', RETH[12:16])[0]

    def decode_immd_data(self):
        if self.roce_bth_opcode == RC_RDMA_WRITE_ONLY_IMD:
            immd_data = self.raw_frame[70:74]
        elif self.roce_bth_opcode == RC_RDMA_WRITE_LAST_IMD:
            immd_data = self.raw_frame[54:58]


    def produce_icrc(roce_frame_no_icrc):
        icrc = b''

        crc_temp = 0xDEBB20E3
        if len(roce_frame_no_icrc) % 4 != 0:
            print("Wrong payload length")

        steps_32 = int(len(roce_frame_no_icrc) / 4)

        for i in range(steps_32):
            value = struct.unpack('<L', roce_frame_no_icrc[(i * 4):(i * 4 + 4)])[0]
            crc_temp = compute_crc(value, 0x04c11db7, crc_temp)

        crc_temp = ~np.uint32(crc_temp)
        icrc += struct.pack('<L', crc_temp)

        return icrc

    def compute_sw_icrc(self):
        ip_frame = self.raw_frame[-(len(self.raw_frame) - 14):]

        icrc_mask = [0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00,
                     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                     0x00, 0xff, 0xff, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00,
                     0x00, 0xff, 0x00]

        roce_frame_temp = b''
        for i in range(len(ip_frame)-4):
            if i < 33:
                value = struct.unpack('>B', ip_frame[i:i + 1])[0]
                value = value | icrc_mask[32 - i]
                roce_frame_temp += struct.pack('>B', value)
            else:
                value = struct.unpack('>B', ip_frame[i:i + 1])[0]
                roce_frame_temp += struct.pack('>B', value)

        crc_temp = 0xDEBB20E3

        if len(roce_frame_temp) % 4 != 0:
            print("Wrong payload length")

        steps_32 = int(len(roce_frame_temp) / 4)

        for i in range(steps_32):
            value = struct.unpack('<L', roce_frame_temp[(i * 4):(i * 4 + 4)])[0]
            crc_temp = compute_crc(value, 0x04c11db7, crc_temp)

        crc_temp = ~np.uint32(crc_temp)

        return crc_temp

    def decode_icrc(self):
        icrc_value = self.raw_frame[-4:]

        self.roce_icrc = struct.unpack('<L', icrc_value)[0]


class IPFrame(object):
    def __init__(self,
                 raw_frame=b'',
                 ip_version=4,
                 ip_ihl=5,
                 ip_dscp=0,
                 ip_ecn=0,
                 ip_length=None,
                 ip_identification=0,
                 ip_flags=2,
                 ip_fragment_offset=0,
                 ip_ttl=64,
                 ip_protocol=0x11,
                 ip_header_checksum=None,
                 ip_source_ip=0xc0a80164,
                 ip_dest_ip=0xc0a80165
                 ):
        self.raw_frame = raw_frame
        self._payload = self.raw_frame[-(len(self.raw_frame) - 20):]
        self.ip_version = ip_version
        self.ip_ihl = ip_ihl
        self.ip_dscp = ip_dscp
        self.ip_ecn = ip_ecn
        self.ip_length = ip_length
        self.ip_identification = ip_identification
        self.ip_flags = ip_flags
        self.ip_fragment_offset = ip_fragment_offset
        self.ip_ttl = ip_ttl
        self.ip_protocol = ip_protocol
        self.ip_header_checksum = ip_header_checksum
        self.ip_source_ip = ip_source_ip
        self.ip_dest_ip = ip_dest_ip

    def decode_ip_header(self):
        ip_header = self.raw_frame[0:20]

        v = struct.unpack('B', ip_header[0:1])[0]
        self.ip_version = (v >> 4) & 0xF
        self.ip_ihl = v & 0xF

        v = struct.unpack('B', ip_header[1:2])[0]
        self.ip_dscp = (v >> 2) & 0x3F
        self.ip_ecn = v & 0x3
        self.ip_length = struct.unpack('>H', ip_header[2:4])[0]
        self.ip_identification = struct.unpack('>H', ip_header[4:6])[0]

        v = struct.unpack('>H', ip_header[6:8])[0]
        self.ip_flags = (v >> 13) & 0x7
        self.ip_fragment_offset = v & 0x1FFF
        self.ip_ttl = struct.unpack('B', ip_header[8:9])[0]
        self.ip_protocol = struct.unpack('B', ip_header[9:10])[0]
        self.ip_header_checksum = struct.unpack('>H', ip_header[10:12])[0]
        self.ip_source_ip = struct.unpack('>L', ip_header[12:16])[0]
        self.ip_dest_ip = struct.unpack('>L', ip_header[16:20])[0]


class UDPFrame(object):
    def __init__(self,
                 raw_frame=b'',
                 udp_source_port=1,
                 udp_dest_port=2,
                 udp_length=None,
                 udp_checksum=None
                 ):
        self.raw_frame = raw_frame,
        self._payload = self.raw_frame[-(len(self.raw_frame) - 8):]
        self.udp_source_port = udp_source_port
        self.udp_dest_port = udp_dest_port
        self.udp_length = udp_length
        self.udp_checksum = udp_checksum

    def decode_udp_header(self):
        udp_header = self.raw_frame[0:8]

        self.udp_source_port = struct.unpack('>H', udp_header[0:2])[0]
        self.udp_dest_port = struct.unpack('>H', udp_header[2:4])[0]
        self.udp_length = struct.unpack('>H', udp_header[4:6])[0]
        self.udp_checksum = struct.unpack('>H', udp_header[6:8])[0]


def produce_ip():
    ip_header = b''

    ip_header += struct.pack('B', 0x45)
    ip_header += struct.pack('B', 0x00)
    ip_header += struct.pack('>H', 124)
    ip_header += struct.pack('>H', 0x0000)
    ip_header += struct.pack('>H', 0x4000)
    ip_header += struct.pack('B', 0x40)
    ip_header += struct.pack('B', 0x11)
    ip_header += struct.pack('>H', 0x7c59)
    ip_header += struct.pack('>L', 0x0b01d40a)
    ip_header += struct.pack('>L', 0x0b01d40b)

    return ip_header


def produce_udp():
    udp_header = b''

    udp_header += struct.pack('>H', 8483)
    udp_header += struct.pack('>H', 4791)
    udp_header += struct.pack('>H', 104)
    udp_header += struct.pack('>H', 0x0b17)

    return udp_header


def produce_bth(op_code, p_key, psn, qpn):
    bth_header = b''

    bth_header += struct.pack('>B', op_code)
    bth_header += struct.pack('>B', 0x00)
    bth_header += struct.pack('>H', p_key)
    bth_header += struct.pack('>B', 0x00)
    bth_header += struct.pack('>L', qpn)[-3:]
    bth_header += struct.pack('>B', 0x00)
    bth_header += struct.pack('>L', psn)[-3:]

    return bth_header


def produce_reth(v_addr, r_key, dma_length):
    reth_header = b''

    reth_header += struct.pack('>Q', v_addr)
    reth_header += struct.pack('>L', r_key)
    reth_header += struct.pack('>L', dma_length)

    return reth_header


def produce_imm_data(data):
    imm_data = b''

    imm_data += struct.pack('>L', data)

    return imm_data


def produce_payload(payload_data):
    payload = b''

    for value in payload_data:
        payload += struct.pack('>L', value)

    return payload


def produce_icrc(roce_frame_no_icrc):
    icrc = b''

    crc_temp = 0xDEBB20E3
    if len(roce_frame_no_icrc) % 4 != 0:
        print("Wrong payload length")

    steps_32 = int(len(roce_frame_no_icrc) / 4)

    for i in range(steps_32):
        value = struct.unpack('<L', roce_frame_no_icrc[(i * 4):(i * 4 + 4)])[0]
        crc_temp = compute_crc(value, 0x04c11db7, crc_temp)

    crc_temp = ~np.uint32(crc_temp)
    icrc += struct.pack('<L', crc_temp)

    return icrc


def mask_icrc_fields(roce_frame):
    icrc_mask = [0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00,
                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                 0x00, 0xff, 0xff, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00,
                 0x00, 0xff, 0x00]

    roce_frame_temp = b''
    for i in range(len(roce_frame)):
        if i < 33:
            value = struct.unpack('>B', roce_frame[i:i + 1])[0]
            value = value | icrc_mask[32 - i]
            roce_frame_temp += struct.pack('>B', value)
        else:
            value = struct.unpack('>B', roce_frame[i:i + 1])[0]
            roce_frame_temp += struct.pack('>B', value)

    return roce_frame_temp


def get_frame(bth, reth, imm_data, payload):
    roce_frame = b''

    roce_frame += produce_ip()
    roce_frame += produce_udp()

    roce_frame += bth
    bth_op_code = struct.unpack('>B', bth[0:1])[0]
    if bth_op_code == RC_RDMA_WRITE_FIRST or bth_op_code == RC_RDMA_WRITE_ONLY or bth_op_code == RC_RDMA_WRITE_ONLY_IMD:
        roce_frame += reth
    if bth_op_code == RC_RDMA_WRITE_ONLY_IMD or bth_op_code == RC_RDMA_WRITE_LAST_IMD:
        roce_frame += imm_data
    roce_frame += payload
    roce_frame_masked = mask_icrc_fields(roce_frame)
    icrc = produce_icrc(roce_frame_masked)
    roce_frame += icrc
    icrc_number = struct.unpack('>L', icrc[0:4])[0]
    print(hex(~np.uint32(icrc_number)))

    return roce_frame


RC_RDMA_WRITE_FIRST = 0x06
RC_RDMA_WRITE_MIDDLE = 0x07
RC_RDMA_WRITE_LAST = 0x08
RC_RDMA_WRITE_LAST_IMD = 0x09
RC_RDMA_WRITE_ONLY = 0x0a
RC_RDMA_WRITE_ONLY_IMD = 0x0b
RC_RDMA_ACK = 0x11

op_code = RC_RDMA_WRITE_ONLY
p_key = 0xFFFF
psn = 136
dest_qp = 0x10
ack_req = 0x0
v_addr = 0x0
r_key = 4143972420
dma_length = 64

#bth  = produce_bth(op_code, p_key, psn, dest_qp)
#reth = produce_reth(v_addr, r_key, dma_length)

#payload_data = b''

#for i in range(int(dma_length/8)):
#    value_data = np.uint32(i*8)
#    value_data_rev = np.uint32(~value_data)
#    payload_data += struct.pack('<L', value_data)
#    payload_data += struct.pack('<L', value_data_rev)

#roce_frame = get_frame(bth, reth, None, payload_data)


#for value in roce_frame:
#    print(hex(value))


#HW_ICRC = 0xb8c4707a

Exp_psn = 0
Measured_data_legth = 0
Sim_data_legth = 0

ETH_P_ALL = 3  # not defined in socket module, sadly...
s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
s.bind(("tap0", 0))
while True:
    data = s.recv(4096)
    Eth_frame_data = EthFrame(raw_frame=data)
    Eth_frame_data.decode_eth_header()
    #print(Eth_frame_data._payload)
    if Eth_frame_data.eth_type == 0x0800:
        Eth_frame_data.decode_ip_header()
        if Eth_frame_data.ip_protocol == 0x11:
            Eth_frame_data.decode_udp_header()
            if Eth_frame_data.udp_dest_port == 4791:
                Eth_frame_data.decode_BTH()
                Eth_frame_data.decode_icrc()
                if Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_FIRST or Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_ONLY or Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_ONLY_IMD:
                    Exp_psn = Eth_frame_data.roce_bth_psn
                else:
                    Exp_psn = Exp_psn + 1
                if Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_FIRST or Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_ONLY or Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_ONLY_IMD:
                    Eth_frame_data.decode_RETH()
                    Sim_data_legth = Eth_frame_data.roce_reth_dma_length
                if Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_FIRST or Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_ONLY:
                    Measured_data_legth = Eth_frame_data.frame_length - 14 - 20 - 8 - 12 - 16 - 4
                elif Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_ONLY_IMD:
                    Measured_data_legth = Eth_frame_data.frame_length - 14 - 20 - 8 - 12 - 16 - 4 - 4
                elif Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_MIDDLE or Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_LAST:
                    Measured_data_legth = Measured_data_legth + Eth_frame_data.frame_length - 14 - 20 - 8 - 12 - 4
                elif Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_LAST_IMD:
                    Measured_data_legth = Measured_data_legth + Eth_frame_data.frame_length - 14 - 20 - 8 - 12 - 4 - 4
                print('------------------------START OF PACKET---------------------')
                print('OP CODE = ', OP_codes[Eth_frame_data.roce_bth_opcode])
                print('QUEUE PAIR NUMBER = ', Eth_frame_data.roce_bth_dest_qp)
                print('Recieved PSN = ', Eth_frame_data.roce_bth_psn)
                print('Expected PSN = ', Exp_psn)

                print('Remote key= ', hex(Eth_frame_data.roce_reth_rkey))
                print('SIM ICRC = ', hex(Eth_frame_data.roce_icrc))
                SW_icrc = Eth_frame_data.compute_sw_icrc()
                print('SW ICRC  = ', hex(SW_icrc))
                if Exp_psn != Eth_frame_data.roce_bth_psn:
                    print('Wrong PSN!')
                if SW_icrc != Eth_frame_data.roce_icrc:
                    print('Software ICRC does not match recieved one!')
                else:
                    print('Good ICRC!')
                print('RETH DMA length= ', Sim_data_legth)
                print('Measured length= ', Measured_data_legth)
                if Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_LAST or Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_LAST_IMD or Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_ONLY or Eth_frame_data.roce_bth_opcode == RC_RDMA_WRITE_ONLY_IMD:
                    if Sim_data_legth != Measured_data_legth:
                        print('DMA Length does not match!')
                print('------------------------END OF PACKET-----------------------')
