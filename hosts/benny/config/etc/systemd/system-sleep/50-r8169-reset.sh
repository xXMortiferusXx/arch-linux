#!/bin/sh
# Realtek RTL8168f (r8169): nach S3 kommt der Link oft nicht zurueck.
# Modul beim Resume neu laden (reines ip link up/down reicht meist nicht).
case "$1" in
  post)
    /usr/bin/ethtool -s enp3s0 wol d 2>/dev/null || true
    /usr/bin/modprobe -r r8169 2>/dev/null || true
    /usr/bin/modprobe r8169 2>/dev/null || true
    /usr/bin/ip link set enp3s0 up 2>/dev/null || true
    /usr/bin/ethtool -s enp3s0 autoneg on 2>/dev/null || true
    ;;
esac
