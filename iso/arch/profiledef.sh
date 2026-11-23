#!/usr/bin/env bash
# Profil-Definition fuer das Installer-ISO (archiso).
# Wird von mkarchiso gelesen. Basis: releng, siehe README.md.

iso_name="arch-install"
iso_label="ARCH_INSTALL_$(date +%Y%m)"
iso_publisher="arch-linux (github.com/xXMortiferusXx)"
iso_application="Arch Linux Installer"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=(
  'uefi.systemd-boot'
  'bios.syslinux'
)
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-noappend')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/usr/local/bin/install-arch"]="0:0:755"
)
