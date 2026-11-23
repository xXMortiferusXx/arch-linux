#!/usr/bin/env bash
# Host-Extras: Snapshots, NVIDIA/PRIME, Desktop (Umbriel/Noctalia), Gaming.
# shellcheck shell=bash

TARGET=${TARGET:-/mnt}

install_extras() {
  local profile="$1"

  extras_chaotic
  extras_snapshots "$profile"
  extras_btrfs
  extras_nvidia "$profile"
  extras_desktop "$profile"
  extras_gaming "$profile"
  extras_sunshine
  extras_system
  extras_apps
  extras_services

  if [ -x "$profile/post.sh" ]; then
    ui_step "Host-Post-Skript"
    "$profile/post.sh" "$TARGET"
  fi

  extras_snap_pac
}

# snap-pac zuletzt: sein pacman-Hook braucht snapperd (DBus), das im chroot
# nicht laeuft. Mit leerem hookdir installieren, damit der Hook nicht feuert.
extras_snap_pac() {
  ui_step "snap-pac"
  # Leerer Hookdir, damit snap-pacs post-transaction-Hook nicht feuert
  # (snapperd/DBus fehlt im chroot). Pfad ausserhalb /tmp: arch-chroot kann
  # /tmp ueberdecken.
  install -d "$TARGET/etc/pacman-hooks-off"
  if ! arch-chroot "$TARGET" pacman -S --needed --noconfirm --hookdir /etc/pacman-hooks-off snap-pac; then
    ui_warn "snap-pac mit leerem hookdir fehlgeschlagen – installiere ohne"
    arch-chroot "$TARGET" pacman -S --needed --noconfirm snap-pac \
      || die "snap-pac nicht installierbar"
  fi
  rm -rf "$TARGET/etc/pacman-hooks-off"
  ui_ok "snap-pac installiert (Pre/Post-Snapshots ab dem ersten Boot)"
}

# snapper nur fuer @ (System). /home, /gaming und /var/* sind eigene
# Subvolumes und damit automatisch ausgenommen.
#
# Zwei Eigenheiten von snapper auf Arch:
#   1) create-config legt .snapshots selbst an -> scheitert, weil unser
#      @snapshots-Subvolume bereits unter /.snapshots gemountet ist. Also
#      create-config versuchen (Fehler ignorieren) und die Config schreiben.
#   2) /etc/conf.d/snapper (SNAPPER_CONFIGS) ist Pflicht: ohne Registrierung
#      findet die CLI keine Config ("Konfiguration Root ist nicht vorhanden")
#      und die systemd-Timer laufen leer.
# Chaotic-AUR einbinden (Keyring + Mirrorlist). Wird von Desktop und
# snapper-support gebraucht.
extras_chaotic() {
  ui_step "chaotic-aur"
  arch-chroot "$TARGET" pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com >/dev/null 2>&1 \
    || die "chaotic-aur: Key nicht abrufbar"
  arch-chroot "$TARGET" pacman-key --lsign-key 3056513887B78AEB >/dev/null 2>&1 \
    || die "chaotic-aur: Key nicht signierbar"
  arch-chroot "$TARGET" pacman -U --noconfirm \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' >/dev/null \
    || die "chaotic-aur: keyring/mirrorlist nicht installierbar"
  if ! grep -q '^\[chaotic-aur\]' "$TARGET/etc/pacman.conf"; then
    printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' >> "$TARGET/etc/pacman.conf"
  fi
  arch-chroot "$TARGET" pacman -Sy --noconfirm >/dev/null
  ui_ok "chaotic-aur eingebunden"
}

