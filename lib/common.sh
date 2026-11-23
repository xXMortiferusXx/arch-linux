#!/usr/bin/env bash
# Gemeinsame Helfer: Ausgabe, Abbrueche, Checks.
# Wird von install.sh gesourct (nicht direkt ausfuehren).

# shellcheck shell=bash

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
  C_ACC=$'\033[38;5;39m'; C_OK=$'\033[38;5;42m'; C_WRN=$'\033[38;5;214m'
  C_ERR=$'\033[38;5;203m'; C_DIM=$'\033[38;5;245m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
  C_ACC=""; C_OK=""; C_WRN=""; C_ERR=""; C_DIM=""; C_BLD=""; C_RST=""
fi

ui_title() { printf '\n%s%s%s\n' "$C_BLD$C_ACC" "$1" "$C_RST"; printf '%s' "$C_DIM"; printf '%.0s─' $(seq 1 52); printf '%s\n' "$C_RST"; }
ui_rule()  { printf '%s' "$C_DIM"; printf '%.0s─' $(seq 1 52); printf '%s\n' "$C_RST"; }
ui_step()  { printf '\n%s▸%s %s%s%s\n' "$C_ACC" "$C_RST" "$C_BLD" "$1" "$C_RST"; }
ui_kv()    { printf '  %s%-10s%s %s\n' "$C_DIM" "$1" "$C_RST" "$2"; }
ui_ok()    { printf '  %s✔%s %s\n' "$C_OK" "$C_RST" "$1"; }
ui_warn()  { printf '  %s▲%s %s\n' "$C_WRN" "$C_RST" "$1"; }
ui_err()   { printf '  %s✖%s %s\n' "$C_ERR" "$C_RST" "$1" >&2; }
ui_info()  { printf '  %s•%s %s\n' "$C_DIM" "$C_RST" "$1"; }

die() { ui_err "$*"; exit 1; }

confirm() {
  local answer
  printf '  %s?%s %s [j/N] ' "$C_WRN" "$C_RST" "$1"
  read -r answer
  case "$answer" in
    j|J|ja|Ja|y|Y|yes) return 0 ;;
    *) die "Abgebrochen" ;;
  esac
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Bitte als root ausfuehren (Live-ISO: root-Shell)"
}

require_uefi() {
  [ -d /sys/firmware/efi ] || die "Kein UEFI-System (nur UEFI wird unterstuetzt)"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Benoetigtes Kommando fehlt: $1"
}

# Wartet, bis ein Geraet nicht mehr busy ist (nach Wipe/Mount).
wait_unbusy() {
  local dev="$1" i
  for i in $(seq 1 20); do
    if ! fuser -s "$dev" 2>/dev/null; then return 0; fi
    sleep 0.5
  done
  die "Geraet ist belegt: $dev"
}
