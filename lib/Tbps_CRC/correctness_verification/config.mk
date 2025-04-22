#!/bin/sh
#modify this config file for different configurations
#board setting
PART_NUM="xcu250-figd2104-2L-e"  #the part number of the target fpga

# general setup
DWIDTH="512"             #data width
CRC_WIDTH="32"           #crc polynomial width
PIPE_LVL="0"             #pipeline level for crc calculation, deeper pipeline increases overall latency and area, but results in better fmax/throughput
CRC_POLY="32'h04C11DB7"  #crc polynomial
INIT="32'hffffffff"      #init hex
XOR_OUT="32'hffffffff"   #xor out hex
REFIN="1"                #reflect in, 1 for yes, 0 for no
REFOUT="1"               #reflect out, 1 for yes, 0 for no

# simulation
N_MESSAGE="10"           #number of messages to send in simulation
MESSAGE_LEN_MIN="1"      #min message size (in byte) in simulation
MESSAGE_LEN_MAX="1500"   #max message size (in byte) in simulation
flitEn_ratio="0.8"       #ratio of the valid flits during simulation, 0.8 means 80% of the flits are valid, 20% of bubble (invalid) flits for each message

# hardware implementation
PKT_LIMIT="10"           #number of messages to send in hardware test
BYTE_BITS="11"           #max message size (in byte) in hardware test, here max message size is 2^11=2048 bytes
