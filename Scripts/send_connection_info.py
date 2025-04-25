import socket
import struct
from ipaddress import ip_address, IPv4Address

import argparse

parser = argparse.ArgumentParser(description='Send QP information via UDP')
parser.add_argument('-ir', '--rem_ip_addr', metavar='N', type=str, default="22.1.212.11",
                    help='Client IP address (PC)')
parser.add_argument('-il', '--loc_ip_addr', metavar='N', type=str, default="22.1.212.10",
                    help='FPGA IP address')
parser.add_argument('-rr', '--rem_rkey', metavar='N', type=int, default=0x234,
                    help='Remote key')
parser.add_argument('-lr', '--loc_rkey', metavar='N', type=int, default=0x234,
                    help='Local key')
parser.add_argument('-ra', '--rem_base_addr', metavar='N', type=int, default=0x12341242,
                    help='Remote base address')
parser.add_argument('-la', '--loc_base_addr', metavar='N', type=int, default=0x12341242,
                    help='Local base address')
parser.add_argument('-rq', '--rem_qpn', metavar='N', type=int, default=0x11,
                    help='Remote queue pair number')
parser.add_argument('-lq', '--loc_qpn', metavar='N', type=int, default=0x12,
                    help='Local queue pair number')
parser.add_argument('-rp', '--rem_psn', metavar='N', type=int, default=0x0,
                    help='Remote Start Packet Sequence Number')
parser.add_argument('-lp', '--loc_psn', metavar='N', type=int, default=0x0,
                    help='Local Start Packet Sequence Number')
#TX meta for debug
parser.add_argument('-l', '--length', metavar='N', type=int, default=128,
                    help='DMA transfer size in byte')
parser.add_argument('-o', '--addrOffset', metavar='N', type=int, default=0x0,
                    help='Address offset')
parser.add_argument('-i', '--immediate', action='store_true',
                    help='Immediate transfer')
parser.add_argument('-t', '--txtype', action='store_false',

                    help='Default transmit type is WRITE, set to transmit SEND instead')
parser.add_argument('-s', '--start', action='store_true',
                    help='Start transfer')
parser.add_argument('-r', '--request', metavar='N', type=int, default=0x0,
                    help='''
Request type:
REQ_NULL          = 0x0
REQ_OPEN_QP       = 0x1
REQ_SEND_QP_INFO  = 0x2
REQ_MODIFY_QP_RTS = 0x3
REQ_CLOSE_QP      = 0x4
REQ_ERROR         = 0x7
                    ''')

args = parser.parse_args()

UDP_PORT = 0x4321

#REQUESTS types
REQ_NULL          = 0x0
REQ_OPEN_QP       = 0x1
REQ_SEND_QP_INFO  = 0x2
REQ_MODIFY_QP_RTS = 0x3
REQ_CLOSE_QP      = 0x4
REQ_ERROR         = 0x7


def request_qp_info(rem_ip_addr="22.1.212.10", loc_ip_addr="22.1.212.11",loc_qpn=0x100, loc_psn=0x0, loc_r_key=0x1234, loc_base_addr=0x12345678):

    LOC_IP_ADDRESS = loc_ip_addr
    LOC_IP_ADDRESS_INT = int(ip_address(loc_ip_addr))
    LOC_R_KEY = loc_r_key
    LOC_QPN = loc_qpn
    LOC_PSN = loc_psn
    LOC_BASE_ADDR = loc_base_addr

    REM_IP_ADDRESS = rem_ip_addr
    REM_IP_ADDRESS_INT = int(ip_address(rem_ip_addr))
    REM_R_KEY = 0x0
    REM_QPN = 0x0
    REM_PSN = 0x0
    REM_BASE_ADDR = 0x0

    REQ_TYPE = REQ_OPEN_QP

    qpinfo_flags = 0x1 | (REQ_TYPE << 1) #open qp request

    MESSAGE = b''
    # QP infos, only local parameters are filled
    MESSAGE += struct.pack("<B", qpinfo_flags)  # QP_info_valid and open qp request
    # LOCAL QP INFO
    MESSAGE += struct.pack('<L', LOC_QPN)  # local queue pair number
    MESSAGE += struct.pack('<L', LOC_PSN)  # local start psn
    MESSAGE += struct.pack('<L', LOC_R_KEY)  # local r_key
    MESSAGE += struct.pack('<Q', LOC_BASE_ADDR)  # local base address
    MESSAGE += struct.pack('<L', LOC_IP_ADDRESS_INT)  # local IP address
    # REMOTE QP INFO
    MESSAGE += struct.pack('<L', REM_QPN)  # remote queue pair number
    MESSAGE += struct.pack('<L', REM_PSN)  # remote start psn
    MESSAGE += struct.pack('<L', REM_R_KEY)  # remote key
    MESSAGE += struct.pack('<Q', REM_BASE_ADDR)  # remote base address
    MESSAGE += struct.pack('<L', REM_IP_ADDRESS_INT)  # remote IP address
    # TX META values
    MESSAGE += struct.pack("<B", 0x0)  # No transimt values
    MESSAGE += struct.pack("<Q", 0x0)  # TXmeta_rem_addr
    MESSAGE += struct.pack("<L", 0x0)  # DMA length
    MESSAGE += struct.pack("<H", 0x0)  # UDP_PORT

    print("UDP target IP:", REM_IP_ADDRESS)
    print("UDP target port:", UDP_PORT)
    print("message:", MESSAGE)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # UDP
    sock.sendto(MESSAGE, (REM_IP_ADDRESS, UDP_PORT))

    rcv_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # UDP
    rcv_sock.bind((LOC_IP_ADDRESS, 0x4321))
    while True:
        data, addr = rcv_sock.recvfrom(1024)  # buffer size is 1024 bytes
        print("received message: %s" % data)
        break

    return data

