#!/usr/bin/env bash
# Stellt Lions Home-Verzeichnis aus dem Backup wieder her.
#
# KOPIE ZUR SICHERUNG. Kanonisch liegt das Skript im Backup selbst:
#   nex:/home/mortiferus/backups/lion-pc/<datum>/restore-home.sh
# Es erwartet dort die Ordner home/, face.png und flatpak-apps.txt.
# Diese Repo-Kopie dient nur dazu, den Ablauf versioniert zu haben.

#
# Aufruf auf dem frisch installierten Lion (als lion):
#   ./restore-home.sh                 # Ziel: eigenes Home
#   ./restore-home.sh --flatpak       # zusätzlich Flatpak-Apps installieren
#   sudo ./restore-home.sh /home/lion # oder als root mit explizitem Ziel
#
# Braucht kein rsync: ein frisches Arch hat nur tar. Quelle ist das
# NixOS-Home von 2026-11-24; das Skript passt die NixOS-spezifischen Stellen
# an den Arch-Port an (Umbriel-Autostart, Firefox-Pfad, tote Symlinks,
# Profilbild, Bedrock-Welten).

set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$BASE/home"
TARGET_USER="${TARGET_USER:-lion}"
DO_FLATPAK=0
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --flatpak) DO_FLATPAK=1;;
    *) TARGET="$arg";;
  esac
done

TARGET="${TARGET:-$(getent passwd "$TARGET_USER" | cut -d: -f6)}"
GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")"

[ -d "$SRC" ] || { echo "Backup nicht gefunden: $SRC" >&2; exit 1; }
[ -n "$TARGET" ] || { echo "Ziel-Home nicht ermittelbar; Pfad als Argument angeben." >&2; exit 1; }
id "$TARGET_USER" >/dev/null 2>&1 || { echo "Benutzer $TARGET_USER existiert nicht." >&2; exit 1; }

IS_ROOT=0
if [ "$(id -u)" -eq 0 ]; then
  IS_ROOT=1
elif [ "$(id -un)" != "$TARGET_USER" ]; then
  echo "Als root oder als $TARGET_USER ausführen." >&2; exit 1
fi

mkdir -p "$TARGET"

echo "==> Kopiere Benutzerdaten nach $TARGET"
# Theme-/Session-Dateien kommen auf Arch aus dem Installer-Profil und werden
# nicht mit den NixOS-Versionen (tote /nix/store-Symlinks) überschrieben.
TAR_EXC=()
for e in ./.config/fish ./.config/autostart ./.config/gtk-3.0 ./.config/gtk-4.0 \
         ./.config/qt5ct ./.config/qt6ct ./.config/systemd ./.config/environment.d \
         ./.config/fontconfig ./.config/mimeapps.list ./.icons ./.gtkrc-2.0 \
         ./.local/state; do
  TAR_EXC+=("--exclude=$e")
done
tar -C "$SRC" -cf - "${TAR_EXC[@]}" . | tar -C "$TARGET" -xpf -

echo "==> Umbriel: Arch-Autostart setzen (Backup kam von NixOS/systemd)"
CFG="$TARGET/.config/umbriel/config.toml"
if [ -f "$CFG" ]; then
  sed -i 's/^autostart[[:space:]]*=[[:space:]]*\[\]/autostart = ["noctalia"]/' "$CFG"
  if grep -q '^autostart[[:space:]]*=[[:space:]]*\["noctalia"\]' "$CFG"; then
    echo "    autostart = [\"noctalia\"]"
  else
    echo "    WARNUNG: autostart in $CFG bitte manuell auf [\"noctalia\"] setzen" >&2
  fi
fi

