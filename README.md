# 100G-verilog-RoCEv2-lite

!!!! Based Alex Forencich code !!!!

TX only RoCEv2. Super stripped down version of a RoCEv2 endpoint. \\
Up to now only RC RDMA WRITE. RX part is there only to read ACKs and NAKs.

## Diagram
<center>
    <img src="img/RoCE_TX_diagram.png" alt="Drawing" style="width: 500px"/>
</center>

Still Work In Progress, many things need to be adjusted:
- [] QP state module need to be updated
- [] Modify RX and TX to support variable datapath width, minimum should be 64 bits
- [] Optimize mask fields, now takes far too many LUTS (11k-15k)
- [] Migth be usefull to add UC RDMA WRITE
- [] Finish retransmission module
