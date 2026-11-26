# arch-linux

Arch-Linux-Port der NixOS-Konfiguration (`xXMortiferusXx/nix-config`).
Ziel: derselbe Komfort – Installer-ISO mit `install-arch`, Host-Profile,
Abbruch bei jedem Fehler – aber mit nativen Arch-Paketen (offizielle Repos,
chaotic-aur, LizardByte) statt Nix.

## Hosts

| Host | Hardware | Status |
|---|---|---|
| `nex` | Legion 5, Ryzen 5 5600H + RTX 3070 Mobile | installiert, im Einsatz |
| `lion-pc` | Ryzen 5 1500X + Radeon RX 590, SATA-SSD | installiert, im Einsatz |
| `benny` | Intel i5-3xxx (Ivy Bridge), Arctis GameDAC | in QEMU getestet, Installation offen |

Details pro Host: `docs/STATUS.md` §6, für benny zusätzlich
`hosts/benny/README.md`.

## Installer-ISO

Aktuelle ISO (stabiler Link, wird pro Build ersetzt):

```
https://github.com/xXMortiferusXx/arch-linux/releases/download/iso-latest/arch-install-latest.iso
https://github.com/xXMortiferusXx/arch-linux/releases/download/iso-latest/arch-install-latest.iso.sha256
```

Prüfen:

```bash
sha256sum arch-install-latest.iso
```

Auf USB schreiben (Ventoy oder `dd`), booten, dann:

```bash
nmtui            # WLAN (falls nötig)
install-arch     # fragt Host-Profil und Ziel-Datenträger ab
```

Nicht-interaktiv:

```bash
install-arch --host nex --disk /dev/nvme0n1
install-arch --host lion-pc --disk /dev/nvme0n1 --gaming /dev/sda1
install-arch --host benny --disk /dev/sda
```

`--gaming` bindet eine vorhandene Spiele-Platte ein, ohne sie zu formatieren.

Das Live-System holt das Repo von GitHub `main` (SHA256 wird angezeigt).
Die ISO enthält zusätzlich eine eingebettete Repo-Kopie als Offline-Fallback.

## Was der Installer macht

- GPT + ESP (1 GB) + btrfs mit Subvolumes (`@`, `@home`, `@snapshots`,
  `@var_*`, optional `@gaming`)
- Snapper, `grub-btrfs` (Snapshot-Booteinträge), scrub/balance/fstrim-Timer
- GRUB (UEFI) mit Theme und Fallback-Eintrag
- Desktop: Umbriel + Noctalia (+ Greeter), XDG-Portale, Keyring
- Gaming: Steam, Gamescope, MangoHud, Lutris/Heroic, ProtonPlus (hostabhängig)
- Audio: PipeWire/WirePlumber, Host-Sonderfälle (GC7, GameDAC)
- Flatpak + Bazaar nur auf Hosts mit `FLATPAK=1`
- Host-Configs aus `hosts/<name>/config/` und `home/` (überschreiben `shared/`)
- `hosts/<name>/post.sh` für Dinge, die kein Paket/Config sind
  (chaotic-Pakete, AUR-Builds, z. B. Arctis Sound Manager für benny)

## Sicherheit & Rollback (Snapper)

NixOS kennt atomare Generationen und Rollback per Boot-Menü. Der Arch-Port
bildet das mit **btrfs + snapper** nach:

- **snap-pac** legt bei **jedem `pacman`-Lauf** (Install, Update, Remove)
  ein **Pre/Post-Snapshot-Paar** an – analog zu einer neuen Generation.
- **snapper** läuft auf `/` (Subvolumen `@`): `NUMBER_LIMIT=10`,
  `NUMBER_LIMIT_IMPORTANT=5`, Timeline aus, `snapper-cleanup.timer` aktiv.