extras_snapshots() {
  ui_step "Snapshots (snapper)"

  arch-chroot "$TARGET" snapper --no-dbus create-config / </dev/null >/dev/null 2>&1 || true

  install -d -m 755 "$TARGET/etc/snapper/configs"
  cat > "$TARGET/etc/snapper/configs/root" <<'CFG'
SUBVOLUME="/"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS="wheel"
SYNC_ACL="no"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="10"
NUMBER_LIMIT_IMPORTANT="5"
TIMELINE_CREATE="no"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="3600"
TIMELINE_LIMIT_HOURLY="10"
TIMELINE_LIMIT_DAILY="10"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="0"
TIMELINE_LIMIT_QUARTERLY="0"
TIMELINE_LIMIT_YEARLY="0"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="3600"
CFG

  install -d -m 755 "$TARGET/etc/conf.d"
  cat > "$TARGET/etc/conf.d/snapper" <<'CONF'
# Registrierung der snapper-Configs (von snapper-CLI und -Timern gelesen)
SNAPPER_CONFIGS="root"
CONF

  arch-chroot "$TARGET" systemctl enable snapper-cleanup.timer
  arch-chroot "$TARGET" systemctl disable snapper-timeline.timer >/dev/null 2>&1 || true

  # Snapshot-Booteintraege: grub-btrfs baut das GRUB-Menue, snapper-support
  # (chaotic) liefert den passenden Path/Service dafuer.
  arch-chroot "$TARGET" pacman -S --needed --noconfirm grub-btrfs snapper-support \
    || die "grub-btrfs/snapper-support nicht installierbar"
  arch-chroot "$TARGET" systemctl enable grub-btrfsd.service
  arch-chroot "$TARGET" systemctl enable grub-btrfs-snapper.path

  ui_ok "snapper: / (NUMBER_LIMIT=10), grub-btrfs (Snapshot-Booteintraege)"
}

# Btrfs-Wartung (Pendant zu modules/system/btrfs.nix im NixOS-Repo):
#   - Scrub monatlich: btrfs-scrub@.timer kommt von btrfs-progs
#   - Balance woechentlich: -d usage=5, nice 19, idle I/O
#   - fstrim woechentlich (services.fstrim)
# Ein Pool mit Subvolumes (@, @home, @gaming, ...) -> eine Instanz fuer "/".
extras_btrfs() {
  ui_step "Btrfs-Wartung (Scrub/Balance/TRIM)"
  arch-chroot "$TARGET" systemctl enable btrfs-scrub@-.timer \
    || die "btrfs-scrub@-.timer nicht aktivierbar"

  cat > "$TARGET/etc/systemd/system/btrfs-balance.service" <<'EOF'
[Unit]
Description=BTRFS Balance auf /
After=btrfs-scrub@-.service
Conflicts=shutdown.target sleep.target
Before=shutdown.target sleep.target

[Service]
Type=oneshot
Nice=19
IOSchedulingClass=idle
# nur schwach belegte Chunks umpacken (kein Voll-Balance)
ExecStart=/usr/bin/btrfs balance start -d usage=5 /
EOF

  cat > "$TARGET/etc/systemd/system/btrfs-balance.timer" <<'EOF'
[Unit]
Description=Woechentlicher BTRFS Balance Timer auf /

[Timer]
OnCalendar=weekly
AccuracySec=1d
Persistent=true

[Install]
WantedBy=timers.target
EOF

  arch-chroot "$TARGET" systemctl enable btrfs-balance.timer \
    || die "btrfs-balance.timer nicht aktivierbar"
  arch-chroot "$TARGET" systemctl enable fstrim.timer \
    || ui_warn "fstrim.timer nicht aktivierbar"

  ui_ok "btrfs: Scrub monatlich, Balance woechentlich, fstrim woechentlich"
}

