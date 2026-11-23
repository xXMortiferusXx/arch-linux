#!/usr/bin/env bash
# QEMU-Testumgebung fuer das Installer-ISO.
# Vorbild: test-installer.sh aus dem NixOS-Repo.
#
#   ./test/test-installer.sh iso [ISO-DATEI]   ISO booten (baut nicht selbst)
#   ./test/test-installer.sh clean             Testumgebung loeschen
#
# Ueberschreibbar: DISK_SIZE (Default 40G, sparse), RAM (4G), CPUS (4), SSH_PORT (2222)
set -Eeuo pipefail

# Original-Argumente merken: ensure_qemu re-execs das Skript.
ORIG_ARGS=("$@")

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK="${WORK:-/tmp/arch-test}"
DISK_SIZE="${DISK_SIZE:-40G}"
RAM="${RAM:-4G}"
CPUS="${CPUS:-4}"
SSH_PORT="${SSH_PORT:-2222}"

die() { echo "FEHLER: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "$1 fehlt"; }

# qemu ist auf NixOS nicht zwingend installiert -> bei Bedarf aus nixpkgs holen.
ensure_qemu() {
  if command -v qemu-system-x86_64 >/dev/null 2>&1 && command -v qemu-img >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "${ARCH_TEST_IN_NIX_SHELL:-}" ]; then
    die "qemu-system-x86_64 fehlt auch im nix shell"
  fi
  command -v nix >/dev/null 2>&1 || die "qemu fehlt und nix ist nicht verfuegbar"
  echo "qemu fehlt – starte ueber 'nix shell nixpkgs#qemu_full' (einmaliger Download)"
  export ARCH_TEST_IN_NIX_SHELL=1
  exec nix shell nixpkgs#qemu_full -c "$0" "${ORIG_ARGS[@]}"
}

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
  ensure_qemu
  need qemu-system-x86_64
  local iso; iso="$(find_iso "${1:-}")"

  mkdir -p "$WORK"
  local disk="$WORK/disk.qcow2"
  [ -f "$disk" ] || qemu-img create -f qcow2 "$disk" "$DISK_SIZE" >/dev/null

  local ovmf_args=()
  local ovmf_code ovmf_vars
  ovmf_code="$(ls /nix/store/*OVMF*/FV/OVMF_CODE.fd 2>/dev/null | head -1 || true)"
  if [ -z "$ovmf_code" ] && command -v nix >/dev/null 2>&1; then
    echo "OVMF fehlt im Store – baue nixpkgs#OVMF.fd (einmalig)"
    local ovmf_dir
    ovmf_dir="$(nix build --no-link --print-out-paths nixpkgs#OVMF.fd 2>/dev/null | tail -1 || true)"
    [ -n "$ovmf_dir" ] && ovmf_code="$ovmf_dir/FV/OVMF_CODE.fd"
  fi
  if [ -n "$ovmf_code" ]; then
    ovmf_vars="$WORK/OVMF_VARS.fd"
    # Immer frische NVRAM: sonst bleiben PXE-Booteintraege aus Fehlversuchen
    # in der Boot-Order haengen.
    rm -f "$ovmf_vars"
    cp "$(dirname "$ovmf_code")/OVMF_VARS.fd" "$ovmf_vars"
    chmod u+w "$ovmf_vars"   # Store-Datei ist read-only, QEMU braucht Schreibzugriff
    ovmf_args=(
      -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
      -drive "if=pflash,format=raw,file=$ovmf_vars"
    )
  else
    echo "Hinweis: kein OVMF gefunden – Boot im BIOS-Modus (syslinux)" >&2
  fi

  echo "ISO : $iso"
  echo "Disk: $disk ($DISK_SIZE)"
  echo "SSH : localhost:$SSH_PORT (nach Installation)"

  exec qemu-system-x86_64 \
    -machine q35 -enable-kvm -cpu host -smp "$CPUS" -m "$RAM" \
    "${ovmf_args[@]}" \
    -drive "file=$disk,if=virtio" \
    -cdrom "$iso" -boot d \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" -device virtio-net-pci,netdev=net0 \
    -vga std -display gtk
}

# Installiertes System booten (ohne ISO/CD, damit die Platte bootet)
cmd_boot() {
  ensure_qemu
  need qemu-system-x86_64
  local disk="$WORK/disk.qcow2"
  [ -f "$disk" ] || die "Kein Disk-Image ($disk) – erst installieren"

  local ovmf_args=()
  local ovmf_code
  ovmf_code="$(ls /nix/store/*OVMF*/FV/OVMF_CODE.fd 2>/dev/null | head -1 || true)"
  if [ -n "$ovmf_code" ]; then
    local ovmf_vars="$WORK/OVMF_VARS.fd"
    rm -f "$ovmf_vars"
    cp "$(dirname "$ovmf_code")/OVMF_VARS.fd" "$ovmf_vars"
    chmod u+w "$ovmf_vars"
    ovmf_args=(
      -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
      -drive "if=pflash,format=raw,file=$ovmf_vars"
    )
  fi

  echo "Boote installiertes System: $disk"
  exec qemu-system-x86_64 \
    -machine q35 -enable-kvm -cpu host -smp "$CPUS" -m "$RAM" \
    "${ovmf_args[@]}" \
    -drive "file=$disk,if=virtio" \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" -device virtio-net-pci,netdev=net0 \
    -vga std -display gtk
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
  boot) cmd_boot ;;
  clean) cmd_clean ;;
  *) echo "Usage: $0 {iso [ISO-DATEI]|boot|clean}" >&2; exit 2 ;;
esac
