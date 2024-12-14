#!/bin/bash
zerotierid=""
sed -i "s/8056c2e21c000001/$zerotierid/g" feeds/luci/applications/luci-app-zerotier/root/etc/config/zerotier
sed -i "s/8056c2e21c000001/$zerotierid/g" feeds/packages/net/zerotier/files/etc/config/zerotier

sed -i "s/_5G*//g" target/linux/qualcommax/ipq60xx/base-files/etc/uci-defaults/992_set-wifi-uci.sh