# NVIDIA (offene Module) + PRIME-Offload + Dynamic Boost.
extras_nvidia() {
  ui_step "NVIDIA/PRIME"
  # Env fuer die ganze Session (iGPU treibt das Display, dGPU per prime-run).
  cat > "$TARGET/etc/environment" <<'EOF'
# Compositor/Display laeuft auf der iGPU (radeonsi)
LIBVA_DRIVER_NAME=radeonsi
VDPAU_DRIVER=radeonsi
# VRR nur fuer prime-run-Spiele
__GL_VRR_ALLOWED=1
EOF

  # VRAM-Heap-Fix fuer Electron-/GPU-Apps (GLVidHeapReuseRatio=0)
  install -d "$TARGET/etc/nvidia/nvidia-application-profiles-rc.d"
  cat > "$TARGET/etc/nvidia/nvidia-application-profiles-rc.d/50-vram-fix.json" <<'EOF'
{
  "rules": [
    { "pattern": { "feature": "procname", "matches": "umbriel" }, "profile": "No VidMem Reuse" },
    { "pattern": { "feature": "procname", "matches": "steamwebhelper" }, "profile": "No VidMem Reuse" },
    { "pattern": { "feature": "procname", "matches": "Discord" }, "profile": "No VidMem Reuse" },
    { "pattern": { "feature": "procname", "matches": "vesktop" }, "profile": "No VidMem Reuse" },
    { "pattern": { "feature": "procname", "matches": "heroic" }, "profile": "No VidMem Reuse" }
  ],
  "profiles": [
    { "name": "No VidMem Reuse", "settings": [ { "key": "GLVidHeapReuseRatio", "value": 0 } ] }
  ]
}
EOF

  # Dynamic Boost (115 -> 130 W)
  arch-chroot "$TARGET" systemctl enable nvidia-powerd

  # Offload-Wrapper: setzt zusaetzlich VK_DRIVER_FILES, damit der Vulkan-Loader
  # die dGPU nimmt (NVIDIA bringt hier keine Layer mit).
  cat > "$TARGET/usr/local/bin/nvidia-offload" <<'EOF'
#!/bin/sh
export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/nvidia_icd.json
exec "$@"
EOF
  chmod 755 "$TARGET/usr/local/bin/nvidia-offload"

  ui_ok "NVIDIA: Env, VRAM-Profile, nvidia-powerd, nvidia-offload"
}

# Chaotic-AUR + Umbriel/Noctalia/Greeter + greetd.
extras_desktop() {
  ui_step "Desktop (chaotic-aur, Umbriel/Noctalia)"

  # greetd kommt erst hier: sein Provider (greetd-greeter) liefert
  # noctalia-greeter-git aus chaotic - im pacstrap-Schritt gaebe es sonst
  # eine pacman-Rueckfrage nach einem fremden Greeter.
  arch-chroot "$TARGET" pacman -S --needed --noconfirm \
    greetd umbriel-git noctalia-git noctalia-greeter-git xdg-desktop-portal-umbriel-git \
    || die "Desktop-Pakete (chaotic) nicht installierbar"

  # Greeter-User + greetd (User explizit anlegen, Fehler nicht verschlucken)
  if ! arch-chroot "$TARGET" id greeter >/dev/null 2>&1; then
    arch-chroot "$TARGET" groupadd --system greeter
    arch-chroot "$TARGET" useradd --system -g greeter -d /var/lib/noctalia-greeter -s /usr/bin/nologin greeter
  fi
  arch-chroot "$TARGET" id greeter >/dev/null 2>&1 || die "greeter-User konnte nicht angelegt werden"
  install -d -o 0 -g 0 -m 755 "$TARGET/etc/greetd"
  cat > "$TARGET/etc/greetd/config.toml" <<'EOF'
[terminal]
vt = 1

[default_session]
command = "noctalia-greeter-session"
user = "greeter"
EOF

  # Greeter-Config (deutsche Tastatur, keine Uhr)
  install -d -o 0 -g 0 -m 755 "$TARGET/etc"
  cat > "$TARGET/etc/noctalia-greeter.toml" <<'EOF'
[keyboard]
layout = "de"

[appearance]
password_style = "random"

[clock]
enabled = false
EOF
  install -d -m 750 "$TARGET/var/lib/noctalia-greeter"
  arch-chroot "$TARGET" chown -R greeter:greeter /var/lib/noctalia-greeter

  # Der Greeter liest seine Config aus /var/lib/noctalia-greeter/greeter.toml
  # (wie im NixOS-Modul); /etc ist nur die Quelle.
  install -m 644 "$TARGET/etc/noctalia-greeter.toml" "$TARGET/var/lib/noctalia-greeter/greeter.toml"
  arch-chroot "$TARGET" chown greeter:greeter /var/lib/noctalia-greeter/greeter.toml

  # Avatar fuer den Greeter: ~/.face kommt aus dem Host-Profil (home/.face).
  # Der Greeter laeuft als User greeter und braucht Execute-Recht auf $HOME
  # (Pendant zu setfacl u:greeter:x in modules/home/*/config.nix).
  local username="mortiferus"
  if [ -f "$profile/settings.env" ]; then
    # shellcheck disable=SC1090
    . "$profile/settings.env"
  fi
  if [ -f "$TARGET/home/$username/.face" ]; then
    setfacl -m u:greeter:x,m::r-x "$TARGET/home/$username" \
      || ui_warn "setfacl fuer /home/$username fehlgeschlagen"

    # AccountsService braucht das Icon explizit (nicht nur ~/.face), sonst
    # zeigt der Greeter das Standard-Symbol.
    install -d -m 755 "$TARGET/var/lib/AccountsService/icons"
    install -d -m 700 "$TARGET/var/lib/AccountsService/users"
    install -m 644 "$TARGET/home/$username/.face" \
      "$TARGET/var/lib/AccountsService/icons/$username"
    cat > "$TARGET/var/lib/AccountsService/users/$username" <<EOF
[User]
Icon=/var/lib/AccountsService/icons/$username
SystemAccount=false
EOF
    chmod 600 "$TARGET/var/lib/AccountsService/users/$username"
    ui_ok "Avatar fuer den Greeter gesetzt (AccountsService)"
  fi

  arch-chroot "$TARGET" systemctl enable greetd
  arch-chroot "$TARGET" systemctl set-default graphical.target
  ui_ok "Desktop: greetd + Noctalia-Greeter (de, ohne Uhr)"
}

