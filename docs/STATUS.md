# Status & Übergabe – Arch-Linux-Port

Stand: 2026-11-24. Diese Datei ist als Einstiegspunkt gedacht: Wer (auch ich
später) hier weiterarbeitet, soll nach dem Lesen wissen, wie der Port aufgebaut
ist, was schon verifiziert wurde, welche Fallstricke es gibt und was offen ist.

**Auf `nex` verifizierte Fehlerbilder + Installer-Fixes** (Noctalia-Autostart,
Greeter-Sync, GNOME-Keyring, Rechte nach `cp -a`): siehe
[`docs/arch-fix.md`](arch-fix.md).

## 1. Ziel

Der NixOS-Setup (`xXMortiferusXx/nix-config`) soll auf Arch Linux laufen –
gleiche Oberfläche, gleiche Werkzeuge, gleiche Eigenheiten, aber native
Arch-Pakete statt Nix. Kein Flatpak auf `nex`, Flatpak auf `lion-pc`.

## 2. Aufbau des Repos

```
install.sh            Einstiegspunkt (läuft auf der Live-ISO)
lib/                  Installer-Bibliothek
  common.sh           UI, confirm, require_root/uefi
  disk.sh             Partitionierung, btrfs-Subvolumes, Mounts
  base.sh             pacstrap, fstab, User, Grundkonfiguration
  boot.sh             GRUB (UEFI), Theme, mkinitcpio
  extras.sh           chaotic, Snapshots, Btrfs-Wartung, Grafik, Desktop,
                      Gaming, Dienste, Keyring, Flatpak
shared/               gilt für ALLE Hosts
  packages.list       gemeinsame Pakete
  config/             /etc-Overlay (sysctl, udev, journald, systemd, zram,
                      polkit, Portale, fastfetch, Firefox, Thunar, nftables-Basis,
                      arch-check/arch-clean, greetd-Drop-in, zink-run, steam)
  home/               Dotfiles (fish, starship, nvim, icons, xsettingsd,
                      arch-update-Config + Timer + Tray-Service, OBEX)
  grub/               GRUB-Theme "Unholy Angels" (Bild + theme.txt + Generator)
hosts/<host>/         nur die Unterschiede
  packages.list       Host-Pakete
  settings.env        Host-Features (s. u.)
  kernel-cmdline      zusätzliche Kernel-Parameter
  config/             /etc-Overrides (überschreiben shared/)
  home/               Host-Dotfiles (überschreiben shared/)
  authorized_keys     SSH-Key (nur wo sshd läuft)
  post.sh             optionaler Host-Nachlauf
iso/arch/             archiso-Profil (Packages, issue, MOTD, install-arch,
                      serielle Konsole)
scripts/build-iso.sh  ISO-Bau über Arch-Bootstrap + systemd-nspawn + mkarchiso
test/                 QEMU-Testumgebung + Automatisierungs-Helfer
docs/                 diese Datei, installer.md
```

Reihenfolge beim Install: `shared/…` wird zuerst kopiert, danach
`hosts/<host>/…` (überschreibt). Bei Paketen werden beide Listen vereinigt
(Duplikate entfernt).

## 3. Installer

Phasen: Partitionieren → Dateisystem+Subvolumes → pacstrap → fstab →
Grundkonfiguration → Bootloader → Extras → Passwörter.

```bash
install-arch                        # interaktiv (Host, Ziel-Disk, Spiele-Platte)
install-arch --host nex --disk /dev/nvme0n1 --gaming /dev/nvme1n1
install-arch --host nex --disk /dev/vda --yes      # ohne Rückfragen (Tests)
install-arch --dry-run                             # nur Vorprüfung
```

`--gaming`/die interaktive Frage betrifft eine **bestehende** Platte: sie wird
nur gemountet (nie formatiert), kein `@gaming`-Subvolume, fstab mit
`defaults,noatime,nofail,x-systemd.device-timeout=5`, Mountpunkt gehört dem User.

### `hosts/<host>/settings.env`

