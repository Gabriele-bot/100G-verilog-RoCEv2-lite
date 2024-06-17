import struct
import numpy as np
import sys
import socket


from ipaddress import ip_address, IPv4Address


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
        self.payload = payload
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

    def decode_eth_frame(self):
        ethernet_frame = self.raw_frame[0:14]

        self.eth_dest_mac = struct.unpack('>Q', b'\x00\x00' + ethernet_frame[0:6])[0]
        self.eth_src_mac = struct.unpack('>Q', b'\x00\x00' + ethernet_frame[6:12])[0]
        self.eth_type = struct.unpack('>H', ethernet_frame[12:14])[0]

        self.payload = self.raw_frame[-(len(self.raw_frame) - 14):]
        #if self.eth_type == 0x0800:
        #    self.ip_raw_frame = self._payload


class IPFrame(object):

    def __init__(self,
                 raw_frame=b'',
                 payload=b'',
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
                 ip_source_ip=0x0b01d40b,
                 ip_dest_ip=0x0b01d40a
                 ):
        self.raw_frame = raw_frame
        self.payload = payload
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

    def decode_ip_frame(self):
        #ip_header = self.raw_frame[14:34]
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

        self.payload = self.raw_frame[-(len(self.raw_frame) - 20):]


class UDPFrame(object):
    def __init__(self,
                 raw_frame=b'',
                 payload=b'',
                 udp_source_port=1,
                 udp_dest_port=2,
                 udp_length=None,
                 udp_checksum=None
                 ):
        self.raw_frame = raw_frame
        self.payload = payload
        self.udp_source_port = udp_source_port
        self.udp_dest_port = udp_dest_port
        self.udp_length = udp_length
        self.udp_checksum = udp_checksum

    def decode_udp_frame(self):
        # udp_header = self.raw_frame[34:42]
        udp_header = self.raw_frame[0:8]

        self.udp_source_port = struct.unpack('>H', udp_header[0:2])[0]
        self.udp_dest_port = struct.unpack('>H', udp_header[2:4])[0]
        self.udp_length = struct.unpack('>H', udp_header[4:6])[0]
        self.udp_checksum = struct.unpack('>H', udp_header[6:8])[0]

        self.payload = self.raw_frame[-(len(self.raw_frame) - 8):]