def send_qp_info(rem_ip_addr="22.1.212.10", rem_qpn=0x100, rem_psn=0x0, rem_r_key=0x1234, rem_base_addr=0x12345678, loc_ip_addr="22.1.212.11",loc_qpn=0x100, loc_psn=0x0, loc_r_key=0x1234, loc_base_addr=0x12345678):
    LOC_IP_ADDRESS = loc_ip_addr
    LOC_IP_ADDRESS_INT = int(ip_address(loc_ip_addr))
    LOC_R_KEY = loc_r_key
    LOC_QPN = loc_qpn
    LOC_PSN = loc_psn
    LOC_BASE_ADDR = loc_base_addr

    REM_IP_ADDRESS = rem_ip_addr
    REM_IP_ADDRESS_INT = int(ip_address(rem_ip_addr))
    REM_R_KEY = rem_r_key
    REM_QPN = rem_qpn
    REM_PSN = rem_psn
    REM_BASE_ADDR = rem_base_addr

    REQ_TYPE = REQ_SEND_QP_INFO

    qpinfo_flags = 0x1 | (REQ_TYPE << 1)

    MESSAGE = b''

    # QP infos, only local parameters are filled
    MESSAGE += struct.pack("<B", qpinfo_flags)  # QP_info_valid and open qp request
    # LOCAL QP INFO
    MESSAGE += struct.pack('<L', LOC_QPN)  # local queue pair number
    MESSAGE += struct.pack('<L', LOC_PSN)  # local start psn
    MESSAGE += struct.pack('<L', LOC_R_KEY)  # local r_key
    MESSAGE += struct.pack('<Q', LOC_BASE_ADDR)  # local base address
    MESSAGE += struct.pack('<L', LOC_IP_ADDRESS_INT)  # local IP address
    # REMOTE QP INFO
    MESSAGE += struct.pack('<L', REM_QPN)  # remote queue pair number
    MESSAGE += struct.pack('<L', REM_PSN)  # remote start psn
    MESSAGE += struct.pack('<L', REM_R_KEY)  # remote key
    MESSAGE += struct.pack('<Q', REM_BASE_ADDR)  # remote base address
    MESSAGE += struct.pack('<L', REM_IP_ADDRESS_INT)  # remote IP address
    # TX META values
    MESSAGE += struct.pack("<B", 0x0)  # No transimt values
    MESSAGE += struct.pack("<Q", 0x0)  # TXmeta_rem_addr
    MESSAGE += struct.pack("<L", 0x0)  # DMA length
    MESSAGE += struct.pack("<H", 0x0)  # UDP_PORT

    print("UDP target IP:", REM_IP_ADDRESS)
    print("UDP target port:", UDP_PORT)
    print("message:", MESSAGE)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # UDP
    sock.sendto(MESSAGE, (REM_IP_ADDRESS, UDP_PORT))

