# Umbriel – Arch-Tracking

Zweck: Version, Config-Stand und Upstream-Änderungen für den **Arch-Port**
(`xXMortiferusXx/arch-linux`) nachvollziehbar halten.

> Die NixOS-Version liegt separat unter `xXMortiferusXx/nix-config/umbriel.md`.
> Dort steht der **NixOS-Pin**; hier steht der **Arch-Stand**. Nicht vermischen.

## Stand 2026-11-24

| | |
|---|---|
| Arch-Paket | `umbriel-git 1:0.1.0.r1672.a909081-1` (chaotic/AUR, via paru) |
| Binary | `umbriel 0.1.0 (a909081a934a)` |
| Upstream `main` | `a909081a934a` |
| Upstream `cachix` | `a909081a934a` (identisch mit `main`) |
| Config-Validierung | `umbriel config validate` → `config: ok` |
| NixOS-Pin | `2572005a9fe5505618f783534ca0ca6d0e745090` (15.11., revCount 1581) |
| Abstand | **91 Commits** hinter Arch/Upstream |

Unser Arch-Binary ist damit **exakt der aktuelle Upstream-HEAD**; es gibt
derzeit kein neueres Umbriel.

## Config-Pfade

- Repo: `hosts/nex/home/.config/umbriel/` und `hosts/lion-pc/home/.config/umbriel/`
- Live: `~/.config/umbriel/` (`config.toml`, `cfg/*.toml`, `noctalia.toml`)
- `noctalia.toml` wird von Noctalia erzeugt (Farben/Templates).
- `/usr/local/bin/start-umbriel` ist der leise Login-Wrapper
  (`stdout/stderr` → `/dev/null`); das Paket-Skript liegt unter
  `/usr/bin/start-umbriel`.

## Verhältnis zu NixOS

Die `cfg/*.toml` sind **1:1 identisch** mit den aktuellen NixOS-Configs
(`home/mortiferus/config/umbriel`, `home/lion/config/umbriel`). Bewusste
Arch-Unterschiede:

| Datei | Arch | NixOS |
|---|---|---|
| `config.toml` | `general.autostart = ["noctalia"]` | leer; Autostart über systemd-user |
| `display.toml` (nex) | eDP-1 = amdgpu/aktiv, eDP-2 = nvidia/Rollback | Kommentare/Blöcke vertauscht (nur Doku) |
| `noctalia.toml` | von Noctalia erzeugt | nicht im NixOS-Config-Repo |
| `start-umbriel` | leiser Wrapper in `/usr/local/bin` | Home-Manager/systemd-Service |

## Neu im Upstream seit `2572005` (in `a909081` enthalten)

- **Global Shortcuts Portal**: Registry, Freigabe-Dialog, IPC, Revoke und
  Config-Overrides (`global_shortcuts`).
- **Scratchpad**: beliebiges Layout + modal, Fenster pinnen, Show/Hide auf
  einer Taste, bleibt über Workspace-Wechsel sichtbar, bleibt sichtbar während
  Fenster dahinter benutzt werden, über Fullscreen, Fokus beim Output-Wechsel,
  Position bleibt erhalten.
- Neue Action **`spawn-floating`** (App direkt floating starten).
- **`window_rule.border_effect_unfocused`** (unfokussierter Border-Effekt).
- Config-Diagnostik: jeder Fehler wird geloggt; Regeln mit unbekannten
  `match`-Keys werden verworfen; Include-/Reload-Fixes.
- Viele Layout-/Render-/Fokus-/Output-Fixes (Titlebar-Rundungen, maximierte
  Floats, Tab-Gruppen, Touch/Pad, Frame-Retries).

## Effekte: `appearance` vs. `[effects]`

Nicht verwechseln:

- **`appearance`** (aktiv): `blur`, `shadow`, `corner_radius = 12`,
  `drag_opacity`, `animation` (popin/fade/snappy). Das ist der normale
  „moderne“ Look und läuft bereits.
- **`[effects]`** (aus): separate GLSL-Engine für Border-/Window-/Screen-/
  Cursor-Effekte. `umbriel effects` zeigt aktuell **keine Presets/Pools**;
  `effects.border/window/screen/cursor` sind leer, `effects.border_unfocused`
  ist `false`.

Mitgelieferte Presets (nur nach Include + Selektor aktiv):

