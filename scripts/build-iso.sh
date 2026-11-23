#!/usr/bin/env bash
# Baut das Installer-ISO auf einem beliebigen Linux (auch NixOS), ohne dass
# Arch installiert sein muss: offizieller Arch-Bootstrap -> systemd-nspawn ->
# mkarchiso. Ergebnis landet in iso/arch/out/.
#
#   sudo ./scripts/build-iso.sh            # baut
#   sudo ./scripts/build-iso.sh --clean    # Build-Verzeichnis loeschen
#
# Voraussetzungen: curl, tar, systemd-nspawn, ~5 GB Platz in BUILD_DIR.
set -Eeuo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/archiso-build}"
BOOTSTRAP_URL="${BOOTSTRAP_URL:-https://geo.mirror.pkgbuild.com/iso/latest/archlinux-bootstrap-x86_64.tar.zst}"
OUT_DIR="$REPO/iso/arch/out"

die() { echo "FEHLER: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Bitte als root (sudo) ausfuehren"
command -v systemd-nspawn >/dev/null || die "systemd-nspawn fehlt"

if [ "${1:-}" = "--clean" ]; then
  rm -rf "$BUILD_DIR"
  echo "geloescht: $BUILD_DIR"
  exit 0
fi

mkdir -p "$BUILD_DIR"/{out,work}
mkdir -p "$OUT_DIR"

# 1) Bootstrap holen und entpacken
cd "$BUILD_DIR"
if [ ! -f archlinux-bootstrap-x86_64.tar.zst ]; then
  echo "== Bootstrap laden =="
  curl -fsSL --retry 3 -o archlinux-bootstrap-x86_64.tar.zst "$BOOTSTRAP_URL"
fi
rm -rf root.x86_64
echo "== Bootstrap entpacken =="
tar --numeric-owner -xf archlinux-bootstrap-x86_64.tar.zst
cp /etc/resolv.conf root.x86_64/etc/resolv.conf

# Der Bootstrap bringt eine leere mirrorlist mit -> sonst "no servers configured".
cat > root.x86_64/etc/pacman.d/mirrorlist <<'MIRRORS'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://archlinux.thaller.ws/$repo/os/$arch
MIRRORS

# 2) Repo-Stand als Quelle einhaengen
rm -rf "$BUILD_DIR/src"
mkdir -p "$BUILD_DIR/src"
rsync -a --delete --exclude=iso/arch/out/ --exclude=.git/ "$REPO/" "$BUILD_DIR/src/"

# Alte ISOs aus dem Build-Ausgang entfernen (sonst werden sie mitkopiert)
rm -f "$BUILD_DIR"/out/*.iso "$BUILD_DIR"/out/*.iso.sha256

# 3) Im Chroot bauen
echo "== mkarchiso (nspawn) =="
# nspawn kennt kein --privileged (das ist podman/docker); mkarchiso braucht
# aber volle Capabilities (mount/loop/mksquashfs).
systemd-nspawn -D "$BUILD_DIR/root.x86_64" --capability=all \
  --bind="$BUILD_DIR/out:/out" \
  --bind="$BUILD_DIR/work:/work" \
  --bind="$BUILD_DIR/src:/src" \
  --bind="$REPO/scripts/build-in-chroot.sh:/build-in-chroot.sh" \
  -- /bin/bash /build-in-chroot.sh

# 4) ISO + Pruefsumme nach iso/arch/out
shopt -s nullglob
isos=("$BUILD_DIR"/out/*.iso)
[ ${#isos[@]} -gt 0 ] || die "kein ISO erzeugt"
for iso in "${isos[@]}"; do
  cp -f "$iso" "$OUT_DIR/"
  ( cd "$OUT_DIR" && sha256sum "$(basename "$iso")" > "$(basename "$iso").sha256" )
  echo "fertig: $OUT_DIR/$(basename "$iso")"
done
