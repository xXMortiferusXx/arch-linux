# Arch-Fix – verifizierte Fehlerbilder auf `nex`

Stand: 2026-11-24. Bezug: Port von NixOS nach Arch (`docs/STATUS.md`).
Hier stehen nur Dinge, die auf dem **laufenden** System reproduziert und
behoben wurden – jeweils mit Ursache, Sofort-Fix und dem Fix für den
Installer. Ziel: Eine Neuinstallation liefert diese Fehler nicht mehr.

Betroffen: `nex` (Legion 5, Ryzen 5 5600H + RTX 3070 Mobile), Umbriel +
Noctalia + noctalia-greeter (greetd).

> **Stand der Umsetzung:** Die Fixes aus § 1, § 2 und § 5 sowie der
> PAM-Fix aus § 3 sind im Installer eingebaut
> (`hosts/{nex,lion-pc}/home/.config/umbriel/config.toml`, `install.sh`,
> `lib/base.sh`, `lib/extras.sh`). Noch **nicht** durch einen kompletten
> ISO-Installationslauf validiert – bisher nur `bash -n`, isolierte Tests
> der `awk`-/`find`-Snippets und Abgleich mit dem laufenden System.

---

## 1. Noctalia startet nach dem Login nicht

### Symptom
Nach dem Login läuft Umbriel, aber es gibt keine Bar, kein Wallpaper, keine
Shell. `pgrep noctalia` ist leer. Auf tty1 läuft die Wayland-Session, auf
tty2 nur die Textkonsole – das ist **nicht** die Ursache, sondern nur der
Grund, warum es zuerst so aussah.

### Ursache
`~/.config/umbriel/config.toml` hatte:

```toml
[general]
autostart = []

[include.optional]
files = ["../autostart.nix"]   # NixOS-Relikt
```

Auf NixOS kamen die Autostarts aus `autostart.nix` (systemd-User-Units). Auf
Arch existiert diese Datei und die Units nicht. Umbriel startet also nichts.

### Fix
```toml
[general]
autostart = ["noctalia"]
```

Das NixOS-Include ist entfernt, der Kommentar in der Datei erklärt jetzt,
dass Umbriel die Shell selbst startet.

**Wichtig:** Noctalia darf **nicht zusätzlich** über
`~/.config/autostart/*.desktop` oder eine systemd-User-Unit starten – sonst
laufen zwei Instanzen (doppelte Bar, doppelte IPC-Antworten).

### Installer
- `hosts/*/home/.config/umbriel/config.toml` muss
  `autostart = ["noctalia"]` enthalten.
- Kein `autostart.nix`-Include, keine Noctalia-Unit, kein XDG-Autostart.
- Prüfen: `pgrep -a noctalia` und `ps -o pid,ppid,comm -C noctalia`
  (PPID muss Umbriel sein).

---

## 2. Greeter-Sync: „refusing untrusted greeter sync helper“

### Symptom
`noctalia msg greeter-sync` scheitert, im Journal steht:

```
refusing untrusted greeter sync helper
```

Der Greeter behält Wallpaper/Palette/Font der Standard-Installation.

### Ursache (zwei Blocker)

1. **`/usr` war `775 root:root`** (gruppen-schreibbar). Der Greeter-Sync
   prüft alle Elternverzeichnisse des Helpers; ein gruppen- oder
   welt-schreibbarer Pfad gilt als unsicher → Helper wird abgelehnt.
   Betroffen waren `/usr`, `/usr/local`, `/usr/local/bin`.
2. **`/etc/polkit-1` war `775 root:root`**. Dadurch wurden die
   Polkit-Regeln nicht zuverlässig geladen und `pkexec` konnte den Aufruf
   nicht autorisieren.

Beides kam vom Installer, siehe § 5 (Ursache: `cp -a` der Config-Overlays).

### Fix (Sofort)
```bash
sudo chmod 755 /usr /usr/local /usr/local/bin
sudo chmod 755 /etc/polkit-1
```

Passwortlosen Sync für den Benutzer aktivieren:
```bash
sudo noctalia-greeter passwordless-sync enable mortiferus
# -> Enabled passwordless appearance sync for 'mortiferus'.
```

Ergebnis: `/etc/polkit-1/rules.d/49-noctalia-greeter-passwordless-sync.rules`
(Verzeichnis ist `750 root:polkitd`, deshalb braucht `status`/`ls` dort
`sudo`).