class RoCEFrame(object):

    def __init__(self,
                 raw_ip_frame=b'',
                 raw_frame=b'',
                 payload=b'',
                 roce_bth_opcode=0xA,
                 roce_bth_pkey=0,
                 roce_bth_dest_qp=0,
                 roce_bth_ack_req=1,
                 roce_bth_psn=0,
                 roce_reth_vaddr=0,
                 roce_reth_rkey=0,
                 roce_reth_dma_length=0,
                 roce_immdata=0xDEADBEEF
                 ):
        self.RC_RDMA_WRITE_FIRST = 0x06
        self.RC_RDMA_WRITE_MIDDLE = 0x07
        self.RC_RDMA_WRITE_LAST = 0x08
        self.RC_RDMA_WRITE_LAST_IMD = 0x09
        self.RC_RDMA_WRITE_ONLY = 0x0a
        self.RC_RDMA_WRITE_ONLY_IMD = 0x0b
        self.RC_RDMA_ACK = 0x11

        self.OP_codes = {
            0x06: 'RC_RDMA_WRITE_FIRST',
            0x07: 'RC_RDMA_WRITE_MIDDLE',
            0x08: 'RC_RDMA_WRITE_LAST',
            0x09: 'RC_RDMA_WRITE_LAST_IMD',
            0x0a: 'RC_RDMA_WRITE_ONLY',
            0x0b: 'RC_RDMA_WRITE_ONLY_IMD',
            0x11: 'RC_RDMA_ACK'
        }

        self.mask_fields4icrc = [0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0x00, 0xff, 0xff, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0x00, 0xff, 0x00]
        self.raw_ip_frame = raw_ip_frame
        self.raw_frame = raw_frame
        self.payload = payload
        self.roce_bth_opcode = roce_bth_opcode
        self.roce_bth_pkey = roce_bth_pkey
        self.roce_bth_dest_qp = roce_bth_dest_qp
        self.roce_bth_ack_req = roce_bth_ack_req
        self.roce_bth_psn = roce_bth_psn
        self.roce_reth_vaddr = roce_reth_vaddr
        self.roce_reth_rkey = roce_reth_rkey
        self.roce_reth_dma_length = roce_reth_dma_length
        self.roce_immdata = roce_immdata
        self.frame_length = len(raw_frame)

    def decode_BTH(self):
        #BTH = self.raw_frame[42:54]
        BTH = self.raw_frame[0:12]

        self.roce_bth_opcode = struct.unpack('>B', BTH[0:1])[0]
        #reserved = struct.unpack('>B', BTH[1:2])[0]
        self.roce_bth_pkey = struct.unpack('>H', BTH[2:4])[0]
        # reserved = struct.unpack('>B', BTH[4:5])[0]
        self.roce_bth_dest_qp = struct.unpack('>L', b'\x00' + BTH[5:8])[0]
        self.roce_bth_ack_req = struct.unpack('>B', BTH[8:9])[0]
        self.roce_bth_psn = struct.unpack('>L', b'\x00' + BTH[9:12])[0]

    def decode_RETH(self):
        #RETH = self.raw_frame[54:70]
        RETH = self.raw_frame[12:28]

        self.roce_reth_vaddr = struct.unpack('>Q', RETH[0:8])[0]
        self.roce_reth_rkey = struct.unpack('>L', RETH[8:12])[0]
        self.roce_reth_dma_length = struct.unpack('>L', RETH[12:16])[0]

    def decode_immd_data(self):
        if self.roce_bth_opcode == self.RC_RDMA_WRITE_ONLY_IMD:
            #immd_data = self.raw_frame[70:74]
            immd_data = self.raw_frame[28:32]
        elif self.roce_bth_opcode == self.RC_RDMA_WRITE_LAST_IMD:
            #immd_data = self.raw_frame[54:58]
            immd_data = self.raw_frame[12:16]
        self.roce_immdata = struct.unpack('>H', immd_data[0:4])[0]

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
        ip_frame = self.raw_ip_frame

        roce_frame_temp = b''
        for i in range(len(ip_frame) - 4):
            if i < 33:
                value = struct.unpack('>B', ip_frame[i:i + 1])[0]
                value = value | self.mask_fields4icrc[32 - i]
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

