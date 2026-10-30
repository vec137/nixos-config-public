#!/usr/bin/env bash
# shot.sh ФАЙЛ.png [часть-имени-окна]
# Снимок экрана гостя с хоста. Если указана часть имени окна — кадр обрезается
# ровно по этому окну вместе с рамкой. ВМ берётся из CYVM (см. vmenv.sh).
#
# Важно: координаты берутся из xwininfo («Absolute upper-left» — левый верхний
# угол клиентской области), а НЕ из `xdotool getwindowgeometry`: последний для
# окон, перехваченных менеджером, возвращает значения, смещённые на толщину
# рамки, и обрезка уезжает вниз-вправо. Поля рамки читаются из
# _NET_FRAME_EXTENTS, поэтому формула не зависит от темы оформления.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/vmenv.sh"
OUT="$1"; NAME="$2"
VBoxManage controlvm "$CYVM" screenshotpng "$OUT"
[ -z "$NAME" ] && { identify "$OUT"; exit 0; }
WIN_ID="$("$DIR/winpick.sh" "$NAME")"
[ -z "$WIN_ID" ] && { echo "окно '$NAME' не найдено" >&2; exit 1; }
read -r CX CY W H FL FR FT FB <<< "$("$DIR/cyx.sh" "
  win=$WIN_ID
  info=\$(xwininfo -id \$win)
  cx=\$(echo \"\$info\" | awk '/Absolute upper-left X/ {print \$4}')
  cy=\$(echo \"\$info\" | awk '/Absolute upper-left Y/ {print \$4}')
  w=\$(echo \"\$info\" | awk '/^  Width:/ {print \$2}')
  h=\$(echo \"\$info\" | awk '/^  Height:/ {print \$2}')
  ext=\$(xprop -id \$win _NET_FRAME_EXTENTS | sed 's/.*= //; s/,//g')
  echo \$cx \$cy \$w \$h \$ext")"
magick "$OUT" -crop "$((W+FL+FR))x$((H+FT+FB))+$((CX-FL))+$((CY-FT))" +repage "$OUT"
identify "$OUT"