| Kind | Presets |
|---|---|
| Border | `pulse` (Palette + Light), `audio` (Spektrum) |
| Cursor | `glow`, `trail`, `trail-path` |
| Screen | `vignette` |
| Window | `scanlines` |
| Animation | `reveal`, `squash`, `workspace_wipe` |

**Empfehlung:** standardmäßig aus lassen. Der einzige subtile Kandidat ist
**`pulse`** als Border-Effekt **nur für das fokussierte Fenster**
(`border_effect_unfocused` bleibt `false`), optional **`glow`** für den Cursor.
`vignette` (Screen) deaktiviert Direct-Scanout und kann Spiele/Video stören;
`scanlines` ist retro; `audio` ist ein Gimmick mit Spektrum-Kosten.

Getesteter Opt-in-Snippet (nicht aktiv; in `config.toml` ergänzen):

```toml
[include]
files = [
  # ... bestehende cfg/*.toml ...
  "/usr/share/umbriel/effects/border/pulse/effect.toml",
  # "/usr/share/umbriel/effects/cursor/glow/effect.toml",
]

[effects]
border = "pulse"
# cursor = "glow"
```

Danach `umbriel config validate` (muss `config: ok` liefern) und der
Compositor lädt neu. Rollback: die beiden Include-Zeilen und `[effects]`
entfernen. `border_effect_unfocused = true` würde auch alle unfokussierten
Fenster leuchten lassen – bewusst nicht gesetzt.

## Feature-Entscheidung

**Nichts muss migriert oder konfiguriert werden.** Die aktuelle Config ist
gültig und bleibt bewusst minimal.

| Feature | Empfehlung |
|---|---|
| `global_shortcuts` | Nichts tun – Portal/Freigabe läuft automatisch; Apps können Shortcuts registrieren |
| Scratchpad Show/Hide/Pin/Stay-up | Optional; wir nutzen bereits `Mod+Tab` + `scratchpad-window-show-next/previous` |
| `spawn-floating` | Optional; z. B. für ein Floating-Terminal, aktuell nicht gebunden |
| `border_effect_unfocused` | Nur mit Border-Effect; bleibt `false` (nur fokussiertes Fenster) |
| Config-Diagnostik/unknown-match-Fix | Automatisch, keine Aktion |

Wenn Scratchpads künftig intensiver genutzt werden, sind die neuen
Show/Hide-/Pin-Actions die einzigen Kandidaten für einen Keybind. Für den
jetzigen Stand: **keine Config-Änderung nötig.**

## Check-Ablauf (für die Zukunft)

```bash
# 1) Installiertes Binary und Config
umbriel --version
umbriel config validate

# 2) Upstream-Refs
git ls-remote https://github.com/noctalia-dev/umbriel.git \
  refs/heads/main refs/heads/cachix

# 3) Commits seit dem letzten Stand
curl -fsSL "https://api.github.com/repos/noctalia-dev/umbriel/compare/<ALT>...<NEU>" \
  | jq -r '.ahead_by, (.commits[]? | .sha[0:7] + " " + (.commit.message | split("\n")[0]))'

# 4) Schema/Config prüfen
umbriel config schema --json > /tmp/umbriel-schema.json
umbriel config validate

# 5) NixOS-Configs vergleichen
#    (nix-config: home/mortiferus/config/umbriel, home/lion/config/umbriel)
```

Update: `paru -Syu` bzw. `pacman -Syu` zieht `umbriel-git`; danach
**Login-Neustart**, damit der laufende Compositor das neue Binary nutzt.
Anschließend beide Hosts validieren und diese Datei fortschreiben.

## Historie

- **2026-11-24**: Arch `a909081` = Upstream `main`/`cachix`; NixOS-Pin
  `2572005` (91 Commits zurück). `config: ok`; keine Migration. Neue Features:
  Global Shortcuts, Scratchpad-Verbesserungen, `spawn-floating`,
  `border_effect_unfocused`, Config-Diagnostik.
- **2026-11-15**: NixOS-Pin `2572005`; `follows_mouse` auf `"off"` migriert;
  Config gültig.
- **2026-11-24 (QEMU)**: Lion-Erstboot mit `a909081`; Greeter läuft,
  `umbriel config validate` = `config: ok`; grafischer Login headless nicht
  durchgeklickt.