def modify_qp_rts(rem_ip_addr="22.1.212.10", rem_qpn=0x100, rem_psn=0x0, rem_r_key=0x1234, rem_base_addr=0x12345678, loc_ip_addr="22.1.212.11",loc_qpn=0x100, loc_psn=0x0, loc_r_key=0x1234, loc_base_addr=0x12345678):
    LOC_IP_ADDRESS = loc_ip_addr
    LOC_IP_ADDRESS_INT = int(ip_address(loc_ip_addr))
    LOC_R_KEY = loc_r_key
    LOC_QPN = loc_qpn
    LOC_PSN = loc_psn
    LOC_BASE_ADDR = loc_base_addr

    REM_IP_ADDRESS = rem_ip_addr
    REM_IP_ADDRESS_INT = int(ip_address(rem_ip_addr))
    REM_R_KEY = rem_r_key
    REM_QPN = rem_qpn
    REM_PSN = rem_psn
    REM_BASE_ADDR = rem_base_addr

    REQ_TYPE = REQ_MODIFY_QP_RTS

    qpinfo_flags = 0x1 | (REQ_TYPE << 1)

    MESSAGE = b''

    # QP infos, only local parameters are filled
    MESSAGE += struct.pack("<B", qpinfo_flags)  # QP_info_valid and open qp request
    # LOCAL QP INFO
    MESSAGE += struct.pack('<L', LOC_QPN)  # local queue pair number
    MESSAGE += struct.pack('<L', LOC_PSN)  # local start psn
    MESSAGE += struct.pack('<L', LOC_R_KEY)  # local key
    MESSAGE += struct.pack('<Q', LOC_BASE_ADDR)  # local base address
    MESSAGE += struct.pack('<L', LOC_IP_ADDRESS_INT)  # local IP address
    # REMOTE QP INFO
    MESSAGE += struct.pack('<L', REM_QPN)  # remote queue pair number
    MESSAGE += struct.pack('<L', REM_PSN)  # remote start psn
    MESSAGE += struct.pack('<L', REM_R_KEY)  # remote key
    MESSAGE += struct.pack('<Q', REM_BASE_ADDR)  # remote base address
    MESSAGE += struct.pack('<L', REM_IP_ADDRESS_INT)  # remote IP address
    # TX META values
    MESSAGE += struct.pack("<B", 0x0)  # No transimt values
    MESSAGE += struct.pack("<Q", 0x0)  # TXmeta_rem_addr
    MESSAGE += struct.pack("<L", 0x0)  # DMA length
    MESSAGE += struct.pack("<H", 0x0)  # UDP_PORT

    print("UDP target IP:", REM_IP_ADDRESS)
    print("UDP target port:", UDP_PORT)
    print("message:", MESSAGE)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # UDP
    sock.sendto(MESSAGE, (REM_IP_ADDRESS, UDP_PORT))

    rcv_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # UDP
    rcv_sock.bind((LOC_IP_ADDRESS, 0x4321))
    while True:
        data, addr = rcv_sock.recvfrom(1024)  # buffer size is 1024 bytes
        print("received message: %s" % data)
        break

    return data

