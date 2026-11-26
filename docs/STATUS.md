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
  home/               Dotfiles (fish, starship, nvim, kitty, mpv, icons,
                      xsettingsd, arch-update-Config + Timer + Tray-Service,
                      OBEX, Discord-Autostart, systembus-notify, MIME-Defaults)
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

| Variable | Bedeutung | nex | lion-pc | benny (vorbereitet) |
|---|---|---|---|---|
| `USERNAME` | Benutzer | mortiferus | lion | benny |
| `GPU` | `nvidia`, `amd` oder `intel` | nvidia | amd | intel |
| `SUNSHINE` | Game-Streaming-Host | 1 | 0 | 0 |
| `SCANNER` | NAPS2 installieren | 1 | 0 | 0 |
| `FLATPAK` | Flatpak + Bazaar + Flathub | 0 | 1 | 1 |
| `LAPTOP` | Legion-Akku-Limit (60 %) | 1 | 0 | 0 |
| `SSHD` | SSH-Server | 0 | 1 | 1 (öffentlich, DynDNS) |
| `I2C` | ddcutil (Monitor-Helligkeit), Gruppe `i2c` | 0 | 1 | 1 |
| `EXTRA_GROUPS` | zusätzliche Gruppen | input scanner lp | scanner lp | – |
| `NOPASSWD_SUDO` | sudo ohne Passwortabfrage (`zzz-<user>-nopasswd`) | 1 | 0 | 1 |
| `BEDROCK` | BedrockOnLinux-AppImage (Windows-Client, Xbox-Friends/Einladungen) | 0 | 1 | 0 |
| `FAUGUS` | Faugus Launcher (chaotic) | 1 | 0 | 0 |
| `ORCA` | OrcaSlicer (chaotic, `orca-slicer-bin`) | 1 | 0 | 0 |

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

### Release-Upload (stabiler Link)

Die jeweils aktuelle ISO liegt als GitHub-Release `iso-latest`:

```
https://github.com/xXMortiferusXx/arch-linux/releases/download/iso-latest/arch-install-latest.iso
https://github.com/xXMortiferusXx/arch-linux/releases/download/iso-latest/arch-install-latest.iso.sha256
```

Nach jedem Build (`iso/arch/out/*.iso`) aktualisieren:

```bash
cp iso/arch/out/arch-install-<datum>.iso /var/tmp/arch-install-latest.iso
( cd /var/tmp && sha256sum arch-install-latest.iso > arch-install-latest.iso.sha256 )
gh release upload iso-latest /var/tmp/arch-install-latest.iso \
  /var/tmp/arch-install-latest.iso.sha256 --clobber
gh release edit iso-latest --notes "Version <datum> … SHA256 …"
rm /var/tmp/arch-install-latest.iso*
```

Der Link bleibt gleich (Asset wird überschrieben). `gh` ist installiert
(`github-cli`); Login `gh auth login --web`.

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

**Home-Backup vor der Neuinstallation (2026-11-24):**
`nex:/home/mortiferus/backups/lion-pc/2026-11-24/` – 1,1 GB Benutzerdaten
(Browser, Discord, Umbriel, Steam-Config/userdata, Bedrock-Welten,
PrismLauncher-Instanzen, Keyrings, Bilder/Downloads). Enthalten sind
`README.md`, `manifest.sha256`, `restore-home.sh` und `entfernt.txt`.
Wiederherstellen nach der Installation:

```bash
# frisches Arch hat kein rsync -> tar ueber SSH
tar -C /home/mortiferus/backups/lion-pc/2026-11-24 -cf - . \
  | ssh lion 'mkdir -p /var/tmp/lion-restore && tar -C /var/tmp/lion-restore -xpf -'
ssh lion 'TARGET_USER=lion bash /var/tmp/lion-restore/restore-home.sh'
```

