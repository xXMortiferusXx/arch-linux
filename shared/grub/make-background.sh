#!/usr/bin/env bash
# Erzeugt das GRUB-Hintergrundbild (1920x1080) im Stil "Unholy Angels":
# dunkel, ruhig, abstrakter Heiligenschein rechts, kleiner Schriftzug unten rechts.
set -euo pipefail

OUT=${1:-/home/mortiferus/Development/arch-linux/hosts/nex/boot/grub/background.png}
W=1920
H=1080
ACCENT="#8ea3bd"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1) Basis: dunkler Diagonalverlauf (links oben fast schwarz, rechts unten etwas heller)
magick -size ${W}x${H} xc: -sparse-color bilinear "0,0 #08090c ${W},${H} #1b2029" "$tmp/base.png"

# 2) Weiches Licht hinter dem Motiv (oben rechts)
magick -size 1400x1400 radial-gradient:'rgba(36,48,64,0.50)-rgba(36,48,64,0)' \
  -background none -gravity northeast -extent ${W}x${H} "$tmp/glow.png"

# 3) Heiligenschein: zwei feine, konzentrische Ringe (Bruch durch Bildrand)
magick -size ${W}x${H} xc:none -fill none -stroke "$ACCENT" \
  -strokewidth 2 -draw "circle 1520,430 1520,50" \
  -alpha set -channel A -evaluate multiply 0.16 +channel "$tmp/ring1.png"

magick -size ${W}x${H} xc:none -fill none -stroke "$ACCENT" \
  -strokewidth 1 -draw "circle 1520,430 1520,150" \
  -alpha set -channel A -evaluate multiply 0.10 +channel "$tmp/ring2.png"

# 4) Akzentlinie (unten links, trennt Menuebereich optisch ab)
magick -size ${W}x${H} xc:none -fill "$ACCENT" \
  -draw "rectangle 150,846 470,847" \
  -alpha set -channel A -evaluate multiply 0.50 +channel "$tmp/line.png"

# 5) Schriftzug, klein und zurueckhaltend
magick -size ${W}x${H} xc:none -font DejaVu-Sans-ExtraLight -pointsize 26 \
  -kerning 13 -fill 'rgba(168,180,196,0.42)' -gravity southeast \
  -annotate +150+92 'UNHOLY ANGELS' "$tmp/word.png"

# 6) Vignette (Ecken abdunkeln, Mitte frei)
magick -size ${W}x${H} radial-gradient:'#00000000-#000000' \
  -alpha set -channel A -evaluate multiply 0.55 +channel "$tmp/vign.png"

magick "$tmp/base.png" \
  "$tmp/glow.png"  -compose over -composite \
  "$tmp/ring1.png" -compose over -composite \
  "$tmp/ring2.png" -compose over -composite \
  "$tmp/line.png"  -compose over -composite \
  "$tmp/word.png"  -compose over -composite \
  "$tmp/vign.png"  -compose over -composite \
  -depth 8 -strip -define png:compression-level=9 "$OUT"

echo "geschrieben: $OUT ($(du -h "$OUT" | cut -f1))"
