#!/usr/bin/env bash
# Host-Extras: Snapshots, NVIDIA/PRIME, Desktop (Umbriel/Noctalia), Gaming.
# shellcheck shell=bash

TARGET=${TARGET:-/mnt}

install_extras() {
  local profile="$1"

  extras_snapshots "$profile"
  extras_nvidia "$profile"
  extras_desktop "$profile"
  extras_gaming "$profile"

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
  install -d "$TARGET/tmp/nohooks"
  arch-chroot "$TARGET" pacman -S --needed --noconfirm --hookdir /tmp/nohooks snap-pac
  rm -rf "$TARGET/tmp/nohooks"
  ui_ok "snap-pac installiert (Pre/Post-Snapshots ab dem ersten Boot)"
}

# snapper nur fuer @ (System). /home, /gaming und /var/* sind eigene
# Subvolumes und damit automatisch ausgenommen.
# Die Config wird direkt geschrieben: "snapper create-config" braucht DBus
# (snapperd), das im arch-chroot nicht laeuft.
extras_snapshots() {
  ui_step "Snapshots (snapper)"

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
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="0"
TIMELINE_LIMIT_DAILY="0"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="0"
TIMELINE_LIMIT_YEARLY="0"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="1800"
CFG

  arch-chroot "$TARGET" systemctl enable snapper-cleanup.timer

  ui_ok "snapper: / (NUMBER_LIMIT=10, keine Timeline), snap-pac aktiv"
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

  arch-chroot "$TARGET" pacman -S --needed --noconfirm \
    umbriel-git noctalia-git noctalia-greeter-git xdg-desktop-portal-umbriel-git \
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

  arch-chroot "$TARGET" systemctl enable greetd
  arch-chroot "$TARGET" systemctl set-default graphical.target
  ui_ok "Desktop: greetd + Noctalia-Greeter (de, ohne Uhr)"
}

# Gaming-Stack (Pakete stehen in packages.list; hier nur Host-Feinschliff).
extras_gaming() {
  ui_step "Gaming"
  ui_info "Steam/Lutris/gamescope/mangohud kommen aus packages.list"
  ui_info "Heroic/ProtonPlus/lsfg-vk: TODO (chaotic-Pakete ergaenzen)"
}
