# Host-Configs fuer nex

Dieses Verzeichnis wird von `configure_base` **1:1 nach `/` kopiert**
(`cp -a config/. /mnt/`). Struktur also exakt wie im Zielsystem:

```
config/
  etc/
    sysctl.d/10-gaming.conf
    udev/rules.d/60-iosched.rules
    polkit-1/rules.d/49-networkmanager.rules
    greetd/config.toml
    vconsole.conf          (falls host-spezifisch)
  usr/
    local/bin/game-performance
    local/bin/nvidia-offload
```

Noch leer – wird in Phase 2-4 gefuellt (NVIDIA, Desktop, Tuning).