Das Skript korrigiert die NixOS-Eigenheiten für Arch: Umbriel-`autostart`,
Firefox-Profil nach `~/.mozilla/firefox` samt `profiles.ini` **und
`installs.ini`** (ohne `installs.ini` legt Firefox 67+ ein neues Profil an und
ignoriert `lion`), Profilbild,
tote `/nix/store`-Symlinks, Bedrock-Welten. Es braucht kein rsync (tar reicht)
und läuft als `lion`, solange nichts root gehört.

**Umbau 2026-11-24:** Patriot P210 256 GB (SATA) gegen NVMe 476 GB getauscht,
Kingston SUV400 als `/gaming` (`GamingDrive`, UUID `82cd6e39-…`) erhalten.
Installation mit `--disk /dev/nvme0n1 --gaming /dev/sda1`; danach Restore vor
dem ersten Login: 13.274 Dateien, `umbriel config validate` → `config: ok`,
0 tote Symlinks. WLAN war bereits eingerichtet, Flatpak-Apps (Scratch, Sober)
nachinstalliert.

Erster Restore ließ **Steam** und **Vinegar/Roblox Studio** einen neuen Login
verlangen: Die Trim-Regel hatte `Steam/config/htmlcache` (dort liegt
`steamLoginSecure`) und `vinegar/prefixes` erwischt. Auch von der alten Patriot-SSD
(USB) ließ sich der Steam-Login nicht übernehmen: Der Blob in
`Steam/local.vdf` (`ConnectCache`) ist an die alte Installation gebunden und
wurde verworfen. Nach je einem frischen Login sind Steam und Vinegar jetzt
gesichert:

| App | Datei(en) |
|---|---|
| Steam | `Steam/local.vdf` (ConnectCache-Blob), `.steam/steam.token`, `Steam/config/` |
| Vinegar | `vinegar/prefixes/studio`, `vinegar/appdata`, `settings.reg` |
| Heroic | `~/.config/heroic` (auf NixOS nie vorhanden – nichts zu retten) |

Sober, Bedrock und PrismLauncher behielten ihre Logins von Anfang an.

**Abschluss 2026-11-24 (alles verifiziert):**

| Punkt | Stand |
|---|---|
| Firefox | Profil `lion` aktiv, `places.sqlite` 28.388 History-Einträge, 11 MB Add-ons; Fix: `installs.ini` |
| Bedrock | 5 Welten im Prefix (4 aus Backup + 1 neue), `msa`-Login sofort da |
| Steam | `Lion_Jasper` eingeloggt, Bibliothek auf `/gaming/SteamLibrary` erkannt |
| Vinegar | Roblox-Studio-Login im Prefix, gesichert |
| Heroic | auf NixOS nie vorhanden, neu eingerichtet, `~/.config/heroic` im Backup |
| arch-update | `arch-update-tray.service` enabled/active, Timer aktiv |
| Flatpak | Scratch 3.10.1, Sober 1.8.0 |
| Aufgeräumt | `.neu`-Reste, `/var/tmp/lion-restore`, Bedrock-Staging entfernt |

Backup: `nex:/home/mortiferus/backups/lion-pc/2026-11-24` (3,4 GB, Manifest
26.815 Dateien, Prüfsummen verifiziert). Root 25 GB von 476 GB belegt.

Das Restore-Skript liegt kanonisch im Backup (`…/restore-home.sh`, braucht
`home/`, `face.png`, `flatpak-apps.txt` daneben) und als versionierte Kopie
unter `scripts/lion-home-restore.sh`.

Nicht im Backup: Spiele/Runtimes (Steam `steamapps`, Proton, Bedrock-Runtime,
PrismLauncher-`assets`), Caches sowie `/etc/nixos` (eigenes Repo).

### benny (in QEMU **getestet**, Hardware-Test offen)

Desktop bei Benny, **nicht** im eigenen LAN (DynDNS, Zugriff von `nex`).
Intel Ivy Bridge (i5-3xxx, HD 2500/4000), Arctis Pro + GameDAC Gen1,
Cloud-Gaming (Edge/Boosteroid), Flatpak, DNS `192.168.178.1` (FritzBox).