### Wichtig: Neustart von Noctalia nötig
Der IPC-Handler `greeter-sync` wird **nur beim Start** von Noctalia
registriert. Vor dem Fix lief der Helper noch als „untrusted“, deshalb
antwortete der laufende Prozess weiter mit `error: unknown command`.
Nach einmal Aus-/Einloggen (oder Reboot) ist der Handler da.

### Settings (bleiben so)
`~/.local/state/noctalia/settings.toml`:

```toml
[shell]
polkit_agent = true

[shell.greeter_sync]
auto_sync = true
privilege_command = "pkexec"
```

`auto_sync = true` überträgt Änderungen an Wallpaper, Palette, Theme-Modus
und Shell-Font (kurz debounced) automatisch. Für eine reine
Corner-Radius-Änderung reicht das nicht – dann einmal
`noctalia msg greeter-sync`.

### Verifikation
```bash
noctalia msg greeter-sync                    # -> ok
journalctl --user -b | grep -i 'greeter-sync'
```
Erwartete Zeilen (gekürzt):
```
[greeter-sync] greeter sync: staging output_transforms "eDP-1:normal"
[greeter-sync] greeter sync: staging output_scales "eDP-1:1.000"
[greeter-sync] greeter sync: staged wallpaper for 'eDP-1' -> wallpaper-eDP-1.png
[greeter-sync] synced shell appearance to greeter
```
```bash
sudo ls -l /var/lib/noctalia-greeter/        # sync.toml + wallpaper-eDP-*.png
sudo cat /var/lib/noctalia-greeter/sync.toml
sudo noctalia-greeter passwordless-sync status mortiferus
```
Dann ausloggen: Der Greeter liest `sync.toml` beim Start und zeigt das
Design.

### Installer (eingebaut)
- `/var/lib/noctalia-greeter` als `750 greeter:greeter` anlegen und
  `greeter.toml` (644, `greeter:greeter`) hineinlegen – war schon so.
- Rechte-Normalisierung nach dem Overlay-Kopieren in `lib/base.sh`
  (siehe § 5) → `/usr` ist beim Sync vertrauenswürdig.
- `extras_desktop` ruft im Chroot jetzt
  `noctalia-greeter passwordless-sync enable "$username"` auf – nach der
  Rechte-Normalisierung, vor dem ersten Login. Schlägt es fehl, gibt es
  nur eine Warnung mit dem Nachhol-Befehl (kein Abbruch der Installation).
- **Offen:** Prüfen, ob
  `hosts/nex/config/etc/polkit-1/rules.d/50-noctalia-sync.rules` noch
  gebraucht wird. Die Regel adressiert die alte Action
  `org.noctalia.greeter.sync-appearance`; die aktuelle
  `noctalia-greeter`-Version legt ihre Regel selbst über
  `passwordless-sync enable` ab. Doppelte Regeln schaden nicht, die alte
  Action-ID greift aber evtl. nicht mehr.

---

## 3. GNOME-Keyring wird beim Login nicht entsperrt

### Symptom
Nach dem Login erscheint ein Dialog „Der Schlüsselbund … wurde nicht
entsperrt“ (gcr-prompter). Im Journal:

```
gkr-pam: no password is available for user
gnome-keyring-daemon: couldn't unlock the login keyring
```

Unter NixOS trat das nicht auf, weil das PAM-Modul die Zeile korrekt
einsortiert hat.

### Ursache
`lib/extras.sh` (`extras_keyring`, ca. Zeile 445) fügt die auth-Zeile so ein:

```sh
sed -i '1a auth       optional     pam_gnome_keyring.so' "$f"
```

Das landet direkt nach `#%PAM-1.0`, also **vor** `auth include
system-local-login`. Zu diesem Zeitpunkt hat `pam_unix` das Passwort noch
nicht geprüft und `PAM_AUTHTOK` ist leer → `gkr-pam` meldet „no password is
available“ und der Bund bleibt zu.

Aktueller (falscher) Stand auf `nex`:

```
1  #%PAM-1.0
2  auth       optional     pam_gnome_keyring.so     <- zu früh
4  auth       requisite    pam_nologin.so
5  auth       include      system-local-login
...
9  session    optional     pam_gnome_keyring.so auto_start   <- korrekt
```

