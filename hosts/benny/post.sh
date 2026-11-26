#!/usr/bin/env bash
# Host-spezifisches Post-Skript (laeuft am Ende von install.sh, als root,
# mit $1 = Ziel-Root).
#
# benny: Was nicht in pacstrap passt - chaotic-Pakete und AUR-Builds.
# Jeder Schritt loggt nur und bricht die Installation NICHT ab.
# Status: VORBEREITET, auf Hardware noch nicht getestet.
set -uo pipefail

TARGET="${1:-/mnt}"
# arch-chroot kann /tmp ueberdecken -> Builds liegen unter /var/tmp (persistent)
REPO_DIR="$(cd "${2:-.}" 2>/dev/null && pwd || printf '%s' "${2:-.}")"
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
  arch-chroot "$TARGET" rm -rf "/var/tmp/aur-$pkg"
  if ! arch-chroot "$TARGET" runuser -u "$USER_NAME" -- \
      env HOME="/home/$USER_NAME" bash -c "
        set -euo pipefail
        git clone --depth=1 https://aur.archlinux.org/$pkg.git /var/tmp/aur-$pkg
        cd /var/tmp/aur-$pkg
        makepkg --noconfirm --nodeps --nocheck
      "; then
    warn "AUR-Build fehlgeschlagen: $pkg"
    return 1
  fi
  if ! arch-chroot "$TARGET" bash -c "pacman -U --noconfirm /var/tmp/aur-$pkg/*.pkg.tar.zst"; then
    warn "AUR-Installation fehlgeschlagen: $pkg"
    return 1
  fi
  arch-chroot "$TARGET" rm -rf "/var/tmp/aur-$pkg"
  log "$pkg installiert"
}

# Baut ein lokales PKGBUILD (Kopie aus dem Repo) als benny.
local_pkgbuild_install() {
  local src="$1" name
  name="$(basename "$src")"
  if [ ! -d "$src" ]; then
    warn "PKGBUILD-Verzeichnis fehlt: $src"
    return 1
  fi
  src="$(cd "$src" && pwd)" || { warn "PKGBUILD-Pfad unlesbar: $1"; return 1; }
  arch-chroot "$TARGET" rm -rf "/var/tmp/build-$name"
  install -d -m 1777 "$TARGET/var/tmp"
  cp -a "$src" "$TARGET/var/tmp/build-$name"
  if [ ! -d "$TARGET/var/tmp/build-$name" ]; then
    warn "Kopie des PKGBUILD fehlgeschlagen: $name"
    return 1
  fi
  arch-chroot "$TARGET" chown -R "$USER_NAME:$USER_NAME" "/var/tmp/build-$name"
  log "PKGBUILD: baue $name"
  if ! arch-chroot "$TARGET" runuser -u "$USER_NAME" -- \
      env HOME="/home/$USER_NAME" bash -c "
        set -euo pipefail
        cd /var/tmp/build-$name
        makepkg --noconfirm --nodeps --nocheck
      "; then
    warn "Build fehlgeschlagen: $name"
    return 1
  fi
  if ! arch-chroot "$TARGET" bash -c "pacman -U --noconfirm /var/tmp/build-$name/*.pkg.tar.zst"; then
    warn "Installation fehlgeschlagen: $name"
    return 1
  fi
  arch-chroot "$TARGET" rm -rf "/var/tmp/build-$name"
  log "$name installiert"
}

# ASM-User-Units aktivieren (kein User-Bus im chroot -> Wants-Symlinks)
asm_units_enable() {
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
}

# ASM-Abhaengigkeit, die nicht in den offiziellen Repos liegt.
asm_deps() {
  if pac python-pulsectl; then
    log "python-pulsectl installiert (chaotic)"
  else
    warn "python-pulsectl nicht in den Repos - versuche AUR"
    aur_install python-pulsectl || warn "python-pulsectl fehlt - ASM startet evtl. nicht"
  fi
}

# --- Arctis Sound Manager -------------------------------------------------
# Standard: Fork (bewaehrt mit GameDAC Gen1). Umschalten ueber ASM_FLAVOR
# in hosts/benny/settings.env: fork | upstream | none.
ASM_FLAVOR="${ASM_FLAVOR:-fork}"
case "$ASM_FLAVOR" in
  none)
    log "ASM: uebersprungen (ASM_FLAVOR=none)"
    ;;
  upstream)
    log "ASM: Upstream 1.7.10 aus der AUR"
    asm_deps
    if aur_install arctis-sound-manager; then
      asm_units_enable
    else
      warn "Arctis Sound Manager (upstream) nicht installiert"
    fi
    ;;
  fork)
    log "ASM: Fork 1.4.27+fork.3 (lokales PKGBUILD)"
    asm_deps
    if local_pkgbuild_install \
        "$REPO_DIR/hosts/benny/pkgbuilds/arctis-sound-manager-fork"; then
      asm_units_enable
    else
      warn "Arctis Sound Manager (Fork) nicht installiert"
    fi
    ;;
  *)
    warn "Unbekanntes ASM_FLAVOR '$ASM_FLAVOR' (erlaubt: fork|upstream|none)"
    ;;
esac

# --- Boosteroid (AUR) ------------------------------------------------------
if pac libva libvdpau libxcb traceroute ocl-icd pcre2 libxi \
       xcb-util-wm xcb-util-image xcb-util-renderutil xcb-util-keysyms \
       fontconfig alsa-lib pulseaudio-alsa; then
  :
else
  warn "Boosteroid-Abhaengigkeiten unvollstaendig"
fi
aur_install boosteroid || warn "Boosteroid nicht installiert"
# Das Paket liefert nur 1.10.24. Der Client aktualisiert sich aber nur aus
# $HOME (die Paket-Binary unter /usr/bin ist root-eigen). Deshalb die aktuelle
# Version als Benutzer dort ablegen; der Starter /usr/local/bin/boosteroid
# bevorzugt diese Kopie.
bst_dir="/home/$USER_NAME/.local/share/Boosteroid Games S.R.L./Boosteroid"
if arch-chroot "$TARGET" runuser -u "$USER_NAME" -- bash -c "
      set -e
      mkdir -p \"$bst_dir\"
      curl -fsSL -A Mozilla -o /var/tmp/boosteroid.tar https://boosteroid.com/linux/installer/latest/boosteroid.tar
      tar -xOf /var/tmp/boosteroid.tar Boosteroid > \"$bst_dir/Boosteroid.new\"
      chmod 755 \"$bst_dir/Boosteroid.new\"
      mv -f \"$bst_dir/Boosteroid.new\" \"$bst_dir/Boosteroid\"
      rm -f /var/tmp/boosteroid.tar
    "; then
  log "Boosteroid aktuelle Version nach \$HOME kopiert"
else
  warn "Boosteroid-Kopie in \$HOME fehlgeschlagen"
fi
aur_install heroic-games-launcher-bin || warn "Heroic nicht installiert"
aur_install naps2-bin || warn "NAPS2 nicht installiert"
aur_install ookla-speedtest-bin || warn "Ookla-Speedtest nicht installiert"

# --- Ergebnis --------------------------------------------------------------
if [ "$PROBLEMS" -eq 0 ]; then
  log "post.sh fertig - alles installiert"
else
  log "post.sh fertig mit $PROBLEMS Warnung(en) - siehe oben"
fi

# Nie die Installation abbrechen (Post-Schritte sind optional).
exit 0