def close_rem_qp(rem_ip_addr="22.1.212.10", rem_qpn=0x100, rem_psn=0x0, rem_r_key=0x1234, rem_base_addr=0x12345678, loc_ip_addr="22.1.212.11",loc_qpn=0x100, loc_psn=0x0, loc_r_key=0x1234, loc_base_addr=0x12345678):
    LOC_IP_ADDRESS = loc_ip_addr
    LOC_IP_ADDRESS_INT = int(ip_address(loc_ip_addr))
    LOC_R_KEY = loc_r_key
    LOC_QPN = loc_qpn
    LOC_PSN = loc_psn
    LOC_BASE_ADDR = loc_base_addr

    REM_IP_ADDRESS = rem_ip_addr
    REM_IP_ADDRESS_INT = int(ip_address(rem_ip_addr))
    REM_R_KEY = rem_r_key
    REM_QPN = rem_qpn
    REM_PSN = rem_psn
    REM_BASE_ADDR = rem_base_addr

    REQ_TYPE = REQ_CLOSE_QP

    qpinfo_flags = 0x1 | (REQ_TYPE << 1)

    MESSAGE = b''

    # QP infos, only local parameters are filled
    MESSAGE += struct.pack("<B", qpinfo_flags)  # QP_info_valid and open qp request
    # LOCAL QP INFO
    MESSAGE += struct.pack('<L', LOC_QPN)  # local queue pair number
    MESSAGE += struct.pack('<L', LOC_PSN)  # local start psn
    MESSAGE += struct.pack('<L', LOC_R_KEY)  # local key
    MESSAGE += struct.pack('<Q', LOC_BASE_ADDR)  # local base address
    MESSAGE += struct.pack('<L', LOC_IP_ADDRESS_INT)  # local IP address
    # REMOTE QP INFO
    MESSAGE += struct.pack('<L', REM_QPN)  # remote queue pair number
    MESSAGE += struct.pack('<L', REM_PSN)  # remote start psn
    MESSAGE += struct.pack('<L', REM_R_KEY)  # remote key
    MESSAGE += struct.pack('<Q', REM_BASE_ADDR)  # remote base address
    MESSAGE += struct.pack('<L', REM_IP_ADDRESS_INT)  # remote IP address
    # TX META values
    MESSAGE += struct.pack("<B", 0x0)  # No transimt values
    MESSAGE += struct.pack("<Q", 0x0)  # TXmeta_rem_addr
    MESSAGE += struct.pack("<L", 0x0)  # DMA length
    MESSAGE += struct.pack("<H", 0x0)  # UDP_PORT

    print("UDP target IP:", REM_IP_ADDRESS)
    print("UDP target port:", UDP_PORT)
    print("message:", MESSAGE)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # UDP
    sock.sendto(MESSAGE, (REM_IP_ADDRESS, UDP_PORT))

    rcv_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # UDP
    rcv_sock.bind((LOC_IP_ADDRESS, 0x4321))
    while True:
        data, addr = rcv_sock.recvfrom(1024)  # buffer size is 1024 bytes
        print("received message: %s" % data)
        break

    return data

def send_txmeta(rem_ip_addr="22.1.212.11", loc_ip_addr="22.1.212.10", rem_qpn=0x11, loc_qpn=0x12,
                addr_offset=0x0, rdma_length=0x0, start_flag=0, immd_flag=0, txtype_flag=1):

    LOC_IP_ADDRESS = loc_ip_addr
    LOC_IP_ADDRESS_INT = int(ip_address(loc_ip_addr))
    LOC_R_KEY = 0x0
    LOC_QPN = loc_qpn
    LOC_PSN = 0x0
    LOC_BASE_ADDR = 0x0

    REM_IP_ADDRESS = rem_ip_addr
    REM_IP_ADDRESS_INT = int(ip_address(rem_ip_addr))
    REM_R_KEY = 0x0
    REM_QPN = rem_qpn
    REM_PSN = 0x0
    REM_BASE_ADDR = 0x0

    # Tx meta
    ADDR_OFFSET = addr_offset
    DMA_LENGTH = rdma_length

    REQ_TYPE = REQ_NULL

    qpinfo_flags = 0x0 | (REQ_TYPE << 1)

    txmeta_flags = 0x1 | (start_flag << 1) | (immd_flag << 2) | (txtype_flag << 3)
    print(txtype_flag)

    MESSAGE = b''

    MESSAGE += struct.pack("<B", qpinfo_flags)  # QP_info_valid
    # LOCAL QP INFO
    MESSAGE += struct.pack('<L', LOC_QPN)  # local queue pair number
    MESSAGE += struct.pack('<L', LOC_PSN)  # local start psn
    MESSAGE += struct.pack('<L', LOC_R_KEY)  # local key
    MESSAGE += struct.pack('<Q', LOC_BASE_ADDR)  # local base address
    MESSAGE += struct.pack('<L', LOC_IP_ADDRESS_INT)  # local IP address
    # REMOTE QP INFO
    MESSAGE += struct.pack('<L', REM_QPN)  # remote queue pair number
    MESSAGE += struct.pack('<L', REM_PSN)  # remote start psn
    MESSAGE += struct.pack('<L', REM_R_KEY)  # remote key
    MESSAGE += struct.pack('<Q', REM_BASE_ADDR)  # remote base address
    MESSAGE += struct.pack('<L', REM_IP_ADDRESS_INT)  # remote IP address
    #TX META values
    MESSAGE += struct.pack("<B", txmeta_flags)  # TX meta flags: valid, start, is_immd, txtype
    MESSAGE += struct.pack("<Q", ADDR_OFFSET)  # TXmeta_addr_offset
    MESSAGE += struct.pack("<L", DMA_LENGTH)  # DMA length
    MESSAGE += struct.pack("<H", 0x3412)  # UDP_PORT

    print("UDP target IP:", REM_IP_ADDRESS)
    print("UDP target port:", UDP_PORT)
    print("message:", MESSAGE)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # UDP
    sock.sendto(MESSAGE, (REM_IP_ADDRESS, UDP_PORT))