`/etc/pam.d/greetd` und `/etc/pam.d/login` sind beide betroffen. Die
Paket-Defaults (`greetd`, `util-linux`) enthalten **keine**
Keyring-Zeilen – der Installer muss sie also selbst und an der richtigen
Stelle setzen.

### Korrekte Reihenfolge
Die auth-Zeile gehört **hinter** den letzten `auth`-Eintrag (bzw. hinter
`auth include system-local-login`), die session-Zeile ans Ende:

```
#%PAM-1.0

auth       required     pam_securetty.so
auth       requisite    pam_nologin.so
auth       include      system-local-login
auth       optional     pam_gnome_keyring.so

account    include      system-local-login
session    include      system-local-login
session    optional     pam_gnome_keyring.so auto_start
```

`use_authtok` ist nicht nötig und für Fingerprint-Logins sogar schädlich
(dort gibt es kein Passwort, der Login soll trotzdem funktionieren).

### Fix (Sofort)
Fertiges Skript liegt unter `/tmp/opencode/pam-keyring-fix.sh`:

```bash
sudo bash /tmp/opencode/pam-keyring-fix.sh
grep -n pam_gnome_keyring /etc/pam.d/greetd /etc/pam.d/login
```

Es legt Backups (`*.bak-<datum>`) an, entfernt eine evtl. vorhandene
falsche auth-Zeile und setzt sie hinter den letzten `auth`-Eintrag. Danach
einmal neu einloggen.

### Installer (eingebaut in `lib/extras.sh`, `extras_keyring`)

Der Code unten ist 1:1 der eingebaute Stand. Wichtig: kein
„schon vorhanden“-Guard mehr – eine falsch platzierte Zeile aus einer alten
Installation wird sonst nie repariert. Die Session-Zeile wird nur ergänzt,
wenn sie fehlt.

```sh
extras_keyring() {
  ui_step "Schluesselbund (gnome-keyring)"
  local pam f
  for pam in login greetd; do
    f="$TARGET/etc/pam.d/$pam"
    [ -f "$f" ] || continue

    # WICHTIG: Die auth-Zeile muss HINTER dem auth-include stehen. Erst dort
    # hat pam_unix PAM_AUTHTOK gesetzt; davor meldet gkr-pam "no password is
    # available for user" und der Bund bleibt zu.
    # Bewusst kein "schon vorhanden"-Guard: eine falsch platzierte Zeile aus
    # einer alten Installation wird so bei jedem Lauf korrigiert.
    awk '
      /^auth[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so([[:space:]]|$)/ { next }
      { line[++n] = $0 }
      END {
        last = 0
        for (i = 1; i <= n; i++)
          if (line[i] ~ /^auth[[:space:]]/) last = i
        for (i = 1; i <= n; i++) {
          print line[i]
          if (i == last) print "auth       optional     pam_gnome_keyring.so"
        }
      }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

    # session-Zeile genau einmal, ans Ende (startet den Daemon und entriegelt)
    grep -qE '^session[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so' "$f" \
      || printf 'session    optional     pam_gnome_keyring.so auto_start\n' >> "$f"
  done
  ui_ok "PAM: Keyring entriegelt automatisch beim Login"
}
```

Auf `nex` wurde derselbe Stand mit `/tmp/opencode/pam-keyring-fix.sh`
angewendet; das Skript legt Backups (`*.bak-<datum>`) an.

### Verifikation
```bash
grep -n pam_gnome_keyring /etc/pam.d/greetd /etc/pam.d/login
journalctl -b | grep -i gkr-pam     # darf NICHT "no password is available" zeigen
```
Nach dem Re-Login: kein Keyring-Dialog mehr. Falls doch, hat der Bund ein
**anderes Passwort** als das Login-Passwort (z. B. weil er beim ersten
Prompt mit leerem/abweichendem Passwort angelegt wurde) → in Seahorse
(„Passwörter und Schlüssel“ → Standard-Schlüsselbund → Passwort ändern) auf
das Login-Passwort setzen.

Hinweis: Bei Login per Fingerprint gibt es grundsätzlich kein Passwort für
`gkr-pam`; dann bleibt nur ein separater Mechanismus (TPM/`pam_gaze`) oder
der Keyring bleibt zu. Für Passwort-Login über greetd ist die Reihenfolge
oben die vollständige Lösung.

---

## 4. Weitere Auffälligkeiten (keine Blocker)