Werte aus der Umgebung haben Vorrang (`: "${VAR:=default}"`), z. B.
`SSHD=1 install-arch …` für Tests auf einem Host ohne sshd.

| Variable | Bedeutung | nex | lion-pc |
|---|---|---|---|
| `USERNAME` | Benutzer | mortiferus | lion |
| `GPU` | `nvidia` oder `amd` (steuert NVIDIA-Pfad vs. radeonsi-Env) | nvidia | amd |
| `SUNSHINE` | Game-Streaming-Host | 1 | 0 |
| `SCANNER` | NAPS2 installieren | 1 | 0 |
| `FLATPAK` | Flatpak + Bazaar + Flathub | 0 | 1 |
| `LAPTOP` | Legion-Akku-Limit (60 %) | 1 | 0 |
| `SSHD` | SSH-Server | 0 | 1 |
| `I2C` | ddcutil (Monitor-Helligkeit), Gruppe `i2c` | 0 | 1 |
| `EXTRA_GROUPS` | zusätzliche Gruppen | input scanner lp | scanner lp |
| `NOPASSWD_SUDO` | sudo ohne Passwortabfrage (`zzz-<user>-nopasswd`) | 1 | 0 |
| `BEDROCK` | BedrockOnLinux-AppImage (Windows-Client, Xbox-Friends/Einladungen) | 0 | 1 |

Der User bekommt immer `wheel,audio,video`; sysusers-Gruppen werden vor
`useradd` angelegt (im Chroot existieren sie sonst nicht).

## 4. Datenträger-Layout

- ESP 1 GB (vfat, `/boot`), Rest btrfs
- Subvolumes: `@` → `/`, `@home`, `@snapshots`, `@var_cache`, `@var_tmp`,
  `@var_log`, optional `@gaming`
- Snapper **nur** auf `@` (`NUMBER_LIMIT=10`, `IMPORTANT=5`, Timeline aus)
- `grub-btrfs` + `snapper-support` → Snapshot-Booteinträge im GRUB-Menü
- Btrfs-Wartung: `btrfs-scrub@-.timer` (monatlich), `btrfs-balance.timer`
  (wöchentlich, `-d usage=5`), `fstrim.timer`
- GRUB: UEFI, Theme, `\EFI\BOOT\BOOTX64.EFI` als Fallback ohne NVRAM-Eintrag,
  `GRUB_TIMEOUT=10`, `30_uefi-firmware`/`31_efi_bootnext` deaktiviert

## 5. ISO

```bash
sudo ./scripts/build-iso.sh          # ~10 min, Ergebnis in iso/arch/out/
```

- Arch-Bootstrap → systemd-nspawn (`--capability=all`) → mkarchiso
- `iso/arch/profiledef.sh`: `kernel_params_x86_64="console=ttyS0"`
- serielle Root-Konsole (Autologin) für automatisierte Tests
- `install-arch` zieht das Repo von `main` (Fallback: eingebetteter Tarball,
  ohne `iso/arch/out` und `.git`)
- ISO-Namen enthalten Datum+Uhrzeit (kein Überschreiben einer laufenden VM)

## 6. Hosts

### nex (Legion 5, Ryzen 5 5600H + RTX 3070 Mobile)
NVIDIA offene Module (`nvidia-open-dkms`), PRIME-Offload (`nvidia-offload`),
Dynamic Boost (`nvidia-powerd`), Power-Management (`NVreg_*`,
`nvidia-suspend/resume/hibernate`), Legion-Akku-Limit, Touchpad-Toggle,
GC7-Audio (Clock, EQ mit MMX-330-Filter, WirePlumber, `gc7-reset`),
Sunshine (LizardByte-Repo), kein sshd.

### lion-pc (Ryzen 5 1500X + Radeon RX 590)
AMD/RADV (`mesa`, `vulkan-radeon`, `lib32-*`), radeonsi-Env, `scx_lavd`
(Gaming-Modus), ddcutil/DDC-CI statt brightnessctl, `game-performance` mit
Monitor-Helligkeit, Flatpak+Bazaar+Flathub, sshd (nur aus LAN), kein Sunshine.