def decode_udp_packet(pkt):
    payload = pkt[0:64]
    REQ_codes = {
        0x00: 'REQ_NULL',
        0x01: 'REQ_OPEN_QP',
        0x02: 'REQ_SEND_QP_INFO',
        0x03: 'REQ_MODIFY_QP_RTS',
        0x04: 'REQ_CLOSE_QP',
        0x07: 'REQ_ERROR'
    }

    qpinfo_flags = struct.unpack('<B', payload[0:1])[0]
    LOC_QPN = struct.unpack('<L', payload[1:5])[0]
    LOC_PSN = struct.unpack('<L', payload[5:9])[0]
    LOC_R_KEY = struct.unpack('<L', payload[9:13])[0]
    LOC_BASE_ADDR = struct.unpack('<Q', payload[13:21])[0]
    LOC_IP_ADDRESS_INT = struct.unpack('<L', payload[21:25])[0]

    REM_QPN = struct.unpack('<L', payload[25:29])[0]
    REM_PSN = struct.unpack('<L', payload[29:33])[0]
    REM_R_KEY = struct.unpack('<L', payload[33:37])[0]
    REM_BASE_ADDR = struct.unpack('<Q', payload[37:45])[0]
    REM_IP_ADDRESS_INT = struct.unpack('<L', payload[45:49])[0]

    req_code = qpinfo_flags>>1

    if req_code != REQ_ERROR:
        print('OPERATION COMPLETED SUCCESSFULLY!')
    else:
        print('ERROR OBSERVED!')

    print('CODE REQUEST:', REQ_codes[req_code])


    print("LOC_QPN:", hex(LOC_QPN))
    print("LOC_PSN:", hex(LOC_PSN))
    print("LOC_R_KEY:", hex(LOC_R_KEY))
    print("LOC_BASE_ADDR:", hex(LOC_BASE_ADDR))
    print("LOC_IP_ADDRESS:", IPv4Address(LOC_IP_ADDRESS_INT))

    print("REM_QPN:", hex(REM_QPN))
    print("REM_PSN:", hex(REM_PSN))
    print("REM_R_KEY:", hex(REM_R_KEY))
    print("REM_BASE_ADDR:", hex(REM_BASE_ADDR))
    print("REM_IP_ADDRESS:", IPv4Address(REM_IP_ADDRESS_INT))


if __name__ == "__main__":

    if args.start:
        send_txmeta(loc_ip_addr=args.loc_ip_addr, rem_ip_addr=args.rem_ip_addr, rem_qpn=args.rem_qpn,
                    addr_offset=args.addrOffset, rdma_length=args.length, start_flag=args.start,
                    immd_flag=args.immediate, txtype_flag=args.txtype)
    else:
        if args.request == REQ_OPEN_QP:
            data = request_qp_info(loc_ip_addr=args.loc_ip_addr, rem_ip_addr=args.rem_ip_addr, loc_qpn=args.loc_qpn, loc_psn=args.loc_psn, loc_r_key=args.loc_rkey, loc_base_addr=args.loc_base_addr)

            decode_udp_packet(data)

        elif args.request == REQ_CLOSE_QP:
            data = close_rem_qp(loc_ip_addr=args.loc_ip_addr, rem_ip_addr=args.rem_ip_addr, loc_qpn=args.loc_qpn, loc_psn=args.loc_psn, loc_r_key=args.loc_rkey, loc_base_addr=args.loc_base_addr,
                            rem_qpn=args.rem_qpn, rem_psn=0, rem_r_key=0, rem_base_addr=0)
            decode_udp_packet(data)
        elif args.request == REQ_MODIFY_QP_RTS:
            data = modify_qp_rts(loc_ip_addr=args.loc_ip_addr, rem_ip_addr=args.rem_ip_addr, loc_qpn=args.loc_qpn, loc_psn=args.loc_psn, loc_r_key=args.loc_rkey, loc_base_addr=args.loc_base_addr,
                            rem_qpn=args.rem_qpn, rem_psn=0, rem_r_key=0, rem_base_addr=0)
            decode_udp_packet(data)