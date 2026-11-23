#!/usr/bin/env bash
# Arch-Installer – Pendant zu install.sh im NixOS-Repo.
# Ablauf: Host-Profil laden -> wipen -> pacstrap -> Basis -> Boot -> Extras.
# Bricht bei jedem Fehler ab (set -Eeuo pipefail); keine halben Installationen.
set -Eeuo pipefail

SCRIPT_VERSION="2026-11-23.1"
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

HOST=""
DISK=""
DRY_RUN=0
ASSUME_YES=0

usage() {
  cat <<EOF
Arch-Installer ${SCRIPT_VERSION}

  --host <name>    Host-Profil aus hosts/<name> (z. B. nex)
  --disk <dev>     Ziel-Datentraeger (wird KOMPLETT geloescht, z. B. /dev/nvme0n1)
  --yes            Rueckfragen ueberspringen (nur fuer Tests)
  --dry-run        Nur pruefen, nichts veraendern
  -h, --help       Diese Hilfe

Beispiel:
  ./install.sh --host nex --disk /dev/nvme0n1
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --disk) DISK="${2:-}"; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unbekannte Option: $1" >&2; usage; exit 2 ;;
  esac
done

# shellcheck source=lib/common.sh
. "$REPO_DIR/lib/common.sh"

require_root
require_uefi

# --- Host waehlen (falls nicht per --host) --------------------------------
pick_host() {
  local hosts=() d
  for d in "$REPO_DIR"/hosts/*/; do
    [ -d "$d" ] && hosts+=("$(basename "$d")")
  done
  [ "${#hosts[@]}" -gt 0 ] || die "keine Host-Profile unter hosts/"

  ui_title "Host waehlen"
  local i=1 h
  for h in "${hosts[@]}"; do
    printf '  %2d) %s\n' "$i" "$h"
    i=$((i + 1))
  done
  printf '\n  Auswahl [1-%d]: ' "${#hosts[@]}"
  read -r n
  case "$n" in ''|*[!0-9]*) die "ungueltige Auswahl" ;; esac
  [ "$n" -ge 1 ] && [ "$n" -le "${#hosts[@]}" ] || die "ungueltige Auswahl"
  HOST="${hosts[$((n - 1))]}"
}

# --- Ziel-Datentraeger waehlen (falls nicht per --disk) -------------------
pick_disk() {
  local devs=() names=() sizes=() models=() name size model tran
  while read -r name size model tran; do
    [ -n "$name" ] || continue
    case "$name" in
      zram*|loop*|sr*|ram*) continue ;;
    esac
    devs+=("/dev/$name"); names+=("$name"); sizes+=("$size"); models+=("$model")
  done < <(lsblk -dn -o NAME,SIZE,MODEL,TRAN | awk '{tran=$NF; $NF=""; model=""; for(i=3;i<=NF;i++) model=model (i>3?" ":"") $i; print $1, $2, model, tran}')

  [ "${#devs[@]}" -gt 0 ] || die "keine Datentraeger gefunden"

  ui_title "Ziel-Datentraeger waehlen (wird KOMPLETT geloescht)"
  local i
  for i in "${!devs[@]}"; do
    printf '  %2d) %-12s %8s  %s\n' "$((i + 1))" "${devs[$i]}" "${sizes[$i]}" "${models[$i]}"
  done
  printf '\n  Auswahl [1-%d]: ' "${#devs[@]}"
  read -r n
  case "$n" in ''|*[!0-9]*) die "ungueltige Auswahl" ;; esac
  [ "$n" -ge 1 ] && [ "$n" -le "${#devs[@]}" ] || die "ungueltige Auswahl"
  DISK="${devs[$((n - 1))]}"
}

[ -n "$HOST" ] || pick_host
[ -n "$DISK" ] || pick_disk

PROFILE="$REPO_DIR/hosts/$HOST"
[ -d "$PROFILE" ] || die "Host-Profil nicht gefunden: $PROFILE"
[ -f "$PROFILE/packages.list" ] || die "Paketliste fehlt: $PROFILE/packages.list"
[ -b "$DISK" ] || die "Kein Blockgeraet: $DISK"

# shellcheck source=lib/disk.sh
. "$REPO_DIR/lib/disk.sh"
# shellcheck source=lib/base.sh
. "$REPO_DIR/lib/base.sh"
# shellcheck source=lib/boot.sh
. "$REPO_DIR/lib/boot.sh"
# shellcheck source=lib/extras.sh
. "$REPO_DIR/lib/extras.sh"

TARGET=/mnt

ui_title "Arch-Installer ${SCRIPT_VERSION}"
ui_kv "Host" "$HOST"
ui_kv "Ziel" "$DISK"
ui_kv "Profil" "$PROFILE"
[ "$DRY_RUN" = 1 ] && ui_warn "DRY-RUN: es wird nichts veraendert"

if [ "$DRY_RUN" = 0 ] && [ "$ASSUME_YES" = 0 ]; then
  confirm "Datentraeger $DISK wird KOMPLETT geloescht. Fortfahren?"
fi

if [ "$DRY_RUN" = 1 ]; then
  ui_ok "Vorpruefung ok (root, UEFI, Profil, Blockgeraet)"
  exit 0
fi

# --- Phasen ---------------------------------------------------------------
ui_step "Partitionieren"
disk_wipe "$DISK"

ui_step "Dateisystem + Subvolumes"
disk_mkfs "$DISK"

ui_step "Basis-System (pacstrap)"
pacstrap_base "$PROFILE/packages.list"

ui_step "fstab"
gen_fstab

ui_step "Grundkonfiguration"
configure_base "$HOST" "$PROFILE"

ui_step "Bootloader"
install_boot "$DISK" "$PROFILE"

ui_step "Extras (NVIDIA, Desktop, Snapshots)"
install_extras "$PROFILE"

ui_step "Passwoerter"
set_passwords

ui_rule
ui_ok "Installation fertig – Reboot und pruefen"
