# Installer – Entscheidungen und Ablauf

## Grundsatz

- **UEFI only** (kein BIOS-Boot im Zielsystem).
- **btrfs** mit getrennten Subvolumes; Snapper nur auf `/`.
- **GRUB (UEFI)** als Bootloader – wegen `grub-btrfs` (Snapshot-Booteintraege).
  Zusaetzlich `\EFI\BOOT\BOOTX64.EFI` als Fallback ohne NVRAM-Eintrag.
- **Kein LUKS** in v1 (spaeter optional).
- **zram** statt Swap-Partition.
- **Kein Flatpak** im Basissystem; Gaming-Stack nativ.

## Subvolumes

| Subvolume | Mount | Snapper |
|---|---|---|
| `@` | `/` | ✅ (`snapper -c root`) |
| `@home` | `/home` | ❌ |
| `@gaming` | `/gaming` | ❌ (entfaellt bei vorhandener Spiele-Platte) |
| `@snapshots` | `/.snapshots` | – |
| `@var_cache` | `/var/cache` | ❌ |
| `@var_tmp` | `/var/tmp` | ❌ |
| `@var_log` | `/var/log` | ❌ |

Snapper snapshottet nur das Subvolume mit Config – alles separat Gemountete ist
automatisch ausgenommen.

### Vorhandene Spiele-Platte

`install-arch --gaming /dev/nvme1n1` (oder interaktiv, `0` = keine) mountet eine
**bestehende** Platte nach `/gaming` – ohne Formatieren. Dann wird kein
`@gaming`-Subvolume angelegt und der fstab-Eintrag bekommt `nofail`.
Typischer Fall: Spiele-NVMe bleibt ext4 und wird beim Umstieg nur uebernommen.

## Ablauf (install.sh)

1. Vorpruefung: root, UEFI, Profil, Blockgeraet
2. `disk_wipe` (sgdisk, ESP 1G + btrfs) – nur der Ziel-Datentraeger
3. `disk_mkfs` (mkfs, Subvolumes, Mounts)
4. `pacstrap_base` (Basis + `hosts/<host>/packages.list`)
5. `gen_fstab`
6. `configure_base` (Zeitzone, Locale, Tastatur, Hostname, User, sudo, NetworkManager, Host-Configs)
7. `install_boot` (systemd-boot, Loader-Eintrag, mkinitcpio)
8. `install_extras` (Snapshots, NVIDIA, Desktop, Gaming, `post.sh`)
9. `set_passwords`
10. Reboot

## Fehlerverhalten

- `set -Eeuo pipefail`: jeder Fehler bricht ab.
- Destruktive Schritte nur nach `confirm`.
- `--dry-run` prueft Voraussetzungen ohne Aenderungen.

## Testschleife

```bash
./test/test-installer.sh iso [iso-datei]
# im Gast: install-arch --host nex --disk /dev/vda [--gaming /dev/vdb]
./test/test-installer.sh clean
```

Abnahme Phase 0: VM bootet nach der Installation und SSH ist erreichbar.

## Offene Punkte

- Firewall (NixOS hatte `networking.firewall`; auf Arch noch nicht portiert)
- `orca-slicer-bin` (AUR) – nach dem ersten Login per `paru -S` nachziehen

- Hardware-Test auf nex (NVIDIA/PRIME, Umbriel/Noctalia, Greeter-Sync)
- Greeter-Theme-Sync: greift erst nach dem ersten Login (in der VM nicht testbar)
- Drift-Check: `pacman -Qqe` gegen `hosts/<host>/packages.list`