# Gaming-Stack: Basis aus packages.list, Nischen-Tools aus chaotic.
extras_gaming() {
  ui_step "Gaming"
  arch-chroot "$TARGET" pacman -S --needed --noconfirm \
    heroic-games-launcher-bin protonplus lsfg-vk-git \
    || die "Gaming-Pakete (chaotic) nicht installierbar"
  ui_ok "Heroic, ProtonPlus, lsfg-vk installiert"
}

# Sunshine (Game-Streaming-Host, nex-only) aus dem offiziellen LizardByte-Repo.
# Nicht aus der AUR: das Bin-Paket dort ist gegen feste Bibliotheksversionen
# gebaut (libicu) und bricht bei Systemupdates. LizardByte baut taeglich neu.
# autoStart bleibt aus (wie services.sunshine.autoStart = false in NixOS);
# das Paket setzt cap_sys_admin/cap_sys_nice selbst (Pendant zu capSysAdmin).
extras_sunshine() {
  ui_step "Sunshine (Game-Streaming)"
  if ! grep -q '^\[lizardbyte\]' "$TARGET/etc/pacman.conf"; then
    printf '\n[lizardbyte]\nSigLevel = Optional\nServer = https://github.com/LizardByte/pacman-repo/releases/latest/download\n' \
      >> "$TARGET/etc/pacman.conf"
  fi
  arch-chroot "$TARGET" pacman -Sy --noconfirm >/dev/null
  arch-chroot "$TARGET" pacman -S --needed --noconfirm sunshine \
    || die "sunshine (lizardbyte) nicht installierbar"
  # uinput/uhid fuer virtuelles Gamepad (modprobe im chroot greift nicht)
  if ! grep -q '^uinput$' "$TARGET/etc/modules-load.d/nex.conf" 2>/dev/null; then
    printf 'uinput\nuhid\n' >> "$TARGET/etc/modules-load.d/nex.conf"
  fi
  ui_ok "Sunshine installiert (User-Service, nicht autostart)"
}

# Desktop-/Zusatz-Apps, die es nur in chaotic gibt.
extras_apps() {
  ui_step "Zusatz-Apps (chaotic)"
  arch-chroot "$TARGET" pacman -S --needed --noconfirm \
    bibata-cursor-theme tela-icon-theme naps2 vinegar python-pynput \
    || ui_warn "einzelne chaotic-Apps nicht verfuegbar"
  ui_ok "Cursor/Icon-Theme, NAPS2, Vinegar, python-pynput"
}