### benny (geplant, noch nicht angelegt)
Intel Ivy Bridge (i5-3xxx, HD 2500), Arctis GameDAC (Arctis Sound Manager,
benny-only!), Flatpak, DNS 192.168.178.1 (FritzBox), Realtek-r8169-Resume-Fix,
kein Sunshine. Für ein Profil wären nötig: `GPU=intel` (neuer Pfad),
`SUNSHINE=0`, `SCANNER=0` (kein Scanner), `FLATPAK=1`, `SSHD=1`,
`LAPTOP=0`, `I2C=0`, eigener User `benny`, GameDAC-Config, Arctis-Paket
(AUR/Flake → auf Arch als AUR-Build oder Flatpak).

## 7. Portierungsmatrix (NixOS → Arch)

| NixOS | Arch | Status |
|---|---|---|
| `system/common` (Locale, Networking, Security, ananicy, audio, printing, shell, editor, fastfetch, terminal, tools, desktop, polkit, fonts, thunar, greeter, umbriel) | shared + host | ✅ (außer `nix-settings`, `nix-ld`, Nix-Tools) |
| `boot-nex` / `boot-lion` (Kernel-Params, Blacklist, ntsync, zram) | `kernel-cmdline`, `modprobe.d`, `modules-load.d`, zram-generator | ✅ |
| `environment-*` (Session-Variablen) | `hosts/*/config/etc/environment` | ✅ (Cursor, Qt, radeonsi, Shader-Cache) |
| `nvidia-prime` | `extras_nvidia`, `modprobe.d/nvidia.conf`, VRAM-Profile, `nvidia-offload` | ✅ (Laufzeit ungetestet) |
| `legion` (Akku 60 %, iwlmvm, irqbalance, µcode) | Unit+Skript, modprobe, `amd-ucode` | ✅ |
| `bpftune` (Netzwerk-Auto-Tuning) | `bpftune-git` (chaotic) + `bpftune.service` | ✅ |
| `touchpad` | `touchpad-toggle` + udev | ✅ |
| `audio-gc7` | PipeWire/WirePlumber/udev/`gc7-reset` | ✅ (pro-audio + param_eq live geprüft) |
| `gaming` (steam, gamescope, udev, scripts, sunshine) | Pakete, 99-gaming.rules, `game-performance`, Steam-Wrapper, LizardByte | ✅ |
| `cachyos-tools` (zink-run, dlss-swapper) | `usr/local/bin` | ✅ |
| `ausweis`, `zink-run` | `ausweisapp`, `zink-run` | ✅ |
| `users/*` (Gruppen) | `settings.env` + `EXTRA_GROUPS` | ✅ (nex: input/scanner/lp, lion: scanner/lp/i2c) |
| `home/*` (Dotfiles, Noctalia-State, `.face`) | `hosts/*/home` + AccountsService-Icon | ✅ |
| `polkit` (Wheel + passwordless Greeter-Sync) | `rules.d/49-wheel`, `50-noctalia-sync` | ✅ |
| `noctalia-greeter` | greetd + `/var/lib/noctalia-greeter/greeter.toml`, `getty@tty1` maskiert, Greeter-Home korrigiert | ✅ |
| `printing`/`sane` | cups(+browsed), sane, sane-airscan | ✅ |
| `flatpak` (benny/lion) | Flatpak + Bazaar + Flathub, Auto-Update + Key-Refresh | ✅ lion |
| `btrfs`-Modul (Scrub/Balance) | Timer | ✅ |
| `fstrim`, `chrony`, `resolved`, `iwd`, `wireless-regdb`, `avahi`, `fwupd`, `smartd`, `colord`, `irqbalance`, `upower`, `udisks2`, `bluetooth`, `logrotate`, `acpid` | systemd-Units/Pakete | ✅ |
| `firewall` | `nftables.conf` pro Host | ✅ (IPv4/IPv6, DHCP/mDNS/ICMP, SSH nur LAN bei lion, Sunshine bei nex) |

