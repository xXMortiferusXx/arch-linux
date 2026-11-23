#!/usr/bin/env bash
# Host-spezifisches Post-Skript (laeuft am Ende von install.sh, als root,
# mit $1 = Ziel-Root).
#
# Bewusst leer: hier kommen Dinge hinein, die sich nicht als Paket/Config
# abbilden lassen (z. B. chaotic-aur einbinden, Greeter-Toml kopieren,
# NVIDIA-Profile schreiben). Erst fuellen, wenn die jeweilige Phase dran ist.
set -Eeuo pipefail

TARGET="${1:-/mnt}"
echo "nex: post.sh (noch keine Aktionen) – Ziel: $TARGET"
