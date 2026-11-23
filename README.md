# arch-linux

Arch-Linux-Port der NixOS-Konfiguration (`xXMortiferusXx/nix-config`).
Ziel: derselbe Komfort – Installer-ISO mit `install-arch`, Host-Profile,
lauter Abbruch bei Fehlern – aber mit nativen Arch-Paketen (offizielle Repos +
chaotic-aur) statt Nix.

## Status

Gerüst (Phase 0). Der Installer ist noch nicht lauffähig; die Dateien sind
Absicht und Struktur, keine fertige Implementierung.

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
install-arch                # holt install.sh aus main, zeigt Version + SHA256
install-arch --host nex --disk /dev/nvme0n1
```

## Konventionen

- `install.sh` bricht bei jedem Fehler ab (`set -Eeuo pipefail`) – nie halb installiert weiterlaufen.
- Destruktive Schritte verlangen eine ausdrückliche Bestätigung.
- Host-Profile liegen unter `hosts/<name>/`; alles Hostspezifische gehört dorthin, nicht in `lib/`.
- Kein Flatpak-Zwang: Gaming-Stack nativ (Arch-Repos + chaotic-aur).