- **grub-btrfs** + `snapper-support` hängen die Snapshots als
  **Booteinträge ins GRUB-Menü** (schreibgeschützt bootbar). Aktiv ist nur
  `grub-btrfsd.service`; `grub-btrfs-snapper.path` bleibt aus, weil beide
  dieselbe Datei schreiben und sich gegenseitig überholen (siehe
  `docs/arch-fix.md` §12).
- Mitglieder der Gruppe `wheel` dürfen Snapshots ohne `sudo` auflisten
  (`ALLOW_GROUPS="wheel"`).

Zurückrollen:

```bash
snapper -c root list                 # Snapshots ansehen (geht als wheel-User)
# Variante A: im GRUB-Menü den Snapshot booten, prüfen, dann:
sudo snapper -c root rollback <N>    # Snapshot wird neuer Standard
sudo reboot
# Variante B: nur Dateien zurücknehmen (ohne Neustart):
sudo snapper -c root undo <N>
```

Bewusste Grenzen:

- Gesichert wird **nur `/`**. `/home`, `/gaming` und `/var/*` sind eigene
  Subvolumes und bleiben bei einem Rollback unangetastet.
- Snapshots sind **kein Backup** – sie liegen auf derselben Platte. Für Daten
  gilt weiterhin ein echtes Backup (z. B. das Lion-Home-Backup auf `nex`).

Damit ist der NixOS-Effekt da: Ein kaputtes Update lässt sich auf den Stand
davor zurückdrehen, inklusive Boot über den Snapshot im GRUB-Menü.

## Config-Stand einspielen (`apply-config`)

Die verwalteten Systemdateien (`shared/config`, `hosts/<host>/config`) lassen
sich auf einem **laufenden** System abgleichen – ohne Neuinstallation:

```bash
cd ~/arch-linux && git pull --ff-only
./bin/apply-config --list        # verwaltete Pfade
./bin/apply-config --verify      # nur prüfen (Exit 1 bei Abweichung)
./bin/apply-config --dry-run     # Änderungen + unified diff
sudo ./bin/apply-config          # anwenden
sudo ./bin/apply-config --status # Repo-HEAD vs. zuletzt angewendetem Stand
sudo ./bin/apply-config --restore last   # letzten Apply zurückrollen
```

- Geschrieben werden nur Dateien unter `/etc`, `/usr/local` und `/usr/share`;
  `hosts/<host>/config` gewinnt über `shared/config`.
- **Es wird nie etwas gelöscht.** Fremde/App-eigene Dateien bleiben unberührt.
- Vor jedem Schreiben: `tar.gz` der **überschriebenen** Dateien unter
  `/var/backups/arch-config/`; aufgeräumt beim nächsten Apply
  (10 Backups / 90 Tage, kein Timer).
- Kein `/boot`, keine Kernel-Cmdline, keine Pakete, keine Benutzerverwaltung.
  `daemon-reload` läuft automatisch, Dienste werden **nicht** neu gestartet.
- **Home:** nur ausdrücklich deklarierte Pfade (`HOME_PREFIXES` im Skript),
  aktuell `~/.config/umbriel/` – damit Umbriel-/Noctalia-Fixes nach einem
  Umbriel-Update verteilt werden können. Alles andere im Home bleibt unberührt.
- **Rechte** werden mitverwaltet (Modus aus dem Repo), damit z. B. 775/664 aus
  alten Installationen auf 755/644 korrigiert werden.

Ohne Repo-Checkout (lion-pc, benny) gibt es `arch-apply`: es holt `main` und
ruft `apply-config` darauf auf.

```bash
sudo arch-apply --verify
sudo arch-apply
```

## Struktur

```
install.sh              Einstiegspunkt (läuft auf der Live-ISO)
lib/                    Installer-Bibliothek (disk, base, boot, extras, common)
shared/                 gemeinsame Pakete, Configs und Home-Dotfiles
hosts/<name>/           Profil: settings.env, packages.list, config/, home/,
                        kernel-cmdline, authorized_keys, post.sh, pkgbuilds/
iso/arch/               archiso-Profil (install-arch, nmtui, de-Tastatur)
test/test-installer.sh  QEMU-Testumgebung (iso/boot/clean)
scripts/build-iso.sh    ISO-Bau über Bootstrap + systemd-nspawn + mkarchiso
docs/                   STATUS, Installer-Entscheidungen, Fallstricke
```