- **GPU=`intel`** – neuer Pfad `extras_graphics_intel`; `vulkan-intel` (ANV)
  und `libva-intel-driver` (i965) stehen in `hosts/benny/packages.list`,
  `LIBVA_DRIVER_NAME=i965` in `hosts/benny/config/etc/environment`.
- **I2C=1** (bewusst abweichend vom alten Plan): die NixOS-Config gibt Benny
  `i2c`-Gruppe, udev-Regel und `ddcutil`.
- **SSH** ist öffentlich erreichbar: `nftables.conf` erlaubt Port 22 von
  überall, `sshd_config.d/10-benny-hardening.conf` nur Keys, `AllowUsers benny`.
- **GameDAC**: udev (USB-Autosuspend aus), WirePlumber (S32LE/48 kHz/2 ch,
  kein Suspend), `game-performance`/`edge-performance`.
- **ASM** umschaltbar via `ASM_FLAVOR` (`fork` Default | `upstream` | `none`):
  Default ist der eigene Build `1.4.27+fork.3` (lief mit dem GameDAC Gen1;
  Entscheidung 2026-11-24: bewährter Stand hat Vorrang, weil kein Test vor
  Ort möglich ist), Upstream 1.7.10 alternativ. Fork-PKGBUILD liegt unter
  `hosts/benny/pkgbuilds/`. Dazu `asm-verify` auf dem Host für
  Remote-Diagnose (Sinks, Kanal-Layout, Streams, Journal).
- Details und Testliste: `hosts/benny/README.md`.
- **QEMU-Test 2026-11-25:** kompletter Durchlauf inkl. `post.sh` grün –
  Edge, ASM-Fork `1.4.27+fork.3`, Boosteroid installiert; Home `benny:benny 750`,
  SSH per Key, keine failed units, `[multilib]` aktiv. Dabei drei
  Installer-Bugs gefunden und behoben (`docs/arch-fix.md` §10).

Quelle der Werte: `nix-config` (`hosts/benny`, `modules/hardware/*`,
`modules/home/benny`). Dort wurde **nichts** geändert – die NixOS-Config ist
derzeit nicht testbar; Anpassungen bei Benny laufen später über SSH bzw. sein
eigenes Repo.

## 7. Portierungsmatrix (NixOS → Arch)

| NixOS | Arch | Status |
|---|---|---|
| `system/common` (Locale, Networking, Security, ananicy, audio, printing, shell, editor, fastfetch, terminal, tools, desktop, polkit, fonts, thunar, greeter, umbriel) | shared + host | ✅ (außer `nix-settings`, `nix-ld`, Nix-Tools) |
| `boot-nex` / `boot-lion` (Kernel-Params, Blacklist, ntsync, zram) | `kernel-cmdline`, `modprobe.d`, `modules-load.d`, zram-generator | ✅ |
| `environment-*` (Session-Variablen) | `hosts/*/config/etc/environment` | ✅ (Cursor, Qt, radeonsi/i965, Shader-Cache) |
| `intel-ivy` (VA-API i965, no CUDA) | `GPU=intel`, `vulkan-intel`, `libva-intel-driver`, Env | ✅ (vorbereitet, ungetestet) |
| `nvidia-prime` | `extras_nvidia`, `modprobe.d/nvidia.conf`, VRAM-Profile, `nvidia-offload` | ✅ (Laufzeit ungetestet) |
| `legion` (Akku 60 %, iwlmvm, irqbalance, µcode) | Unit+Skript, modprobe, `amd-ucode` | ✅ |
| `bpftune` (Netzwerk-Auto-Tuning) | `bpftune-git` (chaotic) + `bpftune.service` | ✅ |
| `touchpad` | `touchpad-toggle` + udev | ✅ |
| `audio-gc7` | PipeWire/WirePlumber/udev/`gc7-reset` | ✅ (2ch + `gc7_chat`-Sink, ChatMix live geprüft) |
| `gaming` (steam, gamescope, udev, scripts, sunshine, faugus) | Pakete, 99-gaming.rules, `game-performance`, Steam-Wrapper, LizardByte, `cap_sys_nice`, `FAUGUS` | ✅ |
| `cachyos-tools` (zink-run, dlss-swapper) | `usr/local/bin` | ✅ |
| `ausweis`, `zink-run` | `ausweisapp`, `zink-run`, Ports 24727 (wlan0/eno1) | ✅ |
| `users/*` (Gruppen) | `settings.env` + `EXTRA_GROUPS` | ✅ (nex: input/scanner/lp, lion: scanner/lp/i2c) |
| `home/*` (Dotfiles, Noctalia-State, `.face`, Kitty/mpv/Discord/MIME) | `hosts/*/home` + AccountsService-Icon | ✅ |
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

