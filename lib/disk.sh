#!/usr/bin/env bash
# Partitionierung + btrfs-Subvolumes.
# Layout: ESP (1G, FAT32) + btrfs (Rest) mit @, @home, @gaming, @snapshots,
# @var_cache, @var_tmp, @var_log. Snapper laeuft spaeter nur auf @.
# shellcheck shell=bash

PART_ESP=""
PART_ROOT=""

disk_wipe() {
  local dev="$1"
  require_cmd sgdisk
  wait_unbusy "$dev"

  # Etwaige Mounts des Ziels loesen (Live-ISO kann Reste gemountet haben).
  for p in "${dev}"?*; do
    [ -b "$p" ] || continue
    umount -R "$p" 2>/dev/null || true
  done
  swapoff -a 2>/dev/null || true

  sgdisk --zap-all "$dev"
  sgdisk --clear \
         --new=1:0:+1G  --typecode=1:ef00 --change-name=1:ESP \
         --new=2:0:0    --typecode=2:8300 --change-name=2:ARCH \
         "$dev"
  partprobe "$dev"
  sleep 1

  PART_ESP="$(lsblk -npo NAME,TYPE "$dev" | awk '$2=="part"{print $1}' | head -1)"
  PART_ROOT="$(lsblk -npo NAME,TYPE "$dev" | awk '$2=="part"{print $1}' | tail -1)"
  [ -b "$PART_ESP" ] && [ -b "$PART_ROOT" ] || die "Partitionen nicht erkannt ($dev)"
  ui_ok "Partitionen: $PART_ESP (ESP), $PART_ROOT (root)"
}

disk_mkfs() {
  require_cmd mkfs.fat
  require_cmd mkfs.btrfs

  mkfs.fat -F32 -n ESP "$PART_ESP"
  mkfs.btrfs -f -L ARCH "$PART_ROOT"

  mount "$PART_ROOT" /mnt
  for sv in @ @home @gaming @snapshots @var_cache @var_tmp @var_log; do
    btrfs subvolume create "/mnt/$sv"
  done
  umount /mnt

  mount_target
  ui_ok "Subvolumes angelegt"
}

mount_target() {
  local opts="compress=zstd:3,noatime"

  mount -o "subvol=@,$opts" "$PART_ROOT" /mnt
  mkdir -p /mnt/{home,gaming,.snapshots,var/cache,var/tmp,var/log,boot,etc}
  mount -o "subvol=@home,$opts"       "$PART_ROOT" /mnt/home
  mount -o "subvol=@gaming,$opts"     "$PART_ROOT" /mnt/gaming
  mount -o "subvol=@snapshots,$opts"  "$PART_ROOT" /mnt/.snapshots
  mount -o "subvol=@var_cache,$opts"  "$PART_ROOT" /mnt/var/cache
  mount -o "subvol=@var_tmp,$opts"    "$PART_ROOT" /mnt/var/tmp
  mount -o "subvol=@var_log,$opts"    "$PART_ROOT" /mnt/var/log
  mount "$PART_ESP" /mnt/boot
}
