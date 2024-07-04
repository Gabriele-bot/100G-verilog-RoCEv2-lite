import socket
import struct
from ipaddress import ip_address

import argparse

parser = argparse.ArgumentParser(description='Send QP information via UDP')
parser.add_argument('-i', '--ip_addr', metavar='N', type=str, default="22.1.212.10",
                    help='RoCE TX IP address')
parser.add_argument('-l', '--length', metavar='N', type=int, default=128,
                    help='DMA transfer size in byte')
parser.add_argument('-r', '--rkey', metavar='N', type=int, default=0x234,
                    help='Remote key')
parser.add_argument('-a', '--BaseAddr', metavar='N', type=int, default=0x12341242,
                    help='Remote base address')
parser.add_argument('-o', '--addrOffset', metavar='N', type=int, default=0x0,
                    help='Remote address offset')
parser.add_argument('-q', '--qpn', metavar='N', type=int, default=0x11,
                    help='Remote queue pair number')
parser.add_argument('-p', '--psn', metavar='N', type=int, default=0x0,
                    help='Remote packet sequence number')
parser.add_argument('-s', '--start', action='store_true',
                    help='Start transfer')

args = parser.parse_args()


def send_qp_info(rem_ip_addr="22.1.212.11", rem_qpn=0x11, rem_psn=0x0, r_key=0x0, rem_base_addr=0x0):
    UDP_PORT = 0x4321

    REM_IP_ADDRESS = rem_ip_addr
    R_KEY = r_key
    QPN = rem_qpn
    PSN = rem_psn
    REM_BASE_ADDR = rem_base_addr

    MESSAGE = b''

    MESSAGE += struct.pack(">B", 0x1)  #QP_info_valid
    MESSAGE += struct.pack('>L', QPN)[-3:]  # rem_qpn
    MESSAGE += struct.pack('>L', 0x0012)[-3:]  # loc_qpn
    MESSAGE += struct.pack('>L', PSN)[-3:]  # rem_psn
    MESSAGE += struct.pack('>L', 0x0)[-3:]  # loc_psn
    MESSAGE += struct.pack(">L", R_KEY)  #R key
    MESSAGE += struct.pack(">Q", REM_BASE_ADDR) # Base Address

    MESSAGE += struct.pack(">B", 0x0)  #No transimt values
    MESSAGE += struct.pack(">L", 0x0)  #TXmeta_rem_ip_addr
    MESSAGE += struct.pack(">Q", 0x0)  #TXmeta_rem_addr
    MESSAGE += struct.pack(">L", 0x0)  #DMA length
    MESSAGE += struct.pack(">H", 0x0)  #UDP_PORT

    print("UDP target IP:", "22.1.212.10")
    print("UDP target port:", UDP_PORT)
    print("message:", MESSAGE)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # UDP
    sock.sendto(MESSAGE, ("22.1.212.10", UDP_PORT))


def send_txmeta(rem_ip_addr="22.1.212.11", rem_addr_offset=0x0, rdma_length=0x0, start_flag=0):
    UDP_PORT = 0x4321

    REM_IP_ADDRESS = rem_ip_addr
    REM_IP_ADDRESS_INT = int(ip_address(rem_ip_addr))
    DMA_LENGTH = rdma_length
    REM_ADDR_OFFSET = rem_addr_offset

    start_and_valid = 0x1 | (start_flag << 1)
    print(start_and_valid)

    MESSAGE = b''

    MESSAGE += struct.pack(">B", 0x0)  # QP_info_valid
    MESSAGE += struct.pack('>L', 0x0)[-3:]  # rem_qpn
    MESSAGE += struct.pack('>L', 0x0)[-3:]  # loc_qpn
    MESSAGE += struct.pack('>L', 0x0)[-3:]  # rem_psn
    MESSAGE += struct.pack('>L', 0x0)[-3:]  # loc_psn
    MESSAGE += struct.pack(">L", 0x0)  # R key
    MESSAGE += struct.pack(">Q", 0x0)  # Base Address

    MESSAGE += struct.pack(">B", start_and_valid)  # No transimt values
    MESSAGE += struct.pack(">L", REM_IP_ADDRESS_INT)  # TXmeta_rem_ip_addr
    MESSAGE += struct.pack(">Q", REM_ADDR_OFFSET)  # TXmeta_rem_addr_offset
    MESSAGE += struct.pack(">L", DMA_LENGTH)  # DMA length
    MESSAGE += struct.pack(">H", 0x3412)  # UDP_PORT

    print("UDP target IP:", "22.1.212.10")
    print("UDP target port:", UDP_PORT)
    print("message:", MESSAGE)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # UDP
    sock.connect(("22.1.212.10", UDP_PORT))
    #sock.sendto(MESSAGE, (REM_IP_ADDRESS, UDP_PORT))
    sock.send(MESSAGE)


if __name__ == "__main__":

    if args.start:
        send_txmeta(rem_ip_addr=args.ip_addr, rem_addr_offset=args.addrOffset, rdma_length=args.length, start_flag=args.start)
    else:
        send_qp_info(rem_ip_addr=args.ip_addr, rem_qpn=args.qpn, rem_psn=args.psn, r_key=args.rkey, rem_base_addr=args.BaseAddr)
        send_qp_info(rem_ip_addr=args.ip_addr, rem_qpn=args.qpn, rem_psn=args.psn, r_key=args.rkey, rem_base_addr=args.BaseAddr)