### 4.1 Gruppen-schreibbare Verzeichnisse unter `/etc`
Nach der Installation waren 26 Root-Verzeichnisse `775 root:root`, u. a.
`/etc/systemd`, `/etc/systemd/system`, `/etc/udev`, `/etc/NetworkManager`,
`/etc/pipewire`, `/etc/wireplumber`, `/etc/xdg`, `/etc/modprobe.d`,
`/etc/sysctl.d`, `/etc/tmpfiles.d`, `/etc/fastfetch`, `/etc/firefox`.

Ursache und Fix: § 5. Auf `nex` bereits bereinigt (bis auf die 26
`/etc`-Verzeichnisse, die man mit einem Einzeiler nachziehen kann):

```bash
sudo find /etc -xdev -type d -perm -0020 -user root -group root -exec chmod g-w {} +
```

### 4.2 `display.toml`: GPU-/Konnektor-Kommentar vertauscht
Der Kommentar in `hosts/nex/home/.config/umbriel/cfg/display.toml` sagt:
PRIME-Hybrid (AMD iGPU) → `eDP-2`, dGPU-only → `eDP-1`. Auf `nex` ist es
umgekehrt: `eDP-1` ist das Panel (AU Optronics, AMD iGPU), `eDP-2` gehört
zur NVIDIA-dGPU und ist im Hybrid-Betrieb disconnected. Beide
`[output]`-Blöcke sind inhaltlich identisch, daher ist es nur ein
Doku-Fehler – aber ein irreführender. Bitte beim nächsten Edit korrigieren.

### 4.3 `systemctl --user restart umbriel.service` startet den nested Backend
Die User-Manager-Umgebung kann `WAYLAND_DISPLAY=wayland-0` enthalten. Ein
Restart von `umbriel.service` erbt das und Umbriel versucht dann den
nested Wayland-Backend statt DRM. `start-umbriel` räumt die Variablen beim
Login-Rentry auf, ein manueller Restart tut das nicht.

Optionale Härtung (Drop-in):
```ini
# /etc/systemd/user/umbriel.service.d/10-unset-wayland.conf
[Service]
UnsetEnvironment=WAYLAND_DISPLAY WAYLAND_SOCKET DISPLAY
```

### 4.4 `noctalia-greeter passwordless-sync status` braucht `sudo`
Auf `nex` ist `/etc/polkit-1/rules.d` `750 root:polkitd` – das ist der
Paket-Default. Als normaler Benutzer scheitert das Lesen, mit `sudo`
funktioniert es. Nach einer frischen Installation mit normalisierten
Rechten ist der Ordner `755 root:root`; dann geht `status` auch ohne
`sudo` (siehe § 5, „Bewusste Abweichung“).

### 4.5 `sudoers.d`: der letzte Treffer gewinnt
`/etc/sudoers.d/wheel` enthält `%wheel ALL=(ALL:ALL) ALL` (Passwortpflicht).
Eine NOPASSWD-Regel in `10-…` oder `99-…` wird **davor** gelesen und damit
überschrieben – Ziffern sortieren vor Buchstaben, `wheel` kommt zuletzt.
Deshalb heißt die nex-Regel `zzz-mortiferus-nopasswd`. Weitere Fallstricke:

- Modus `0440 root:root` – sudo ignoriert falsch berechtigte Dateien.
- Dateinamen ohne `.` – sudo überspringt in `sudoers.d` Dateien, die auf
  `~` enden oder einen Punkt enthalten (Editor-/Paket-Backups).
- Prüfen mit `sudo visudo -c` (parst auch die Drop-ins, aber **nicht** die
  Reihenfolge) und `sudo -k; sudo -n true`.

Im Installer: `NOPASSWD_SUDO=1` in `hosts/nex/settings.env` (lion: `0`),
erzeugt in `lib/base.sh` direkt nach der `wheel`-Datei.

---

## 5. Installer-Fix: Rechte nach dem Overlay-Kopieren normalisieren

### Ursache
`lib/base.sh` kopiert die Config-Overlays mit `cp -a`:

```sh
cp -a "${REPO_DIR:-.}/shared/config/." "$TARGET/"
cp -a "$profile/config/." "$TARGET/"
```

