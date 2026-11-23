# arch-linux

Arch-Linux-Port der NixOS-Konfiguration (`xXMortiferusXx/nix-config`).
Ziel: derselbe Komfort – Installer-ISO mit `install-arch`, Host-Profile,
lauter Abbruch bei Fehlern – aber mit nativen Arch-Paketen (offizielle Repos,
chaotic-aur, LizardByte) statt Nix.

## Status

Der Installer laeuft in QEMU durch: Partitionierung, btrfs-Subvolumes, pacstrap,
GRUB (UEFI) mit Snapshot-Booteintraegen, Host- und Home-Configs, greetd.
Ungetestet ist nur, was echte Hardware braucht (NVIDIA/PRIME, Desktop-Laufzeit).

## Struktur

```
install.sh              Einstiegspunkt (läuft auf der Live-ISO)
lib/                    Installer-Bibliothek (disk, base, boot, extras)
hosts/<name>/           Paketliste + Config-Snippets pro Host
iso/arch/               archiso-Profil (nmtui, install-arch, de-Tastatur)
test/test-installer.sh  QEMU-Testumgebung
docs/                   Entscheidungen und Portierungsnotizen
```

## Benutzung (geplant)

```bash
# auf der Live-ISO
install-arch                # fragt Host-Profil und Ziel-Datentraeger ab
install-arch --host nex --disk /dev/nvme0n1   # nicht-interaktiv
```

## Konventionen

- `install.sh` bricht bei jedem Fehler ab (`set -Eeuo pipefail`) – nie halb installiert weiterlaufen.
- Destruktive Schritte verlangen eine ausdrückliche Bestätigung.
- Host-Profile liegen unter `hosts/<name>/`; alles Hostspezifische gehört dorthin, nicht in `lib/`.
- Kein Flatpak-Zwang: Gaming-Stack nativ (Arch-Repos, chaotic-aur, LizardByte).
