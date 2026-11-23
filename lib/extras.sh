#!/usr/bin/env bash
# Host-Extras: Snapshots, NVIDIA/PRIME, Desktop (Umbriel/Noctalia), Gaming.
# Aktuell Geruest: die Funktionen sind bewusst noch leer, damit Phase 0
# (bootet + SSH) unabhaengig von Phase 2-4 getestet werden kann.
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
}

# snapper nur fuer @ (System), nicht /home oder /gaming.
extras_snapshots() {
  ui_info "Snapshots: snapper + snap-pac (TODO Phase 4)"
  # arch-chroot "$TARGET" pacman -S --needed --noconfirm snapper snap-pac
  # arch-chroot "$TARGET" snapper -c root create-config /
  #   -> NUMBER_LIMIT setzen, TIMELINE_CREATE=no
}

# NVIDIA-Repo + PRIME/Dynamic Boost (TODO Phase 2).
extras_nvidia() {
  ui_info "NVIDIA/PRIME (TODO Phase 2)"
  # pacman -S nvidia-open-dkms nvidia-prime nvidia-utils libva-nvidia-driver
  # /etc/nvidia/nvidia-application-profiles-rc.d/50-vram-fix.json
  # /etc/environment: __GL_VRR_ALLOWED, LIBVA_DRIVER_NAME=radeonsi ...
}

# Umbriel + Noctalia + Greeter via chaotic-aur, greetd-Session (TODO Phase 3).
extras_desktop() {
  ui_info "Desktop Umbriel/Noctalia/Greeter (TODO Phase 3)"
  # pacman -S greetd
  # chaotic: umbriel-git noctalia-git noctalia-greeter-git xdg-desktop-portal-umbriel-git
  # /etc/greetd/config.toml + Greeter-TOML
}

# Steam/Proton/Lutris/Heroic/ProtonPlus/gamescope/mangohud (TODO Phase 4).
extras_gaming() {
  ui_info "Gaming-Stack (TODO Phase 4)"
  # pacman -S steam lutris gamescope mangohud gamemode
  # chaotic: heroic-games-launcher-bin protonplus lsfg-vk-git
}
