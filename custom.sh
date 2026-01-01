#!/bin/bash
zerotierid=""
if [[ ! -z "$zerotier" ]]; then
    sed -i "s/8056c2e21c000001/$zerotierid/g" feeds/luci/applications/luci-app-zerotier/root/etc/config/zerotier
    sed -i "s/8056c2e21c000001/$zerotierid/g" feeds/packages/net/zerotier/files/etc/config/zerotier
fi

sed -i "s/_5G*//g" target/linux/qualcommax/ipq60xx/base-files/etc/uci-defaults/992_set-wifi-uci.sh

sed -i 's/192.168.1.1/192.168.68.1/g' package/base-files/files/bin/config_generate