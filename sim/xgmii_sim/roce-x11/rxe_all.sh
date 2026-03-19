#!/bin/bash
for netdev in $(ls /sys/class/net | grep -v '^lo$') ; do
    rdma link add rxe_$netdev type rxe netdev $netdev
done