`cp -a` erhält Verzeichnis-Modi. Git speichert keine Verzeichnis-Modi; der
Checkout (bzw. der ISO-Build) lief mit `umask 002`, also entstanden die
Verzeichnisse im Repo als `775`. Beim Mergen auf das Zielsystem werden
diese Modi auf die **bestehenden** Verzeichnisse wie `/usr`, `/etc/systemd`
usw. angewendet – daher `775 root:root` und die abgelehnten Helper.

Dass genau die Verzeichnisse betroffen sind, die es im Overlay gibt
(`shared/config/usr`, `shared/config/etc/...`), bestätigt die Ursache.

### Fix (eingebaut)
1. `install.sh`, direkt nach `set -Eeuo pipefail`:
   ```sh
   umask 022
   ```
2. `lib/base.sh`, nach beiden Overlay-`cp -a`-Aufrufen:
   ```sh
   if [ -d "$TARGET/etc" ]; then
     find "$TARGET/etc" "$TARGET/usr" -xdev \
       \( -type d -o -type f \) -perm /022 -user root -group root \
       -exec chmod go-w {} + 2>/dev/null || true
   fi
   ```
   (`-perm /022` = Gruppen- **oder** Andere-Schreibrecht gesetzt;
   `chmod go-w` entfernt nur das Schreibrecht, `r-x` und Exec-Bits
   bleiben. Gilt bewusst auch für Dateien: ein gruppen-schreibbares
   Skript in `/usr/local/bin` wäre derselbe Vertrauensbruch.)

**Warum nicht `cp -a --no-preserve=mode`?** Getestet: cp legt neue Dateien
dann mit `0666 & ~umask` an, also `644` – das Exec-Bit der Skripte in
`usr/local/bin` geht verloren. Die Normalisierung nach `cp -a` ist
deshalb der richtige Weg.

**Bewusste Abweichung:** `/etc/polkit-1/rules.d` ist im Paket
`750 root:polkitd`, nach der Normalisierung `755 root:root`. Funktional
unkritisch (polkitd liest die Regeln weiterhin, der Ordner ist nicht
schreibbar) – nur `noctalia-greeter passwordless-sync status` braucht dann
kein `sudo` mehr.

### Prüfen (nach Installation)
```bash
find /usr /usr/local /etc -xdev -type d -perm -0020 -user root -group root
# muss leer sein (bzw. nur bewusst gruppen-schreibbare Pfade zeigen)
stat -c '%a %U:%G %n' /usr /usr/local /usr/local/bin /etc/polkit-1
```

---

## 6. Checkliste nach einer Neuinstallation

```bash
# 1) Shell-Autostart
pgrep -a noctalia
noctalia msg status
ps -o pid,ppid,comm -C noctalia          # PPID = umbriel

# 2) Rechte (Voraussetzung fuer Greeter-Sync/pkexec)
stat -c '%a %U:%G %n' /usr /usr/local /usr/local/bin /etc/polkit-1
sudo find /etc -xdev -type d -perm -0020 -user root -group root

# 3) Greeter-Sync
noctalia msg greeter-sync                       # -> ok
journalctl --user -b | grep -i greeter-sync
sudo ls -l /var/lib/noctalia-greeter/
sudo cat /var/lib/noctalia-greeter/sync.toml
sudo noctalia-greeter passwordless-sync status <user>

# 4) Keyring
grep -n pam_gnome_keyring /etc/pam.d/greetd /etc/pam.d/login
journalctl -b | grep -i gkr-pam                 # kein "no password is available"

# 5) Optik
#    ausloggen -> Greeter muss Wallpaper/Palette/Font/Layout zeigen
```

Wenn 2–4 passen, ist der Rest (Wallpaper, Palette, Font, Layout im Greeter)
automatisch korrekt – `auto_sync = true` übernimmt das beim Login und bei
Änderungen.

---

## 7. Umgesetzte Änderungen (2026-11-24)

| Datei | Änderung |
|---|---|
| `hosts/nex/home/.config/umbriel/config.toml` | `autostart = ["noctalia"]`, NixOS-Kommentar ersetzt |
| `hosts/lion-pc/home/.config/umbriel/config.toml` | dito |
| `install.sh` | `umask 022` nach `set -Eeuo pipefail` |
| `lib/base.sh` | Rechte-Normalisierung (`go-w`) nach den Overlay-`cp -a`-Aufrufen; `NOPASSWD_SUDO=1` erzeugt `zzz-<user>-nopasswd` |
| `hosts/nex/settings.env` | `NOPASSWD_SUDO=1` (sudo ohne Passwort) |
| `hosts/lion-pc/settings.env` | `NOPASSWD_SUDO=0` (lion behält die Abfrage) |
| `lib/extras.sh` (`extras_keyring`) | PAM-Reihenfolge via `awk`, „schon vorhanden“-Guard entfernt |
| `lib/extras.sh` (`extras_desktop`) | `noctalia-greeter passwordless-sync enable "$username"` im Chroot |
| `docs/STATUS.md` | Verweis auf diese Datei |

