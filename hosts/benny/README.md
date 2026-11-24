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

## Entscheidungen

- **ASM: Upstream 1.7.10 aus der AUR**, nicht der eigene Fork. Der Fork
  backportete im Kern Upstream 1.4.28–1.4.34; „echtes 7.1 statt Doppel-Mix"
  ist seit **1.7.1** upstream (`loopback_manager.py`). Einziger
  Verhaltensunterschied: das GameDAC-Rad spiegelt upstream bewusst nicht in
  den Default-Sink – falls Benny das braucht, kommt es als Einzel-Patch obendrauf.
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
5. SSH von `nex` aus: `ssh benny` (Key), Passwort-Login muss scheitern.
6. Nach S3: Netzwerk-Link pruefen (r8169-Hook).