## 8. Bewusste Entscheidungen / Abweichungen

- **Kein systemd-oomd** (hat auf NixOS Spiele gekillt); zram + swappiness 150
  übernehmen den Druck.
- **Kein Flatpak auf nex** (nativ), Flatpak+Bazaar nur lion/benny.
- **nex: sudo ohne Passwort** (`NOPASSWD_SUDO=1`): eigene Datei
  `zzz-<user>-nopasswd` in `/etc/sudoers.d`, damit sie nach `wheel` gelesen
  wird (sudo wertet den letzten Treffer aus). lion behält die Abfrage.
- **Sunshine** aus dem offiziellen **LizardByte-Repo** (nicht AUR – das
  AUR-Bin-Paket bricht bei libicu-Updates).
- **Kein `nix-check`/`nixos-update`**: auf Arch `arch-update` (chaotic, Tray +
  Timer, AUR+Flatpak), `arch-check` (Status), `arch-clean` (Orphans/Cache).
- **`prime-run`** (Paket `nvidia-prime`) und **`nvidia-offload`** (Port des
  NixOS-Wrappers, zusätzlich `VK_DRIVER_FILES`) existieren beide.
- **Noctalia**: das Plugin `avivbintangaringga/nix-monitor` (Bar-Widget +
  `update_command`) ist entfernt – es ruft `nixos-update` auf. `discord_binary`
  zeigt auf `/usr/bin/discord` statt auf einen Nix-Profil-Pfad.
- **`game-performance`**: Performance-Profil + Inhibit + Helligkeit; nex nutzt
  brightnessctl, lion ddcutil. EPP/Governor macht power-profiles-daemon.
- **Zink/dlss-Wrapper**, **thunar-extract**, **touchpad-toggle**,
  **legion-conservation-mode**, **gc7-reset** liegen in `usr/local/bin`.
- `rootflags=subvol=@` steht doppelt in der Cmdline (GRUB ergänzt es selbst) –
  harmlos, bewusst so gelassen (Sicherheitsnetz).

## 9. Fallstricke aus den Testläufen (bitte nicht wiederholen)

1. **pacman fragt trotz `--noconfirm` nach Anbietern** (virtuelle Abhängigkeiten).
   Explizite Anbieter in die Liste: `iptables` (nicht `iptables-nft`, das Paket
   gibt es nicht), `mkinitcpio`, `lib32-nvidia-utils` + `lib32-vulkan-radeon`,
   `xdg-desktop-portal-gtk`. `greetd` erst in `extras_desktop` (Provider
   `greetd-greeter` kommt aus chaotic).
2. **`scx_loader.service` steckt in `scx-tools`**, nicht in `scx-scheds`.
   `extras_system` aktiviert ihn nur, wenn `scx-tools` installiert ist.
3. **`vkbasalt`/`lib32-vkbasalt` gibt es nur in chaotic**, nicht offiziell.
4. **`cp -a shared/home/. /home/user/` übernimmt den Modus des Quellverzeichnisses**
   (775) → nach dem Kopieren `chmod 750` (sshd `StrictModes`!).
5. **`acl` ist nicht Teil von `base`** → in ISO- und Host-Paketliste; `setfacl`
   im Ziel-Chroot ausführen.
6. **sysusers-Gruppen existieren im Chroot nicht** (`networkmanager`, `audio`,
   `video`) → vor `useradd` per `getent group || groupadd -r` anlegen.
7. **`settings.env` muss vor den Defaults geladen werden** (`: "${VAR:=…}"`),
   sonst gewinnt immer der Default.
8. **archiso liest `kernel_params_<arch>`**, nicht `kernel_params`.
9. **Offline-Tarball ohne `iso/arch/out` und `.git`** bauen, sonst wächst das ISO
   mit jedem Build (das alte ISO wurde mit eingepackt → 1,9 GB).
