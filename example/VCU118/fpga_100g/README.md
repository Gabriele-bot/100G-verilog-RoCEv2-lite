# Markdown syntax guide
# VCU118 Example Design

## Introduction

This example design targets the Xilinx VCU118 FPGA board.

Three designs:
*  fpga: 100Gbps target 1 RoCE module (1 QSFP)

### Project infos
*  FPGA: xcvu9p-flga2104-2L-e
*  MAC: Xilinx CMAC

## How to build
Modify the the Makefile to change the target project.  
Run make to build.  Ensure that the Xilinx Vivado toolchain components are
in PATH, you might need the lncence for the Xilinx cmac IP.  

## How to test

Program the VCU118 board with Vivado and chenge the IP address if needed (default is `22.1.212.10`).  Then run

    ping 22.1.212.10

Or run this command to arping the board (you might need to be a sudoer)  

    arping -c 10 -w 10 -I <network_interface> 22.1.212.10

To open a Queue Pair run the command (script is in the `Scripts` folder :D).

    python3 send_connection_info.py -il '22.1.212.11' -ir '22.1.212.10' -lr 537 -lq 17 -la 139795697803264 -lp 0 -r 1
    python3 send_connection_info.py -il '22.1.212.11' -ir '22.1.212.10' -lr 537 -lq 17 -la 139795697803264 -lp 0 -rq 256 -r 3

If succeded you can start sending data, you need an application for that otherwise the NIC won't send any ACKs.. this is up to you on how to develop the softwre part.  
To send dummy data you can use this command

    python3 send_connection_info.py -ir '22.1.212.10' -il '22.1.212.11' -rq 256 -r 0 -s -l 16000 -n 100
