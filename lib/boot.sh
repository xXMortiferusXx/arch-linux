#!/usr/bin/env bash
# Bootloader: GRUB (UEFI) + btrfs-Subvolume als Root.
# GRUB statt systemd-boot, weil grub-btrfs Snapshot-Eintraege ins Menue legt
# (Boot eines frueheren Zustands ohne Live-ISO).
# shellcheck shell=bash

TARGET=${TARGET:-/mnt}

install_boot() {
  local disk="$1"
  local profile="${2:-}"
  local root_uuid

  root_uuid="$(blkid -s UUID -o value "$PART_ROOT")"
  [ -n "$root_uuid" ] || die "UUID von $PART_ROOT nicht lesbar"

  # Host-spezifische Kernel-Parameter (optional): hosts/<host>/kernel-cmdline
  local extra_cmdline=""
  if [ -n "$profile" ] && [ -f "$profile/kernel-cmdline" ]; then
    extra_cmdline="$(tr '\n' ' ' < "$profile/kernel-cmdline" | sed 's/[[:space:]]*$//')"
  fi

  # GRUB-Theme: host-spezifisch (hosts/<host>/boot/grub), sonst shared/grub.
  local theme_src=""
  if [ -n "$profile" ] && [ -f "$profile/boot/grub/background.png" ]; then
    theme_src="$profile/boot/grub"
  elif [ -f "${REPO_DIR:-.}/shared/grub/background.png" ]; then
    theme_src="${REPO_DIR:-.}/shared/grub"
  fi

  local theme_dir="$TARGET/boot/grub/themes/unholy-angels"
  local grub_theme=""
  if [ -n "$theme_src" ]; then
    install -d "$theme_dir"
    install -m 644 "$theme_src/background.png" "$theme_dir/background.png"
    install -m 644 "$theme_src/theme/theme.txt" "$theme_dir/theme.txt"

    # Schriften aus DejaVu erzeugen; die Dateinamen muessen exakt zu den
    # Namen in theme.txt passen. Ohne ttf-dejavu: Standardschrift nutzen.
    if arch-chroot "$TARGET" test -f /usr/share/fonts/TTF/DejaVuSans.ttf; then
      arch-chroot "$TARGET" grub-mkfont -s 22 \
        -o "/boot/grub/themes/unholy-angels/DejaVu Sans Regular 22.pf2" \
        /usr/share/fonts/TTF/DejaVuSans.ttf
      if arch-chroot "$TARGET" test -f /usr/share/fonts/TTF/DejaVuSansMono.ttf; then
        arch-chroot "$TARGET" grub-mkfont -s 16 \
          -o "/boot/grub/themes/unholy-angels/DejaVu Sans Mono Regular 16.pf2" \
          /usr/share/fonts/TTF/DejaVuSansMono.ttf
      else
        sed -i '/^terminal-font:/d' "$theme_dir/theme.txt"
      fi
    else
      ui_warn "ttf-dejavu fehlt – GRUB nutzt seine Standardschrift"
      sed -i '/-font:/d' "$theme_dir/theme.txt"
    fi
    grub_theme="GRUB_THEME=\"/boot/grub/themes/unholy-angels/theme.txt\""
  fi

  # Firmware-/BootNext-Eintraege aus dem Menue nehmen (Optik/Aufraeumen).
  # 30_uefi-firmware und 31_efi_bootnext (Arch-Patch) listen NVRAM-Eintraege
  # wie "UEFI PXE", "UEFI Misc Device" – im Alltag nur Ballast.
  local grub_script
  for grub_script in 30_uefi-firmware 31_efi_bootnext; do
    if [ -x "$TARGET/etc/grub.d/$grub_script" ]; then
      chmod -x "$TARGET/etc/grub.d/$grub_script"
    fi
  done

  install -d "$TARGET/etc/default"
  cat > "$TARGET/etc/default/grub" <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=10
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="Arch"
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 udev.log_level=3"
GRUB_CMDLINE_LINUX="rootflags=subvol=@ ${extra_cmdline}"
GRUB_PRELOAD_MODULES="part_gpt btrfs"
GRUB_DISABLE_OS_PROBER=true
${grub_theme}
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

  # Fallback-Pfad \EFI\BOOT\BOOTX64.EFI zusaetzlich installieren: damit bootet
  # die Platte auch bei leerem/zurueckgesetztem UEFI-NVRAM (BIOS-Update,
  # andere Maschine, USB-Gehaeuse) – sonst landet man im PXE.
  arch-chroot "$TARGET" grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot \
    --removable \
    --recheck
  arch-chroot "$TARGET" grub-mkconfig -o /boot/grub/grub.cfg

  ui_ok "GRUB installiert (UUID $root_uuid, rootflags=subvol=@)"
}
