# archiso-Profil (Installer-ISO)

Basis ist das offizielle `releng`-Profil, das um unsere Anpassungen ergaenzt
wird. `releng` selbst wird **nicht** eingecheckt (Bootloader-Configs, viele
Dateien), sondern beim Build kopiert:

```bash
cp -r /usr/share/archiso/configs/releng/. .
# danach unsere Dateien darueberkopieren (dieses Verzeichnis ist die Quelle)
```

## Was hier drin ist

| Datei | Zweck |
|---|---|
| `packages.x86_64` | Paketliste inkl. NetworkManager (-> `nmtui`) und Firmware |
| `airootfs/etc/issue` | Hinweis auf `nmtui` + `install-arch` auf tty1 |
| `airootfs/etc/vconsole.conf` | deutsche Tastatur (`de-latin1`) |
| `airootfs/usr/local/bin/install-arch` | holt `install.sh` aus `main`, prueft SHA256, startet |
| `airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf` | Root-Autologin auf tty1 |

## Build (in einer Arch-Umgebung)

```bash
pacman -S --needed archiso
mkarchiso -v -w work -o out .
```

Ergebnis: `out/arch-install-<datum>-x86_64.iso` (+ `.sha256`).
`work/` und `out/` sind per `.gitignore` ausgeschlossen.
