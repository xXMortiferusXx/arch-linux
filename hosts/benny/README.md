# Host-Profil `benny` (vorbereitet, **ungetestet**)

Desktop von Benny: Intel i5-3xxx (Ivy Bridge), HD 2500/4000, Arctis Pro +
GameDAC Gen1, Cloud-Gaming. Steht **nicht** im eigenen LAN (DynDNS, Zugriff
von `nex` aus).

Quelle der Werte: `nix-config` → `hosts/benny`, `modules/hardware/*`,
`modules/home/benny`. Dorthin wurde bewusst **nichts** zurueckgeschrieben –
die NixOS-Config ist derzeit nicht testbar.

## Was hier liegt

| Datei | Zweck |
|---|---|
| `settings.env` | `GPU=intel`, `I2C=1`, `SSHD=1`, kein Sunshine/Scanner/Laptop |
| `kernel-cmdline` | `intel_pstate=active`, `transparent_hugepage=madvise` |
| `packages.list` | `vulkan-intel`, `libva-intel-driver` (i965), ASM-Deps |
| `authorized_keys` | Key von `mortiferus@nex` (NixOS-Config) |
| `post.sh` | Edge (chaotic) + AUR-Builds: `python-pulsectl`, `arctis-sound-manager`, `boosteroid` |
| `config/etc/environment` | `LIBVA_DRIVER_NAME=i965`, `VDPAU_DRIVER=va_gl` |
| `config/etc/.../50-benny.conf` | DNS `192.168.178.1` (FritzBox), DNSSEC aus, kein DoT |
| `config/etc/nftables.conf` | eingehend zu, **SSH von ueberall** (Key-only) |
| `config/etc/ssh/sshd_config.d/…` | kein Passwort, kein root, `AllowUsers benny` |
| `config/etc/udev/rules.d/99-gamedac.rules` | USB-Autosuspend fuer `1038:1280/1282` aus |
| `config/etc/udev/rules.d/99-i2c.rules` | `ddcutil` darf `/dev/i2c-*` |
| `config/etc/wireplumber/…` | GameDAC: S32LE/48 kHz/2ch, Suspend aus |
| `config/etc/systemd/system-sleep/50-r8169-reset.sh` | Link nach S3 zurueckholen |
| `config/usr/local/bin/{game-performance,edge-performance}` | Performance-Profil + Inhibit |
| `config/usr/local/bin/asm-verify` | Statusbericht für Remote-Support (Sinks, Kanäle, Streams, Journal) |
| `pkgbuilds/arctis-sound-manager-fork` | Fork-Build (Git-Commit 2e5112fa) |

## Entscheidungen

- **ASM umschaltbar** über `ASM_FLAVOR` in `settings.env`:
  - `fork` (**Default**): eigener Build `1.4.27+fork.3` aus
    `pkgbuilds/arctis-sound-manager-fork` – genau der Stand, der mit dem
    GameDAC Gen1 monatelang lief. Bewusst konservativ, weil Benny nicht
    vor Ort testen kann.
  - `upstream`: AUR 1.7.10. Code-Vergleich zeigt: alle GameDAC-/7.1-Fixes
    sind dort enthalten (u. a. 8-Kanal-Capture, `stream.dont-remix=false`);
    ungetestet auf dieser Hardware.
  - `none`: nicht installieren (Audio laeuft dann ohne Sonar/EQ).
  Ein Wechsel ist eine Zeile + Neuinstallation des Pakets, kein Umbau.
- Der Fork hat upstream gegenüber nur noch vier Kleinigkeiten voraus
  (GameDAC-Rad → Default-Sink, Settings-RMW, ChatMix-Persistenz,
  Stream-Guard-PID) – keine davon ist fuer die Audio-Kette kritisch.
- **Entscheidung 2026-11-24:** Fork bleibt Default. Begründung: genau dieser
  Stand lief mit dem GameDAC Gen1; Benny kann nicht vor Ort testen und ist
  bei Problemen schnell überfordert. Upstream wird nur in einem ruhigen
  Fenster mit paralleler SSH-Begleitung getestet.
- **I2C=1** (anders als der alte Plan in `docs/STATUS.md` mit `I2C=0`): die
  NixOS-Config gibt Benny `i2c`-Gruppe, udev-Regel und `ddcutil`.
- **SSH oeffentlich**: bewusst, weil Benny nicht im eigenen Netz steht.

## Vor dem ersten echten Einsatz testen

1. `install-arch --host benny --disk /dev/sdX` (QEMU-Test reicht fuer den
   Ablauf; Intel-GPU laesst sich dort nur eingeschraenkt pruefen).
2. `vainfo` → muss `i965` zeigen; `vulkaninfo --summary` → `Intel(R) … (IVB)`.
3. `pactl list sinks` mit GameDAC → S32LE/48 kHz, kein Suspend.
4. `arctis-manager`/Tray starten, Sonar-Kette anlegen, 7.1-Quelle testen
   (`speaker-test -c8`): Center/Rear duerfen nicht doppelt ankommen.
   Danach `asm-verify` laufen lassen und die Datei `~/asm-check-*.txt` per
   SSH abholen – darin stehen Kanal-Layout, Node-Status, Streams, Journal.
5. Bei Problemen: `ASM_FLAVOR` in `settings.env` umstellen
   (`fork` ↔ `upstream`) und nur das Paket neu bauen/installieren – der Rest
   des Systems bleibt unberührt. Rückweg auf den Fork ist der Default.
6. SSH von `nex` aus: `ssh benny` (Key), Passwort-Login muss scheitern.
7. Nach S3: Netzwerk-Link pruefen (r8169-Hook).
