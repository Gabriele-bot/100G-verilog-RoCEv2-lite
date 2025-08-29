import socket, struct, fcntl
import numpy as np
import zlib
from struct import pack

import argparse

parser = argparse.ArgumentParser(description='Send QP information via UDP')
parser.add_argument('-I', '--netdev', metavar='N', type=str, default="tap0",
                    help='Sender Network device')
parser.add_argument('-t', '--time-quanta', metavar='N', type=in, default=512,
                    help='Pause time')
parser.add_argument('-p', '--priories', metavar='N', type=int, default=0x02,
                    help='Affected priorities')
           
args = parser.parse_args()      

ifnet = args.netdev

# get MAC ADDRESS
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
info = fcntl.ioctl(s.fileno(), 0x8927,  struct.pack('256s', bytes(ifnet, 'utf-8')[:15]))
SOURCE_MAC_ADDR    = int.from_bytes(info[18:24], 'big')

s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
s.bind((ifnet, 0))

BROADCAST_MAC_ADDR = 0x0180C2000001
ETHER_TYPE = 0x8808
#PAUSE
#OPCODE = 0x0001 
#PAUSE_TIME = 255

#PFC
OPCODE = 0x0101 
CEV    = args.priorities
PAUSE_TIME = args.time-quanta


MESSAGE = b''

MESSAGE += struct.pack(">Q", BROADCAST_MAC_ADDR)[-6:]  # DEST MAC
MESSAGE += struct.pack(">Q", SOURCE_MAC_ADDR)[-6:]     # SRC  MAC
MESSAGE += struct.pack(">H", ETHER_TYPE)     # TYPE

#MESSAGE += struct.pack(">H", OPCODE) 
#MESSAGE += struct.pack(">H", PAUSE_TIME)

MESSAGE += struct.pack(">H", OPCODE)     
MESSAGE += struct.pack(">H", CEV)
for i in range(8):
	MESSAGE += struct.pack(">H", PAUSE_TIME)  
	
# PAD 28 bytes
for i in range(28):
	MESSAGE += struct.pack(">B", 0)  	  

#compute CRC



def fcs_ethernet(data: bytes) -> bytes:
    """
    Calcola l'FCS Ethernet (CRC-32 IEEE 802.3) sui byte 'data'
    e lo restituisce come 4 byte in little-endian, pronto da accodare al frame.
    """
    crc = zlib.crc32(data) & 0xFFFFFFFF   # CRC-32 standard (polinomio 0x04C11DB7 riflesso)
    return pack('<I', crc)                # FCS trasmesso LSB-first (little-endian)

FCS = fcs_ethernet(MESSAGE)

MESSAGE += FCS

s.send(MESSAGE)