# Dienste wie im NixOS-Setup (Bluetooth, Drucken, DNS-Cache, Zeit, Firmware).
extras_services() {
  ui_step "Dienste"

  local unit
  for unit in bluetooth.service power-profiles-daemon.service upower.service \
              udisks2.service irqbalance.service colord.service smartd.service \
              cups.socket avahi-daemon.service avahi-daemon.socket \
              fwupd.service fwupd-refresh.timer; do
    arch-chroot "$TARGET" systemctl enable "$unit" >/dev/null 2>&1 \
      || ui_warn "$unit nicht aktivierbar"
  done

  # WLAN ueber iwd (Backend in /etc/NetworkManager/conf.d/10-wifi.conf)
  arch-chroot "$TARGET" systemctl enable iwd.service >/dev/null 2>&1 \
    || ui_warn "iwd.service nicht aktivierbar"

  # DNS-Cache (systemd-resolved), resolv.conf zeigt auf den Stub
  if arch-chroot "$TARGET" systemctl enable systemd-resolved.service >/dev/null 2>&1; then
    ln -sf /run/systemd/resolve/stub-resolv.conf "$TARGET/etc/resolv.conf"
  else
    ui_warn "systemd-resolved nicht aktivierbar"
  fi

  # Zeit: chrony statt systemd-timesyncd
  arch-chroot "$TARGET" systemctl disable systemd-timesyncd.service >/dev/null 2>&1 || true
  arch-chroot "$TARGET" systemctl enable chrony.service >/dev/null 2>&1 \
    || ui_warn "chrony.service nicht aktivierbar"

  # Bluetooth nicht automatisch einschalten (wie powerOnBoot = false)
  if [ -f "$TARGET/etc/bluetooth/main.conf" ]; then
    sed -i 's/^#\?AutoEnable=.*/AutoEnable=false/' "$TARGET/etc/bluetooth/main.conf"
  fi

  ui_ok "Bluetooth, Printing, DNS-Cache, chrony, fwupd, irqbalance aktiv"
}

# System-Tuning: accounts-daemon (Greeter-Userliste), ananicy-cpp.
extras_system() {
  ui_step "System-Tuning"

  arch-chroot "$TARGET" systemctl enable accounts-daemon.service

  # paru (AUR-Helper) aus chaotic; base-devel kommt aus packages.list.
  arch-chroot "$TARGET" pacman -S --needed --noconfirm paru \
    || ui_warn "paru nicht installierbar – AUR-Pakete manuell bauen"

  arch-chroot "$TARGET" pacman -S --needed --noconfirm ananicy-rules-git \
    || ui_warn "ananicy-rules-git nicht verfuegbar – nur ananicy-cpp"
  install -d -m 755 "$TARGET/etc/ananicy.d"
  cat > "$TARGET/etc/ananicy.d/00-defaults.conf" <<'EOF'
check_freq = 15
loglevel = "warn"
log_applied_rule = false
cgroup_realtime_workaround = false
apply_cgroup = false
EOF
  arch-chroot "$TARGET" systemctl enable ananicy-cpp.service \
    || die "ananicy-cpp.service fehlt (Paket ananicy-cpp installiert?)"

  # scx_loader: scx_bpfland im Gaming-Modus (Config in hosts/nex/config).
  # Der Loader steckt in scx-tools, nicht in scx-scheds.
  arch-chroot "$TARGET" systemctl enable scx_loader.service \
    || die "scx_loader.service fehlt (Paket scx-tools installiert?)"

  # MS-Corefonts (nur chaotic)
  arch-chroot "$TARGET" pacman -S --needed --noconfirm ttf-ms-fonts \
    || ui_warn "ttf-ms-fonts nicht verfuegbar"

  ui_ok "accounts-daemon, ananicy-cpp, scx_loader aktiv"
}
