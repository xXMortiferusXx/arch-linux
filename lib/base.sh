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

  # base + linux-firmware immer, dazu shared/packages.list und die
  # Host-Pakete (Kommentare/Leerzeilen ignorieren).
  local pkgs=() shared_list="${REPO_DIR:-.}/shared/packages.list"
  if [ -f "$shared_list" ]; then
    mapfile -t pkgs < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$shared_list" "$list" | grep -v '^$' | awk '!seen[$0]++')
  else
    mapfile -t pkgs < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$list" | grep -v '^$')
  fi

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
    # Steam-taugliche Optionen: noatime (weniger Schreiblast), nofail (Boot
    # ohne Platte), kurzer Device-Timeout statt 90 s Wartezeit.
    awk 'BEGIN{OFS="\t"} $2=="/gaming" { $4 = "defaults,noatime,nofail,x-systemd.device-timeout=5" } {print}' \
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
  local username="${USERNAME:-mortiferus}"

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

  # Zusatzgruppen: audio/video fuer PipeWire+DRM. Die Gruppe "networkmanager"
  # ist nur fuer nmcli als User relevant (nmtui laeuft ueber Polkit/root).
  # Achtung: sysusers-Gruppen existieren im Chroot noch nicht -> vorher anlegen.
  local g
  for g in audio video; do
    arch-chroot "$TARGET" getent group "$g" >/dev/null 2>&1 \
      || arch-chroot "$TARGET" groupadd -r "$g"
  done
  local groups="wheel,audio,video"
  # Host-Extra-Gruppen (nex: input/scanner/lp, lion: keine)
  local eg
  for eg in ${EXTRA_GROUPS:-}; do
    arch-chroot "$TARGET" getent group "$eg" >/dev/null 2>&1 \
      || arch-chroot "$TARGET" groupadd -r "$eg"
    groups="$groups,$eg"
  done
  if [ "${I2C:-0}" = 1 ]; then
    arch-chroot "$TARGET" getent group i2c >/dev/null 2>&1 \
      || arch-chroot "$TARGET" groupadd -r i2c
    groups="$groups,i2c"
  fi
  arch-chroot "$TARGET" useradd -m -G "$groups" -s /bin/bash "$username"
  # 750 statt 775: sshd (StrictModes) verweigert gruppen-schreibbare Homes.
  chmod 750 "$TARGET/home/$username"

  local uid gid
  uid="$(arch-chroot "$TARGET" id -u "$username")"
  gid="$(arch-chroot "$TARGET" id -g "$username")"

  # Spiele-Platte: Mountpunkt dem User geben, sonst kann Steam keine
  # Bibliothek anlegen ("new library folder ... permission denied").
  if [ -n "${GAMING:-}" ] && mountpoint -q "$TARGET/gaming"; then
    chown "$uid:$gid" "$TARGET/gaming"
    if arch-chroot "$TARGET" runuser -u "$username" -- test -w /gaming; then
      ui_ok "Spiele-Platte fuer $username schreibbar"
    else
      ui_warn "/gaming ist fuer $username nicht schreibbar"
    fi
  fi

  # SSH-Keys (passwortloser Zugang, z. B. aus dem Test-Host)
  if [ -f "$profile/authorized_keys" ]; then
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
  if [ "${SSHD:-1}" = 1 ]; then
    arch-chroot "$TARGET" systemctl enable sshd
  fi

  # Configs: erst shared/config (gilt fuer alle), dann Host-Overrides.
  if [ -d "${REPO_DIR:-.}/shared/config" ]; then
    cp -a "${REPO_DIR:-.}/shared/config/." "$TARGET/"
  fi
  if [ -d "$profile/config" ]; then
    cp -a "$profile/config/." "$TARGET/"
    ui_ok "Configs kopiert (shared + Host)"
  fi

  # Home-Dotfiles: erst shared/home (Shell, nvim, icons ...), dann Host.
  if [ -d "${REPO_DIR:-.}/shared/home" ]; then
    cp -a "${REPO_DIR:-.}/shared/home/." "$TARGET/home/$username/"
  fi
  if [ -d "$profile/home" ]; then
    cp -a "$profile/home/." "$TARGET/home/$username/"
    arch-chroot "$TARGET" chown -R "$username:$username" "/home/$username"
    # cp -a uebernimmt auch den Modus des Quellverzeichnisses -> zuruecksetzen
    chmod 750 "$TARGET/home/$username"
    ui_ok "Home-Configs kopiert (shared + Host)"
  fi

  ui_ok "Grundkonfiguration ($host, $tz, $keymap)"
}

set_passwords() {
  local username="${USERNAME:-mortiferus}"
  ui_info "Passwort fuer root:"
  arch-chroot "$TARGET" passwd root
  ui_info "Passwort fuer $username:"
  arch-chroot "$TARGET" passwd "$username"
}
