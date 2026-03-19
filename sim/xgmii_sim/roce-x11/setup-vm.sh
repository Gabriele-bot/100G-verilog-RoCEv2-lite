#!/bin/bash

### Install Soft RoCE

apt-get update

# The RDMA stack and SoftRoCE require the generic kernel (not virtual kernel)
apt-get install -y linux-generic
apt-get autoremove -y --purge linux-virtual

# rdma-core and utilities
apt-get install -y rdma-core ibverbs-utils perftest rdmacm-utils

# enable rxe
mv /tmp/rxe_all.sh /usr/bin/
chmod +x /usr/bin/rxe_all.sh
mv /tmp/rxe.service /etc/systemd/system/
chown root:root /usr/bin/rxe_all.sh /etc/systemd/system/rxe.service
systemctl enable rxe.service
systemctl start rxe.service

# sockperf - need to be pre-built or downloaded
apt-get install -y sockperf

# RDMA coding test dependencis
apt-get install -y build-essential cmake librdmacm-dev

# install pyverbs api
apt-get install -y python3-pyverbs

# enable x11 forwarding
apt-get install -y xauth

# install wireshark
apt-get install -y software-properties-common
add-apt-repository ppa:wireshark-dev/stable
apt-get update

echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y wireshark > /dev/null

# yes | dpkg-reconfigure wireshark-common

### cleanup resources

echo "==> Cleaning up tmp and cache"

rm -rf /tmp/*
apt-get -y autoremove --purge
apt-get -y clean
apt-get -y autoclean