Noch offen: kompletter Testlauf über die ISO (`./scripts/build-iso.sh` +
`test/test-installer.sh`), danach die Checkliste aus § 6 auf dem
installierten System. Die laufende Maschine `nex` wurde zusätzlich manuell
gefixt (Rechte, PAM, passwordless-sync) – dokumentiert in § 1–3. Die
zweite Runde (Audio, udev, Greeter-Home, WLAN-Regdomain) steht in § 8.

---

## 8. Weitere Portierungsfehler (2026-11-24)

Beim ersten vollständigen Systemcheck nach dem Login gefunden, live auf
`nex` behoben und ins Installer-Overlay übernommen.

### 8.1 WirePlumber: zusammengesetzte Schlüssel sind kein SPA-JSON
Die aus NixOS übernommene `90-gc7.conf` enthielt
`actions."update-props"."priorities" = [...]`. SPA-JSON verkettet keine
gequoteten Schlüsselteile mit Punkten; WirePlumber verwirft die ganze
Datei:

```
wp-conf: failed to open '.../90-gc7.conf':
section 'device.profile.priority.rules' has no value
```

Folge: weder die Profil-Priorität noch `monitor.alsa.rules` wurden geladen;
die GC7 blieb auf `analog-stereo` (kein 7.1-Game-/Voice-Stream, kein
ChatMix). Richtig ist die dokumentierte Form:

```
actions = {
    update-props = {
        priorities = [ "pro-audio" ]
    }
}
```

Verifiziert: `pactl list cards` → `Active Profile: pro-audio`;
`wpctl status` listet `GC7 Game (7.1)` und `GC7 Voice (Chat)`.

### 8.2 `param_eq`: `config.filename` ist kein Node-Schlüssel
In PipeWire 1.6 gehört der Dateiname in die `config`-Sektion:

```
config = { filename = "/etc/pipewire/mmx330-filters.txt" }
```

Vorher: `spa.filter-graph: unexpected node key 'config.filename'` und
`param_eq: requires a config section`. Der virtuelle Sink erschien zwar,
blieb aber stumm. Nach dem Fix lädt der Graph beim ersten Ton ohne Fehler
(Test mit `pw-play`, `pw-top` zeigt 8 Kanäle @ 48 kHz).

### 8.3 udev `RUN`: `$$`-Escapes beim Port verloren
NixOS schreibt die Regel als `$$(cat ...)`: udev ersetzt `$$` durch ein
literales `$` und übergibt erst dann an `/bin/sh -c`. In der Arch-Datei
standen nur noch `$(...)`; udev deutet das als eigene Substitution:

```
Invalid value "..." for RUN (char 101: invalid substitution type)
```

Dadurch wurde `snd_hda_intel.power_save` nie geschaltet. Statt die Escapes
zu reparieren, liegt die Logik jetzt in
`/usr/local/bin/snd-hda-powersave` (`init|ac|battery`); die Regeln rufen
nur noch das Skript auf. Getestet: `battery` → 10, `ac` → 0.

### 8.4 Greeter ohne HOME
Das `greetd`-Paket legt `greeter` mit `HOME=/` an; der Keyring im
Greeter-Session scheiterte mit
`unable to create keyring dir: /.local/share/keyrings`. `extras_desktop`
setzt das Home jetzt auch bei bereits existierendem User per
`usermod -d /var/lib/noctalia-greeter`. Live nachgezogen; der Ordner ist
`750 greeter:greeter` und für den Keyring beschreibbar.

### 8.5 WLAN-Regdomain
`/etc/udev/rules.d/99-wifi-regdom.rules` (`iw reg set DE`) war
wirkungslos: `wireless-regdb` fehlte, und die Intel-Karte ist ein
self-managed wiphy (LAR). Jetzt: `wireless-regdb` in
`shared/packages.list`, `Country=DE` in `etc/iwd/main.conf`, die udev-Regel
entfällt. Die Karte zeigt bereits `country DE` (vom AP); die globale
Regdomain greift nach dem nächsten Reboot.