10. **nftables: `icmpv6`**, nicht `ipv6-icmp` (sonst lädt der Regelsatz nicht).
    `nftables.service` ist ein Oneshot ohne `RemainAfterExit` → `is-active` ist
    nach dem Boot „inactive", obwohl die Regeln geladen sind (Journal:
    „Finished Netfilter Tables").
11. **`getty@tty1` maskieren** (wie NixOS: `getty@tty1` disabled,
    `autovt@tty1` masked), sonst blitzt beim Login die Textkonsole auf.
12. **fish: Interaktives nur bei `status is-interactive`** – `start-umbriel`
    startet die Session über `fish -l -c …`; ohne Guard läuft fastfetch beim
    Login und blitzt auf dem VT auf.
13. **QEMU aus dem Nix-Store kann per GC verschwinden** → GC-Root anlegen
    (`nix build nixpkgs#qemu_full -o /tmp/opencode/qemu`).
14. **ISO nicht überschreiben, während eine VM davon bootet** (SQUASHFS/xz).

## 10. Test-Workflow

```bash
# ISO booten (Testumgebung)
./test/test-installer.sh iso [iso-datei]

# automatisiert über die serielle Konsole:
python3 test/serial-console.py /tmp/opencode/serial.sock \
        /tmp/opencode/serial.log /tmp/opencode/serial.cmd &
# QEMU mit: -chardev socket,id=ser0,path=/tmp/opencode/serial.sock,server=on,wait=off
#           -serial chardev:ser0
# Antworten: test/drive-install.py (interaktive Prompts) bzw.
#            test/drive-pw.py (nur Passwörter bei --yes-Läufen)

# installiertes System booten, SSH prüfen
ssh -i ~/.ssh/github_ed25519 -p 2222 <user>@127.0.0.1

# Firewall echt testen: QEMU-Netz ins LAN legen
#   -netdev user,net=192.168.50.0/24,host=192.168.50.2,dhcpstart=192.168.50.100
#   → SSH aus dem LAN erlaubt; mit host=10.0.2.2 (nicht LAN) Timeout.

# Offline-Prüfung ohne Boot (Root-Dateien, Rechte, Timer-Symlinks):
sudo qemu-nbd -c /dev/nbd0 disk.qcow2
sudo mount -o subvol=@ /dev/nbd0p2 /mnt/t   # + /dev/nbd0p1 → /mnt/t/boot
```

## 11. Offene Punkte

1. **Hardware-Test auf nex**: NVIDIA/PRIME, Dynamic Boost, GC7 (ChatMix/EQ),
   Legion-Akku, Touchpad, Greeter-Sync (greift erst nach dem ersten Login).
2. **Hardware-Test lion-pc** (AMD/RADV, DDC-CI, scx_lavd, Flatpak/Bazaar,
   Bazaar-Auto-Update, Flathub-Key-Refresh, BedrockOnLinux/Xbox-Friends).
3. **benny**: Entscheidung offen; Profil noch nicht angelegt (s. o.).
4. **Nix-Skripte**: `audio-rate`, `mic-check` (nicht nötig, Werte stehen fest),
   `nvidia-track`, `boosteroid-track` – bei Bedarf neu bauen.
5. **ISO-Hosting** für Benny (Storage-Box-Unterkonto, read-only, `.sha256`).
6. `nex` hat regulär **kein sshd** (nur lion/benny) – bei Tests `SSHD=1`
   voranstellen.

## 12. Nützliche Befehle auf dem Zielsystem

```bash
arch-check          # ausstehende Updates (pacman+chaotic+AUR), Orphans, Reboot
arch-clean          # Orphans, paccache, paru-Cache, Journal
arch-update         # interaktiver Updater (Tray + Timer laufen automatisch)
game-performance <spiel>
nvidia-offload <programm>      # oder prime-run
gc7-reset                      # GC7 nach USB-Lock zurücksetzen
sudo nft list ruleset          # Firewall ansehen
snapper -c root list           # Snapshots (nur @)
systemctl list-timers          # Scrub/Balance/fstrim/snapper/arch-update
```
