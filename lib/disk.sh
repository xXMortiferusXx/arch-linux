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

  # Reste eines frueheren Laufs loesen: /mnt rekursiv, dann alle Partitionen
  # des Zielgeraets (auch btrfs-Subvolume-Mounts wie /mnt/home).
  if mountpoint -q "$TARGET"; then
    umount -R "$TARGET" 2>/dev/null || true
  fi
  local part
  while read -r part; do
    [ -b "$part" ] || continue
    umount -R "$part" 2>/dev/null || true
  done < <(lsblk -nrpo NAME,TYPE "$dev" | awk '$2=="part"{print $1}')
  swapoff -a 2>/dev/null || true
  udevadm settle 2>/dev/null || true

  # Wenn noch etwas vom Ziel gemountet ist, klar abbrechen statt sgdisk zu quälen.
  if awk -v d="$dev" '$1 ~ d {found=1} END{exit !found}' /proc/mounts; then
    grep -E "$dev" /proc/mounts >&2 || true
    die "Ziel ist noch gemountet – bitte manuell aushaengen (umount -R $TARGET)"
  fi

  sgdisk --zap-all "$dev"
  sgdisk --clear \
         --new=1:0:+1G  --typecode=1:ef00 --change-name=1:ESP \
         --new=2:0:0    --typecode=2:8300 --change-name=2:ARCH \
         "$dev"
  partprobe "$dev" 2>/dev/null || true
  udevadm settle 2>/dev/null || true

  # -r (raw) ist wichtig: ohne Raw-Modus setzt lsblk Baumzeichen vor die Namen.
  local parts=() i
  for i in $(seq 1 20); do
    mapfile -t parts < <(lsblk -nrpo NAME,TYPE "$dev" | awk '$2=="part"{print $1}')
    [ "${#parts[@]}" -ge 2 ] && break
    sleep 0.5
  done
  PART_ESP="${parts[0]:-}"
  PART_ROOT="${parts[1]:-}"
  if [ ! -b "$PART_ESP" ] || [ ! -b "$PART_ROOT" ]; then
    lsblk -o NAME,SIZE,TYPE "$dev" >&2 || true
    die "Partitionen nicht erkannt ($dev)"
  fi
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