### 8.6 Anzeige-Kommentare
`cfg/display.toml` behauptete, im Hybridbetrieb fahre die iGPU `eDP-2`.
Tatsächlich ist `card1` (amdgpu) = `eDP-1` (verbunden) und `card0`
(nvidia) = `eDP-2` (getrennt). Nur Kommentare und Überschriften getauscht;
die beiden Output-Blöcke bleiben inhaltlich identisch.

### 8.7 Beim Abgleich mit `kernel-tuning.nix` nachgezogen

Zwei Punkte aus der NixOS-Vorlage fehlten noch:

- **bpftune** (`services.bpftune.enable`): `bpftune-git` kommt aus chaotic
  und wird deshalb erst in `extras_system` installiert (pacstrap kennt das
  Repo noch nicht). Live getestet: `bpftune works fully`.
- **`security.pam.loginLimits`**: `@audio - rtprio 99` in
  `etc/security/limits.d/99-audio.conf`. `pam_limits.so` ist in
  `system-auth`/`system-services` aktiv; das Limit greift ab dem nächsten
  Login.

### 8.8 Lion-Härtung (Bazaar/Flatpak/OBEX/mpv/Bedrock/Tray)

Beim Abgleich mit dem NixOS-Lion-Profil zusätzlich geschlossen:

- **Bazaar-Auto-Update**: `dconf`-Default `io/github/kolunmi/Bazaar
  auto-update=true` (Profil `user`, `system-db:local`), `dconf update` im
  Installer. Das Arch-Paket bringt die User-Unit
  `io.github.kolunmi.Bazaar.service` bereits mit, aber ohne `[Install]`;
  deshalb ein Symlink in `graphical-session.target.wants`.
- **Flathub**: mitgelieferte `flathub.flatpakrepo` (kein DNS/Netz im
  Chroot nötig) plus `flatpak-key-refresh.timer` für Schlüsselrotation.
- **OBEX**: `bluez-obex` + Drop-in (`--auto-accept`,
  `~/Downloads/Bluetooth`), gestartet über `graphical-session.target`.
- **`mpv`**: fehlte in der gemeinsamen Paketliste (NixOS-Lion hatte es).
- **Bedrock**: NixOS-Lion nutzte `BedrockOnLinux` (Windows-GDK-Client via
  Wine) mit echten Xbox-Friends und Einladungen. Auf Arch gibt es kein
  Paket, aber ein offizielles AppImage. `BEDROCK=1` (nur lion) lädt v2.3.1
  SHA256-geprüft nach `~/Applications/BedrockOnLinux.AppImage` und legt
  einen Desktop-Eintrag an. `mcpelauncher` wird bewusst **nicht** verwendet:
  dessen Doku bestätigt, dass es keine Xbox-Live-Einladungen empfangen kann
  und Friend-Joins unzuverlässig sind.
  Erststart lädt das Spiel über den eigenen Microsoft-Account; Friends,
  Einladungen, Server und Realms funktionieren wie unter Windows. Alte
  Welten liegen unter
  `~/.local/share/bedrock-on-linux/compatdata/pfx/drive_c/users/steamuser/AppData/Roaming/Minecraft Bedrock`
  und müssen vor einem Wipe gesichert werden.
- **arch-update-Tray**: eigener User-Service, der auf Noctalias
  SNI-Watcher wartet; `ShowTrayWhenRelevant` entfernt, damit das Icon
  dauerhaft sichtbar ist.

### 8.9 MIME-Defaults aus NixOS übernommen

`modules/home/apps/mimeapps.nix` gilt jetzt auch auf Arch, als
`shared/home/.config/mimeapps.list` (für nex und lion):

- PDF → `org.pwmt.zathura-pdf-mupdf.desktop` (Backend `zathura-pdf-mupdf`
  ist Pflicht, sonst startet Zathura leer). Der User-Override nutzt `%F`
  statt `%U`, damit Thunar Dateipfade statt `file://`-URIs übergibt.
- Bilder (PNG/BMP/JPEG/GIF/WebP/TIFF/SVG) → `org.gnome.Loupe.desktop`
- Video → `mpv.desktop`
- Audio → `io.bassi.Amberol.desktop`
- Text/Code → `nvim.desktop`
- Browser/HTTP → `firefox.desktop`
- Mail → `org.mozilla.Thunderbird.desktop` (Arch-ID; NixOS nutzte
  `thunderbird.desktop`)
