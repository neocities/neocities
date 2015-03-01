#!/bin/bash

DEBIAN_FRONTEND=noninteractive

apt-get install -y lsyncd
mkdir /etc/lsyncd

# STOP. Generate a root ssh key on primary, and provide the public key to the root account on secondary in authorized_keys.

cp fs-primary/etc/lsyncd/lsyncd.conf.lua /etc/lsyncd/
# EDIT /etc/lsyncd/lsyncd.conf.lua
cp fs-primary/etc/logrotate.d/lsyncd /etc/logrotate.d/

service lsyncd start
#should already exist: sudo update-rc.d lsyncd defaults
