#!/usr/bin/env bash
# QEMU-Testumgebung fuer das Installer-ISO.
# Vorbild: test-installer.sh aus dem NixOS-Repo.
#
#   ./test/test-installer.sh iso [ISO-DATEI]   ISO booten (baut nicht selbst)
#   ./test/test-installer.sh clean             Testumgebung loeschen
#
# Ueberschreibbar: DISK_SIZE (Default 40G, sparse), RAM (4G), CPUS (4), SSH_PORT (2222)
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-/tmp/arch-test}"
DISK_SIZE="${DISK_SIZE:-40G}"
RAM="${RAM:-4G}"
CPUS="${CPUS:-4}"
SSH_PORT="${SSH_PORT:-2222}"

die() { echo "FEHLER: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "$1 fehlt"; }

find_iso() {
  local arg="${1:-}"
  if [ -n "$arg" ]; then
    [ -f "$arg" ] || die "ISO nicht gefunden: $arg"
    printf '%s\n' "$arg"; return
  fi
  local iso
  iso="$(ls -1t "$HERE"/../iso/arch/out/*.iso 2>/dev/null | head -1 || true)"
  [ -n "$iso" ] || die "Keine ISO in iso/arch/out – erst bauen oder Pfad angeben"
  printf '%s\n' "$iso"
}

cmd_iso() {
  need qemu-system-x86_64
  local iso; iso="$(find_iso "${1:-}")"

  mkdir -p "$WORK"
  local disk="$WORK/disk.qcow2"
  [ -f "$disk" ] || qemu-img create -f qcow2 "$disk" "$DISK_SIZE" >/dev/null

  local ovmf_args=()
  local ovmf_code
  ovmf_code="$(ls /nix/store/*OVMF*/FV/OVMF_CODE.fd 2>/dev/null | head -1 || true)"
  if [ -n "$ovmf_code" ]; then
    ovmf_args=(-drive "if=pflash,format=raw,readonly=on,file=$ovmf_code")
  else
    echo "Hinweis: kein OVMF gefunden – UEFI-Boot ggf. nicht moeglich" >&2
  fi

  echo "ISO : $iso"
  echo "Disk: $disk ($DISK_SIZE)"
  echo "SSH : localhost:$SSH_PORT (nach Installation)"

  exec qemu-system-x86_64 \
    -enable-kvm -cpu host -smp "$CPUS" -m "$RAM" \
    "${ovmf_args[@]}" \
    -drive "file=$disk,if=virtio" \
    -cdrom "$iso" -boot d \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" -device virtio-net-pci,netdev=net0 \
    -vga virtio -display gtk,gl=on
}

cmd_clean() {
  if [ -d "$WORK" ]; then
    du -sh "$WORK" 2>/dev/null || true
    rm -rf "$WORK"
    echo "geloescht: $WORK"
  else
    echo "nichts zu loeschen ($WORK)"
  fi
}

case "${1:-}" in
  iso) shift; cmd_iso "$@" ;;
  clean) cmd_clean ;;
  *) echo "Usage: $0 {iso [ISO-DATEI]|clean}" >&2; exit 2 ;;
esac