- Ordner → `thunar.desktop`

`amberol` und `mpv` wurden dafür in die gemeinsame Paketliste aufgenommen.
Live geprüft: `xdg-mime query default` liefert für alle Beispiele die
richtigen Programme.

### 8.10 Leiser Umbriel-Login

Beim Login über den Noctalia-Greeter blitzten Umbriel-Startmeldungen kurz
auf dem VT auf. `/usr/local/bin/start-umbriel` (vor `/usr/bin` im
greetd-PATH) startet jetzt `/usr/bin/start-umbriel` mit
`>/dev/null 2>&1`; das Paket-Skript bleibt unangetastet. Zum Debuggen
direkt `/usr/bin/start-umbriel` aufrufen.

### 8.11 Geänderte Dateien

| Datei | Änderung |
|---|---|
| `hosts/nex/config/etc/pipewire/pipewire.conf.d/99-gc7-eq.conf` | `config = { filename = ... }` |
| `hosts/nex/config/etc/wireplumber/wireplumber.conf.d/90-gc7.conf` | gültiges SPA-JSON (`actions = { update-props = { ... } }`) |
| `shared/config/etc/udev/rules.d/60-tuning.rules` | `RUN` ruft `snd-hda-powersave` statt Shell-Einzeiler |
| `shared/config/usr/local/bin/snd-hda-powersave` | neu: power_save-Umschaltung AC/Akku |
| `shared/config/etc/iwd/main.conf` | neu: `Country=DE` |
| `shared/config/etc/udev/rules.d/99-wifi-regdom.rules` | entfällt (wirkungslos) |
| `shared/packages.list` | `wireless-regdb` |
| `lib/extras.sh` (`extras_desktop`) | `usermod -d /var/lib/noctalia-greeter` für `greeter` |
| `lib/extras.sh` (`extras_system`) | `bpftune-git` + `bpftune.service` |
| `shared/config/etc/security/limits.d/99-audio.conf` | neu: `@audio - rtprio 99` |
| `shared/home/.config/systemd/user/arch-update-tray.service` | neu: Tray-Service (wartet auf SNI-Host) |
| `shared/home/.config/arch-update/arch-update.conf` | Tray immer sichtbar |
| `shared/config/etc/dconf/profile/user`, `.../db/local.d/00-bazaar` | Bazaar `auto-update=true` |
| `shared/config/usr/share/flatpak/flathub.flatpakrepo` | Flathub-Repo offline verfügbar |
| `shared/config/usr/local/bin/flatpak-key-refresh` | GPG-Key-Refresh |
| `shared/config/etc/systemd/system/flatpak-key-refresh.{service,timer}` | täglicher Key-Refresh |
| `lib/extras.sh` (`extras_flatpak`) | lokale `.flatpakrepo`, `dconf update`, Key-Timer |
| `lib/extras.sh` (`extras_gaming`) | `BedrockOnLinux`-AppImage (v2.3.1, SHA256) für `BEDROCK=1` |
| `hosts/lion-pc/settings.env` | `BEDROCK=1` |
| `hosts/lion-pc/home/.../settings.toml.baseline` | `nix-monitor` und Discord-Nix-Pfad entfernt |
| `hosts/lion-pc/home/.../graphical-session.target.wants/io.github.kolunmi.Bazaar.service` | Bazaar-Daemon beim Login |
| `shared/home/.config/systemd/user/obex.service.d/10-auto-accept.conf` | OBEX Auto-Accept |
| `shared/packages.list` | `mpv`, `amberol`, `bluez-obex`, `zathura-pdf-mupdf` |
| `shared/home/.config/mimeapps.list` | NixOS-MIME-Defaults (zathura/Loupe/mpv/Amberol/nvim/Thunderbird) |
| `shared/home/.local/share/applications/org.pwmt.zathura-pdf-mupdf.desktop` | `%F`-Override für Thunar |
| `shared/config/usr/local/bin/start-umbriel` | leiser Login-Wrapper (stdout/stderr → `/dev/null`) |
| `hosts/nex/home/.config/umbriel/cfg/display.toml` | eDP-Zuordnung in den Kommentaren korrigiert |