# Headless + seriell + Lion-Firewall-kompatibles QEMU-Netz:
QEMU_DISPLAY=none QEMU_VGA=std LAN_NET=1 WORK=/var/tmp/arch-test \
  SERIAL_SOCK=/tmp/opencode/serial.sock \
  ./test/test-installer.sh iso
# installiertes System:
QEMU_DISPLAY=none QEMU_VGA=std LAN_NET=1 KEEP_OVMF=1 WORK=/var/tmp/arch-test \
  SERIAL_SOCK=/tmp/opencode/serial-boot.sock \
  ./test/test-installer.sh boot

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
   Bazaar-Auto-Update, Flathub-Key-Refresh). Bedrock lief bereits: 5 Welten
   im Prefix (4 aus Backup + 1 neue), `msa`-Login sofort da.
   - **Erledigt (2026-11-26):** Login-Handoff-Fix (`docs/arch-fix.md` §11)
     und grub-btrfs-Fix (§12) live nachgezogen, `speedtest-cli` entfernt.
     Nach dem Reboot geprüft: `ShowStatus=no`, keine failed Units, Login
     ohne Aufblitzen.
3. **benny**: Installation abgeschlossen (2026-11-26), Nachcheck sauber
   (keine failed Units, Login-Fix aktiv, Bazaar-Auto-Update läuft,
   Boosteroid 1.11.29 startet aus dem Menü). ASM-EQ/Mikrofon stellt er selbst
   ein – bei Problemen meldet er sich.
4. **Nix-Skripte**: `audio-rate`, `mic-check` (nicht nötig, Werte stehen fest),
   `nvidia-track`, `boosteroid-track` – bei Bedarf neu bauen.
5. **ISO-Hosting** für Benny (Storage-Box-Unterkonto, read-only, `.sha256`).
6. `nex` hat regulär **kein sshd** (nur lion/benny) – bei Tests `SSHD=1`
   voranstellen.
7. **speedtest**: Python-`speedtest-cli` entfernt (`d43c5a7`, liefert
   unbrauchbare Werte). NixOS hatte `ookla-speedtest`; live installiert ist
   `ookla-speedtest-bin` (AUR, 1.2.0) auf nex und benny. **Offen:**
   - Einbindung in den Installer für alle Hosts – braucht einen gemeinsamen
     AUR-Schritt (bisher nur benny mit `aur_install` in `post.sh`, dort ist
     ookla schon drin).
   - lion-pc: `speedtest-cli` entfernt (2026-11-26), ookla nicht installiert.

## 12. Nützliche Befehle auf dem Zielsystem

```bash
arch-check          # ausstehende Updates (pacman+chaotic+AUR), Orphans, Reboot
arch-clean          # Orphans, paccache, paru-Cache, Journal
arch-update         # interaktiver Updater (Tray + Timer laufen automatisch)
game-performance <spiel>
nvidia-offload <programm>      # oder prime-run
gc7-reset                      # GC7 nach USB-Lock zurücksetzen
systemctl --user restart gc7-2ch.service   # GC7: 2ch-Profil + Voice-Sink neu
sudo nft list ruleset          # Firewall ansehen
snapper -c root list           # Snapshots (nur @)
systemctl list-timers          # Scrub/Balance/fstrim/snapper/arch-update
```
