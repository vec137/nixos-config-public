#!/usr/bin/env bash
# winpick.sh 'часть-имени-окна' → печатает id самого БОЛЬШОГО совпавшего окна.
# Нужен потому, что xdotool search находит и окна-заглушки 10x10 (остатки
# неудачных запусков GUI), и `| tail -1` легко выбирает именно их.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/cyx.sh" "
  best=; area=0
  for w in \$(xdotool search --name '$1' 2>/dev/null); do
    g=\$(xdotool getwindowgeometry \$w 2>/dev/null | awk '/Geometry:/{print \$2}')
    ww=\${g%x*}; hh=\${g#*x}
    [ -z \"\$ww\" ] && continue
    a=\$((ww*hh))
    [ \$a -gt \$area ] && { area=\$a; best=\$w; }
  done
  echo \$best"
