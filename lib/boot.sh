#!/usr/bin/env bash
# Bootloader: systemd-boot + Loader-Eintrag + initramfs.
# shellcheck shell=bash

TARGET=${TARGET:-/mnt}

install_boot() {
  local disk="$1"
  local root_uuid

  root_uuid="$(blkid -s UUID -o value "$PART_ROOT")"
  [ -n "$root_uuid" ] || die "UUID von $PART_ROOT nicht lesbar"

  arch-chroot "$TARGET" bootctl --esp-path=/boot install

  mkdir -p "$TARGET/boot/loader/entries"
  cat > "$TARGET/boot/loader/loader.conf" <<EOF
default arch.conf
timeout 3
editor 0
EOF

  cat > "$TARGET/boot/loader/entries/arch.conf" <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=${root_uuid} rw rootflags=subvol=@ quiet loglevel=3
EOF

  # initramfs neu bauen (Subvolumes + btrfs muessen rein).
  if ! grep -q '^HOOKS=.*btrfs' "$TARGET/etc/mkinitcpio.conf"; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block btrfs filesystems fsck)/' \
      "$TARGET/etc/mkinitcpio.conf"
  fi
  arch-chroot "$TARGET" mkinitcpio -P

  ui_ok "systemd-boot installiert (UUID $root_uuid)"
}
