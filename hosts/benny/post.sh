#!/usr/bin/env bash
# Host-spezifisches Post-Skript (laeuft am Ende von install.sh, als root,
# mit $1 = Ziel-Root).
#
# benny: Was nicht in pacstrap passt - chaotic-Pakete und AUR-Builds.
# Jeder Schritt loggt nur und bricht die Installation NICHT ab.
# Status: VORBEREITET, auf Hardware noch nicht getestet.
set -uo pipefail

TARGET="${1:-/mnt}"
USER_NAME=benny
PROBLEMS=0

log()  { printf '[benny] %s\n' "$*"; }
warn() { printf '[benny] WARNUNG: %s\n' "$*" >&2; PROBLEMS=$((PROBLEMS + 1)); }

pac() { arch-chroot "$TARGET" pacman -S --needed --noconfirm "$@"; }

# --- Cloud-Gaming: Microsoft Edge (chaotic) --------------------------------
if pac microsoft-edge-stable-bin; then
  log "Microsoft Edge installiert (chaotic)"
else
  warn "microsoft-edge-stable-bin nicht installierbar"
fi

# --- AUR-Helfer: Build als benny, Installation als root --------------------
# makepkg verweigert root. Alle Abhaengigkeiten sind aus den Repos
# vorinstalliert, deshalb reicht 'makepkg --nodeps' + 'pacman -U'.
aur_install() {
  local pkg="$1"
  log "AUR: baue $pkg"
  if ! arch-chroot "$TARGET" runuser -u "$USER_NAME" -- \
      env HOME="/home/$USER_NAME" bash -c "
        set -euo pipefail
        rm -rf /tmp/aur-$pkg
        git clone --depth=1 https://aur.archlinux.org/$pkg.git /tmp/aur-$pkg
        cd /tmp/aur-$pkg
        makepkg --noconfirm --nodeps --nocheck
      "; then
    warn "AUR-Build fehlgeschlagen: $pkg"
    return 1
  fi
  if ! arch-chroot "$TARGET" bash -c "pacman -U --noconfirm /tmp/aur-$pkg/*.pkg.tar.zst"; then
    warn "AUR-Installation fehlgeschlagen: $pkg"
    return 1
  fi
  arch-chroot "$TARGET" rm -rf "/tmp/aur-$pkg"
  log "$pkg installiert"
}

# Python-Bindings fuer PulseAudio/PipeWire (chaotic; sonst AUR)
if pac python-pulsectl; then
  log "python-pulsectl installiert (chaotic)"
else
  warn "python-pulsectl nicht in den Repos - versuche AUR"
  aur_install python-pulsectl || warn "python-pulsectl fehlt - ASM startet evtl. nicht"
fi

# --- Arctis Sound Manager (Upstream 1.7.10, enthaelt den echten 7.1-Fix) ---
if aur_install arctis-sound-manager; then
  # User-Units aktivieren: 'systemctl --user enable' geht im chroot nicht,
  # deshalb die Wants-Symlinks direkt anlegen.
  arch-chroot "$TARGET" bash -c '
    set -e
    install -d /etc/systemd/user/graphical-session.target.wants \
               /etc/systemd/user/default.target.wants
    for u in app-ArctisManager arctis-manager; do
      [ -f "/usr/lib/systemd/user/$u.service" ] && \
        ln -sf "/usr/lib/systemd/user/$u.service" \
               "/etc/systemd/user/graphical-session.target.wants/$u.service"
    done
    for u in arctis-stream-guard arctis-video-router; do
      [ -f "/usr/lib/systemd/user/$u.service" ] && \
        ln -sf "/usr/lib/systemd/user/$u.service" \
               "/etc/systemd/user/default.target.wants/$u.service"
    done
  ' || warn "ASM-User-Units nicht aktiviert"
else
  warn "Arctis Sound Manager nicht installiert"
fi

# --- Boosteroid (AUR) ------------------------------------------------------
if pac libva libvdpau libxcb traceroute ocl-icd pcre2 libxi \
       xcb-util-wm xcb-util-image xcb-util-renderutil xcb-util-keysyms \
       fontconfig alsa-lib pulseaudio-alsa; then
  :
else
  warn "Boosteroid-Abhaengigkeiten unvollstaendig"
fi
aur_install boosteroid || warn "Boosteroid nicht installiert"

# --- Ergebnis --------------------------------------------------------------
if [ "$PROBLEMS" -eq 0 ]; then
  log "post.sh fertig - alles installiert"
else
  log "post.sh fertig mit $PROBLEMS Warnung(en) - siehe oben"
fi

# Nie die Installation abbrechen (Post-Schritte sind optional).
exit 0
