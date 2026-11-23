#!/usr/bin/env bash
# Profil-Definition fuer das Installer-ISO (archiso).
# Wird von mkarchiso gelesen. Basis: releng, siehe README.md.

iso_name="arch-install"
iso_label="ARCHINST_$(date +%y%m)"
iso_publisher="arch-linux (github.com/xXMortiferusXx)"
iso_application="Arch Linux Installer"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
# Reihenfolge wie releng: BIOS zuerst, UEFI als El-Torito-Alt-Eintrag danach.
# Andersherum landet der UEFI-Eintrag nicht im Katalog (OVMF faellt auf PXE zurueck).
bootmodes=(
  'bios.syslinux'
  'uefi.systemd-boot'
)
arch="x86_64"
# Serielle Konsole fuer den Testbetrieb (QEMU -serial file:...)
kernel_params="console=ttyS0"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-noappend')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/usr/local/bin/install-arch"]="0:0:755"
)
