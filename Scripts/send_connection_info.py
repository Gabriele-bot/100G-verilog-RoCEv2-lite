import socket
import struct
from ipaddress import ip_address

import argparse

parser = argparse.ArgumentParser(description='Send QP information via UDP')
parser.add_argument('-ic', '--client_ip_addr', metavar='N', type=str, default="22.1.212.11",
                    help='Client IP address (PC)')
parser.add_argument('-if', '--fpga_ip_addr', metavar='N', type=str, default="22.1.212.10",
                    help='FPGA IP address')
parser.add_argument('-l', '--length', metavar='N', type=int, default=128,
                    help='DMA transfer size in byte')
parser.add_argument('-r', '--rkey', metavar='N', type=int, default=0x234,
                    help='Remote key')
parser.add_argument('-a', '--BaseAddr', metavar='N', type=int, default=0x12341242,
                    help='Remote base address')
parser.add_argument('-o', '--addrOffset', metavar='N', type=int, default=0x0,
                    help='Remote address offset')
parser.add_argument('-qf', '--qpnf', metavar='N', type=int, default=0x11,
                    help='FPGA queue pair number')
parser.add_argument('-qc', '--qpnc', metavar='N', type=int, default=0x12,
                    help='Client queue pair number')
parser.add_argument('-p', '--psn', metavar='N', type=int, default=0x0,
                    help='Packet sequence number')
parser.add_argument('-i', '--immediate', action='store_true',
                    help='Immediate transfer')
parser.add_argument('-t', '--txtype', action='store_false',
                    help='Default transmit type is WRITE, set to transmit SEND instead')                    
parser.add_argument('-s', '--start', action='store_true',
                    help='Start transfer')

args = parser.parse_args()

UDP_PORT = 0x4321

def send_qp_info(client_ip_addr="22.1.212.11", fpga_ip_addr="22.1.212.10", fpga_qpn=0x11, client_qpn=0x12, psn=0x0, r_key=0x0, rem_base_addr=0x0):
    
    REM_IP_ADDRESS = client_ip_addr
    REM_IP_ADDRESS_INT = int(ip_address(client_ip_addr))
    R_KEY          = r_key
    FPGA_QPN       = fpga_qpn
    CLIENT_QPN     = client_qpn
    PSN            = psn
    REM_BASE_ADDR  = rem_base_addr

    MESSAGE = b''

    MESSAGE += struct.pack("<B", 0x1)  #QP_info_valid
    MESSAGE += struct.pack('<L', FPGA_QPN)[:3]  # fpga_qpn
    MESSAGE += struct.pack('<L', CLIENT_QPN)[:3]  # client_qpn
    MESSAGE += struct.pack('<L', PSN)[:3]  # rem_psn
    MESSAGE += struct.pack('<L', 0x0)[:3]  # loc_psn
    MESSAGE += struct.pack("<L", R_KEY)  #R key
    MESSAGE += struct.pack("<Q", REM_BASE_ADDR) # Base Address
    MESSAGE += struct.pack("<L", REM_IP_ADDRESS_INT)  # Rem_ip_addr

    MESSAGE += struct.pack("<B", 0x0)  #No transimt values
    MESSAGE += struct.pack("<Q", 0x0)  #TXmeta_rem_addr
    MESSAGE += struct.pack("<L", 0x0)  #DMA length
    MESSAGE += struct.pack("<H", 0x0)  #UDP_PORT
    
    

    print("UDP target IP:", fpga_ip_addr)
    print("UDP target port:", UDP_PORT)
    print("message:", MESSAGE)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # UDP
    sock.sendto(MESSAGE, (fpga_ip_addr, UDP_PORT))


def send_txmeta(client_ip_addr="22.1.212.11", fpga_ip_addr="22.1.212.10", rem_addr_offset=0x0, rdma_length=0x0, start_flag=0, immd_flag=0, txtype_flag=1):

    REM_IP_ADDRESS = client_ip_addr
    REM_IP_ADDRESS_INT = int(ip_address(client_ip_addr))
    DMA_LENGTH = rdma_length
    REM_ADDR_OFFSET = rem_addr_offset

    txmeta_flags = 0x1 | (start_flag << 1) |  (immd_flag << 2) | (txtype_flag << 3)
    print(txtype_flag)

    MESSAGE = b''

    MESSAGE += struct.pack("<B", 0x0)  # QP_info_valid
    MESSAGE += struct.pack('<L', 0x0)[:3]  # rem_qpn
    MESSAGE += struct.pack('<L', 0x0)[:3]  # loc_qpn
    MESSAGE += struct.pack('<L', 0x0)[:3]  # rem_psn
    MESSAGE += struct.pack('<L', 0x0)[:3]  # loc_psn
    MESSAGE += struct.pack("<L", 0x0)  # R key
    MESSAGE += struct.pack("<Q", 0x0)  # Base Address
    MESSAGE += struct.pack("<L", 0x0)  # Rem_ip_addr

    MESSAGE += struct.pack("<B", txmeta_flags)  # TX meta flags: valid, start, is_immd, txtype
    MESSAGE += struct.pack("<Q", REM_ADDR_OFFSET)  # TXmeta_rem_addr_offset
    MESSAGE += struct.pack("<L", DMA_LENGTH)  # DMA length
    MESSAGE += struct.pack("<H", 0x3412)  # UDP_PORT

    print("UDP target IP:", fpga_ip_addr)
    print("UDP target port:", UDP_PORT)
    print("message:", MESSAGE)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # UDP
    sock.connect((fpga_ip_addr, UDP_PORT))
    #sock.sendto(MESSAGE, (REM_IP_ADDRESS, UDP_PORT))
    sock.send(MESSAGE)


if __name__ == "__main__":

    if args.start:
        send_txmeta(client_ip_addr=args.client_ip_addr, fpga_ip_addr=args.fpga_ip_addr, rem_addr_offset=args.addrOffset, rdma_length=args.length, start_flag=args.start, immd_flag=args.immediate, txtype_flag=args.txtype)
    else:
        send_qp_info(client_ip_addr=args.client_ip_addr, fpga_ip_addr=args.fpga_ip_addr, fpga_qpn=args.qpnf, client_qpn=args.qpnc, psn=args.psn, r_key=args.rkey, rem_base_addr=args.BaseAddr)
        send_qp_info(client_ip_addr=args.client_ip_addr, fpga_ip_addr=args.fpga_ip_addr, fpga_qpn=args.qpnf, client_qpn=args.qpnc, psn=args.psn, r_key=args.rkey, rem_base_addr=args.BaseAddr)