## Host-Profil anlegen

1. `hosts/<name>/settings.env` – Feature-Schalter (`USERNAME`, `GPU`,
   `SUNSHINE`, `FLATPAK`, `SSHD`, `I2C`, `BEDROCK`, …; Erklärung in
   `docs/STATUS.md` §3)
2. `hosts/<name>/packages.list` – Host-Pakete (shared steht in
   `shared/packages.list`)
3. `hosts/<name>/config/` – Dateien relativ zum Wurzelverzeichnis
   (`etc/…`, `usr/local/bin/…`)
4. `hosts/<name>/home/` – optionale Dotfile-Overrides (sonst nur `shared/home`)
5. `hosts/<name>/kernel-cmdline`, `authorized_keys` (optional)
6. `hosts/<name>/post.sh` – Sonderfälle, läuft als root mit `$1 = Ziel-Root`
   und `$2 = Repo-Verzeichnis`; darf die Installation nicht abbrechen

## Tests

```bash
# Trockenlauf mit Loop-Device
truncate -s 2G /tmp/test.img
sudo losetup --find --show /tmp/test.img
sudo ./install.sh --host benny --disk /dev/loop0 --dry-run

# kompletter Lauf in QEMU (serielle Konsole, LAN-Netz, UEFI)
QEMU_DISPLAY=none QEMU_VGA=std LAN_NET=1 KEEP_OVMF=1 \
  SERIAL_SOCK=/tmp/serial.sock WORK=/var/tmp/arch-test-benny \
  ./test/test-installer.sh iso
# installiertes System booten
WORK=/var/tmp/arch-test-benny KEEP_OVMF=1 ./test/test-installer.sh boot
```

Die vollständige Prüfliste (Services, Pakete, Home-Rechte, SSH) steht in
`docs/STATUS.md` §10.

## ISO bauen und veröffentlichen

```bash
sudo ./scripts/build-iso.sh          # ~10 min, Ergebnis in iso/arch/out/
```

Danach das Release-Asset ersetzen (der Link bleibt gleich):

```bash
cp iso/arch/out/arch-install-<datum>.iso /var/tmp/arch-install-latest.iso
( cd /var/tmp && sha256sum arch-install-latest.iso > arch-install-latest.iso.sha256 )
gh release upload iso-latest /var/tmp/arch-install-latest.iso \
  /var/tmp/arch-install-latest.iso.sha256 --clobber
gh release edit iso-latest --notes "Version <datum> … SHA256 …"
rm /var/tmp/arch-install-latest.iso*
```

## Dokumentation

- `docs/STATUS.md` – Übergabe: Aufbau, Host-Features, Portierungsmatrix,
  Fallstricke, Test-Workflow, offene Punkte
- `docs/installer.md` – Installer-Entscheidungen und Ablauf
- `docs/arch-fix.md` – gefundene Fehler und Fixes (inkl. QEMU-Tests)
- `umbriel.md` – Arch-Umbriel-Tracking (Version, Config, Upstream-Checks)
- `hosts/benny/README.md` – QEMU-Test, ASM-Fork, GameDAC

## Konventionen

- `install.sh` bricht bei jedem Fehler ab (`set -Eeuo pipefail`) – nie halb
  installiert weiterlaufen.
- Destruktive Schritte verlangen eine ausdrückliche Bestätigung.
- Hostspezifisches gehört nach `hosts/<name>/`, nicht in `lib/`.
- `post.sh` ist optional und darf nur warnen, nicht abbrechen.
- Kein Flatpak-Zwang: Gaming-Stack nativ, Flatpak nur wo gewünscht.
