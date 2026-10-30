#!/usr/bin/env bash
# crop.sh ФАЙЛ.png [нижняя_рамка]
# Обрезать пустой низ снимка окна терминала: окно на 30 строк с выводом в
# 8 строк иначе тратит полстраницы отчёта на чёрный фон.
# Ищем последнюю непустую строку пикселей по средней яркости, затем
# приклеиваем нижнюю рамку окна (по умолчанию 8 px).
set -e
F="$1"; BOT="${2:-8}"
W=$(identify -format '%w' "$F"); H=$(identify -format '%h' "$F")
LAST=$(magick "$F" -colorspace Gray -resize "1x${H}!" txt:- \
  | awk -F'[,:() ]+' 'NR>1 {if ($3+0 > 12) last=$2} END {print last+0}')
CUT=$((LAST + 14))
[ "$CUT" -ge "$((H - BOT))" ] && { echo "$F — обрезка не нужна"; exit 0; }
magick "$F" +repage \
  \( -clone 0 -crop "${W}x${CUT}+0+0" +repage \) \
  \( -clone 0 -crop "${W}x${BOT}+0+$((H-BOT))" +repage \) \
  -delete 0 -append "$F"
identify "$F"