class RoCEStream(object):

    def __init__(self, data_stream):
        self.data_stream = data_stream
        self.exp_psn = 0
        self.measured_data_legth = 0
        self.sim_data_legth = 0
        self.received_r_key = 0

    def decode_Roce_stream(self, DEBUG_OUT = False):
        icrc_errors  = 0
        psn_errors   = 0
        length_error = False
        for data in self.data_stream:
            Eth_frame_data = EthFrame(raw_frame=data)
            Eth_frame_data.decode_eth_frame()
            if Eth_frame_data.eth_type == 0x0800:
                if DEBUG_OUT:
                    print('IP packet recieved!')
                IP_frame_data = IPFrame(raw_frame=Eth_frame_data.payload)
                IP_frame_data.decode_ip_frame()
                if DEBUG_OUT:
                    print('Source IP : ', IPv4Address(IP_frame_data.ip_source_ip))
                    print('Dest IP   : ', IPv4Address(IP_frame_data.ip_dest_ip))
                if IP_frame_data.ip_protocol == 0x11:
                    if DEBUG_OUT:
                        print('UDP packet recieved!')
                    UDP_frame_data = UDPFrame(raw_frame=IP_frame_data.payload)
                    UDP_frame_data.decode_udp_frame()
                    if DEBUG_OUT:
                        print('Source PORT : ', UDP_frame_data.udp_source_port)
                        print('Dest PORT   : ', UDP_frame_data.udp_dest_port)
                    if UDP_frame_data.udp_dest_port == 4791:
                        RoCE_frame_data = RoCEFrame(raw_ip_frame=IP_frame_data.raw_frame, raw_frame=UDP_frame_data.payload)
                        RoCE_frame_data.decode_BTH()
                        RoCE_frame_data.decode_icrc()
                        if RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_FIRST or RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_ONLY or RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_ONLY_IMD:
                            self.exp_psn = RoCE_frame_data.roce_bth_psn
                        else:
                            self.exp_psn = self.exp_psn + 1
                        if RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_FIRST or RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_ONLY or RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_ONLY_IMD:
                            RoCE_frame_data.decode_RETH()
                            self.sim_data_legth = RoCE_frame_data.roce_reth_dma_length
                        if RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_FIRST or RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_ONLY:
                            self.measured_data_legth = RoCE_frame_data.frame_length - 12 - 16 - 4
                        elif RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_ONLY_IMD:
                            self.measured_data_legth = RoCE_frame_data.frame_length - 12 - 16 - 4 - 4
                        elif RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_MIDDLE or RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_LAST:
                            self.measured_data_legth = self.measured_data_legth + RoCE_frame_data.frame_length - 12 - 4
                        elif RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_LAST_IMD:
                            self.measured_data_legth = self.measured_data_legth + RoCE_frame_data.frame_length - 12 - 4 - 4
                        self.received_r_key = RoCE_frame_data.roce_reth_rkey
                        SW_icrc = RoCE_frame_data.compute_sw_icrc()
                        if DEBUG_OUT:
                            print('RoCE packet recieved!')
                            print('OP CODE = ', RoCE_frame_data.OP_codes[RoCE_frame_data.roce_bth_opcode])
                            print('QUEUE PAIR NUMBER = ', RoCE_frame_data.roce_bth_dest_qp)
                            print('Recieved PSN = ', RoCE_frame_data.roce_bth_psn)
                            print('Expected PSN = ', self.exp_psn)
                            if self.exp_psn != RoCE_frame_data.roce_bth_psn:
                                print('Wrong PSN!')
                            print('SIM ICRC = ', hex(RoCE_frame_data.roce_icrc))
                            print('SW ICRC  = ', hex(SW_icrc))
                            if SW_icrc != RoCE_frame_data.roce_icrc:
                                print('Software ICRC does not match recieved one!')
                            else:
                                print('Good ICRC!')
                            print('Measured length= ', self.measured_data_legth)
                            if RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_LAST or Eth_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_LAST_IMD or RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_ONLY or RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_ONLY_IMD:
                                if self.sim_data_legth != self.measured_data_legth:
                                    print('DMA Length does not match!')
                                print('RETH DMA length= ', self.sim_data_legth)
                                print('Measured length= ', self.measured_data_legth)
                                print('Remote key= ', hex(self.received_r_key))
                        if self.exp_psn != RoCE_frame_data.roce_bth_psn:
                            psn_errors += 1
                        if SW_icrc != RoCE_frame_data.roce_icrc:
                            icrc_errors += 1
                        if RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_LAST or Eth_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_LAST_IMD or RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_ONLY or RoCE_frame_data.roce_bth_opcode == RoCE_frame_data.RC_RDMA_WRITE_ONLY_IMD:
                            if self.sim_data_legth != self.measured_data_legth:
                                length_error = True

        return icrc_errors, psn_errors, length_error


Exp_psn = 0
Measured_data_legth = 0
Sim_data_legth = 0
Received_r_key = 0

data_stream = []


ETH_P_ALL = 3  # not defined in socket module, sadly...
s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
s.bind(("tap0", 0))
try:
    while True:
        data = s.recv(4096)
        data_stream.append(data)
        #print('------------------------START OF PACKET---------------------')

        #print('------------------------END OF PACKET-----------------------')
except KeyboardInterrupt:
    print('Exiting!')

RoCE_stream_recieved = RoCEStream(data_stream)
icrc_errors, psn_errors, length_error = RoCE_stream_recieved.decode_Roce_stream(True)
if icrc_errors == 0  and  psn_errors == 0 and length_error is False:
    print('No errors observed!')
else:
    print('Errors observed!')

