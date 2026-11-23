#!/usr/bin/env bash
# Basis-System: pacstrap, fstab, Grundkonfiguration, Passwoerter.
# shellcheck shell=bash

TARGET=${TARGET:-/mnt}

pacstrap_base() {
  local list="$1"
  require_cmd pacstrap

  enable_multilib

  # base + linux-firmware immer, dazu die Host-Pakete (Kommentare/Leerzeilen ignorieren).
  local pkgs=()
  mapfile -t pkgs < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$list" | grep -v '^$')

  pacstrap -K "$TARGET" base linux linux-firmware "${pkgs[@]}"
  ui_ok "pacstrap: ${#pkgs[@]} Host-Pakete + Basis"
}

# multilib ist Pflicht fuer Steam (32-bit) und lib32-Pakete.
enable_multilib() {
  if grep -q '^#\[multilib\]' /etc/pacman.conf; then
    sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    ui_ok "multilib aktiviert"
  elif ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    die "multilib nicht in /etc/pacman.conf gefunden"
  fi
}

gen_fstab() {
  require_cmd genfstab
  genfstab -U "$TARGET" >> "$TARGET/etc/fstab"
  ui_ok "fstab erzeugt"
}

configure_base() {
  local host="$1" profile="$2"

  local tz="Europe/Berlin"
  local keymap="de-latin1"
  local locale="de_DE.UTF-8"
  local username="mortiferus"

  # Host-spezifische Overrides (optional): KEY=VALUE, wird gesourct.
  if [ -f "$profile/settings.env" ]; then
    # shellcheck disable=SC1090
    . "$profile/settings.env"
  fi

  arch-chroot "$TARGET" ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
  arch-chroot "$TARGET" hwclock --systohc

  printf '%s UTF-8\n' "$locale" > "$TARGET/etc/locale.gen"
  arch-chroot "$TARGET" locale-gen
  printf 'LANG=%s\n' "$locale" > "$TARGET/etc/locale.conf"

  printf 'KEYMAP=%s\nFONT=lat9w-16\n' "$keymap" > "$TARGET/etc/vconsole.conf"
  printf '%s\n' "$host" > "$TARGET/etc/hostname"
  printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s.localdomain %s\n' "$host" "$host" > "$TARGET/etc/hosts"

  arch-chroot "$TARGET" useradd -m -G wheel -s /bin/bash "$username"
  arch-chroot "$TARGET" bash -c 'echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel'

  arch-chroot "$TARGET" systemctl enable NetworkManager
  arch-chroot "$TARGET" systemctl enable sshd

  # Host-Configs (sysctl, udev, polkit, greetd ...) 1:1 uebernehmen.
  if [ -d "$profile/config" ]; then
    cp -a "$profile/config/." "$TARGET/"
    ui_ok "Host-Configs kopiert"
  fi

  ui_ok "Grundkonfiguration ($host, $tz, $keymap)"
}

set_passwords() {
  local username="mortiferus"
  ui_info "Passwort fuer root:"
  arch-chroot "$TARGET" passwd root
  ui_info "Passwort fuer $username:"
  arch-chroot "$TARGET" passwd "$username"
}