echo "==> Firefox: NixOS-Pfad (~/.config/mozilla) nach Arch (~/.mozilla)"
if [ -d "$TARGET/.config/mozilla/firefox" ]; then
  mkdir -p "$TARGET/.mozilla/firefox"
  tar -C "$TARGET/.config/mozilla/firefox" -cf - . | tar -C "$TARGET/.mozilla/firefox" -xpf -
  # profiles.ini kam als NixOS-Symlink nach /nix/store mit.
  # Firefox 67+ waehlt das Profil ueber installs.ini; fehlt die Datei, legt es
  # ein neues default-release-Profil an und ignoriert Lion.
  rm -f "$TARGET/.mozilla/firefox/profiles.ini" "$TARGET/.mozilla/firefox/installs.ini"
  cat > "$TARGET/.mozilla/firefox/profiles.ini" <<'EOF'
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Default=1
IsRelative=1
Name=lion
Path=lion

[Install4F96D1932A9F858E]
Default=lion
Locked=1
EOF
  cat > "$TARGET/.mozilla/firefox/installs.ini" <<'EOF'
[4F96D1932A9F858E]
Default=lion
Locked=1
EOF
  if [ "$IS_ROOT" -eq 1 ]; then
    chown "$TARGET_USER:$GROUP" "$TARGET/.mozilla/firefox/profiles.ini" \
                                   "$TARGET/.mozilla/firefox/installs.ini"
  fi
  rm -rf "$TARGET/.config/mozilla"
  echo "    Profil 'lion' -> ~/.mozilla/firefox/lion"
fi

echo "==> Profilbild"
if [ -f "$BASE/face.png" ]; then
  rm -f "$TARGET/.face"   # im Backup ein toter /etc/nixos-Symlink
  if [ "$IS_ROOT" -eq 1 ]; then
    install -o "$TARGET_USER" -g "$GROUP" -m 644 "$BASE/face.png" "$TARGET/.face"
  else
    cp -f "$BASE/face.png" "$TARGET/.face"
  fi
  echo "    .face gesetzt"
fi

echo "==> NixOS-Reste entfernen"
rm -rf "$TARGET/.nix-profile" "$TARGET/.nix-defexpr" "$TARGET/.local/state/nix" \
       "$TARGET/.local/state/home-manager" "$TARGET/.config/home-manager"
# Alle toten Symlinks (NixOS: /nix/store, /etc/nixos, alte Pulse-Sockets)
find "$TARGET" -type l -xtype l -print -delete 2>/dev/null || true

echo "==> Minecraft-Bedrock-Welten"
WORLDS="$TARGET/.local/share/bedrock-on-linux/minecraft-welten"
PREFIX="$TARGET/.local/share/bedrock-on-linux/compatdata/pfx/drive_c/users/steamuser/AppData/Roaming/Minecraft Bedrock"
if [ -d "$WORLDS" ] && [ -d "$PREFIX" ]; then
  cp -a "$WORLDS"/. "$PREFIX"/
  echo "    Welten in den Bedrock-Prefix kopiert"
elif [ -d "$WORLDS" ]; then
  echo "    Bedrock-Client einmal starten, danach erneut ausführen;"
  echo "    Welten liegen unter $WORLDS"
fi

if [ "$DO_FLATPAK" -eq 1 ] && [ -f "$BASE/flatpak-apps.txt" ]; then
  echo "==> Flatpak-Apps installieren"
  run_as() {
    if [ "$IS_ROOT" -eq 1 ]; then su - "$TARGET_USER" -c "$1"; else bash -lc "$1"; fi
  }
  run_as 'flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo' || true
  while read -r app; do
    [ -n "$app" ] || continue
    run_as "flatpak install -y --user flathub $app" || echo "    $app fehlgeschlagen" >&2
  done < "$BASE/flatpak-apps.txt"
fi

echo
echo "==> Fertig. Kurz prüfen:"
echo "    ls -la $TARGET"
echo "    Danach als $TARGET_USER anmelden."
echo
echo "Neu einzurichten (nicht Teil des Backups):"
echo "  - WLAN-Zugang (NetworkManager; SSID Mortiferus6)"
echo "  - Steam-Spiele auf /gaming sind vorhanden und werden erkannt"
echo "  - Browser-Passwörter: Schlüsselbund fragt nach dem alten Login-Passwort"
