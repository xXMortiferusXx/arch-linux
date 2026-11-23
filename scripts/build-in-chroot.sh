#!/usr/bin/env bash
# Laeuft INNERHALB des Arch-Bootstrap-Chroots (von scripts/build-iso.sh).
# Erwartet /src (Repo), /build (Profil), /work, /out als Bind-Mounts.
set -Eeuo pipefail

# nspawn erbt die Host-Umgebung (auf NixOS: /nix/store-PATH) -> im Chroot
# sauber setzen, sonst findet pacman seine eigenen Tools nicht.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
unset LD_LIBRARY_PATH LD_PRELOAD 2>/dev/null || true

echo "== pacman-key =="
pacman-key --init
pacman-key --populate archlinux

echo "== System aktualisieren + archiso =="
pacman -Syu --noconfirm --needed
pacman -S --noconfirm --needed archiso syslinux mtools libisoburn

echo "== Profil zusammenbauen (releng + unsere Overrides) =="
rm -rf /build
cp -a /usr/share/archiso/configs/releng /build
cp -a /src/iso/arch/. /build/
rm -f /build/README.md

# Offline-Fallback fuer install-arch
install -Dm644 /src/install.sh /build/airootfs/usr/local/share/install.sh
chmod +x /build/airootfs/usr/local/bin/install-arch

echo "== mkarchiso =="
# mkarchiso merkt sich erledigte Schritte als /work/build.*-Marker und ueberspringt
# sie danach komplett (auch geaenderte Profile!). Fuer reproduzierbare Builds
# daher das Arbeitsverzeichnis leeren.
rm -rf -- /work/*
mkarchiso -v -w /work -o /out /build

echo "== Ergebnis =="
ls -lh /out
