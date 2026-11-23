#!/usr/bin/env bash
# Bootloader: GRUB (UEFI) + btrfs-Subvolume als Root.
# GRUB statt systemd-boot, weil grub-btrfs Snapshot-Eintraege ins Menue legt
# (Boot eines frueheren Zustands ohne Live-ISO).
# shellcheck shell=bash

TARGET=${TARGET:-/mnt}

install_boot() {
  local disk="$1"
  local root_uuid

  root_uuid="$(blkid -s UUID -o value "$PART_ROOT")"
  [ -n "$root_uuid" ] || die "UUID von $PART_ROOT nicht lesbar"

  install -d "$TARGET/etc/default"
  cat > "$TARGET/etc/default/grub" <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="Arch"
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"
GRUB_CMDLINE_LINUX="root=UUID=${root_uuid} rootflags=subvol=@ rw"
GRUB_PRELOAD_MODULES="part_gpt btrfs"
GRUB_DISABLE_OS_PROBER=true
EOF

  # initramfs mit btrfs-Hook (Subvolumes muessen im Initramfs lesbar sein).
  if ! grep -q '^HOOKS=.*btrfs' "$TARGET/etc/mkinitcpio.conf"; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block btrfs filesystems fsck)/' \
      "$TARGET/etc/mkinitcpio.conf"
  fi
  arch-chroot "$TARGET" mkinitcpio -P

  arch-chroot "$TARGET" grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot \
    --bootloader-id=GRUB \
    --recheck
  arch-chroot "$TARGET" grub-mkconfig -o /boot/grub/grub.cfg

  ui_ok "GRUB installiert (UUID $root_uuid, rootflags=subvol=@)"
}
