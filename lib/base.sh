#!/usr/bin/env bash
# Basis-System: pacstrap, fstab, Grundkonfiguration, Passwoerter.
# shellcheck shell=bash

TARGET=${TARGET:-/mnt}

pacstrap_base() {
  local list="$1"
  require_cmd pacstrap

  enable_multilib
  # Live-System: gilt fuer pacstrap (schnellerer Download)
  set_parallel_downloads /etc/pacman.conf

  # base + linux-firmware immer, dazu die Host-Pakete (Kommentare/Leerzeilen ignorieren).
  local pkgs=()
  mapfile -t pkgs < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$list" | grep -v '^$')

  pacstrap -K "$TARGET" base linux linux-firmware "${pkgs[@]}"

  # Zielsystem: gleiche Einstellung dauerhaft
  set_parallel_downloads "$TARGET/etc/pacman.conf"
  ui_ok "pacstrap: ${#pkgs[@]} Host-Pakete + Basis"
}

# Parallele Downloads (Arch-Default: 5).
set_parallel_downloads() {
  local conf="$1"
  [ -f "$conf" ] || return 0
  if grep -qE '^#?ParallelDownloads' "$conf"; then
    sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' "$conf"
  else
    sed -i '/^\[options\]/a ParallelDownloads = 10' "$conf"
  fi
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

  # Spiele-Platte mit nofail: fehlt/defekt -> Boot laeuft weiter (wie /home
  # auf einer externen Platte). Fehler beim Mounten fallen im Journal auf.
  if [ -n "${GAMING:-}" ]; then
    awk 'BEGIN{OFS="\t"} $2=="/gaming" { for(i=4;i<=NF;i++) if($i=="defaults") $i="defaults,nofail" } {print}' \
      "$TARGET/etc/fstab" > "$TARGET/etc/fstab.tmp"
    mv "$TARGET/etc/fstab.tmp" "$TARGET/etc/fstab"
  fi

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

  # SSH-Keys (passwortloser Zugang, z. B. aus dem Test-Host)
  if [ -f "$profile/authorized_keys" ]; then
    local uid gid
    uid="$(arch-chroot "$TARGET" id -u "$username")"
    gid="$(arch-chroot "$TARGET" id -g "$username")"
    install -d -m 700 -o "$uid" -g "$gid" "$TARGET/home/$username/.ssh"
    install -m 600 -o "$uid" -g "$gid" "$profile/authorized_keys" \
      "$TARGET/home/$username/.ssh/authorized_keys"
    ui_ok "SSH-Key fuer $username installiert"
  fi
  arch-chroot "$TARGET" bash -c 'echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel'

  # Login-Shell auf fish (falls installiert)
  if arch-chroot "$TARGET" test -x /usr/bin/fish; then
    arch-chroot "$TARGET" usermod -s /usr/bin/fish "$username"
  fi

  arch-chroot "$TARGET" systemctl enable NetworkManager
  arch-chroot "$TARGET" systemctl enable sshd

  # Host-Configs (sysctl, udev, polkit, greetd ...) 1:1 uebernehmen.
  if [ -d "$profile/config" ]; then
    cp -a "$profile/config/." "$TARGET/"
    ui_ok "Host-Configs kopiert"
  fi

  # Home-Dotfiles des Hosts (Umbriel, Noctalia, GTK/Qt, nvim ...)
  if [ -d "$profile/home" ]; then
    cp -a "$profile/home/." "$TARGET/home/$username/"
    arch-chroot "$TARGET" chown -R "$username:$username" "/home/$username"
    ui_ok "Home-Configs kopiert"
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
