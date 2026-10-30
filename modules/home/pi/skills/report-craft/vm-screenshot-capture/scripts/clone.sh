#!/usr/bin/env bash
# clone.sh ИМЯ ПОРТ [ОЗУ_МБ] [ЯДЕР]
# Сделать связанный клон "CyberOps Workstation" со снимка clean-baseline,
# перенастроив проброс SSH на указанный хостовый порт. Идемпотентен: если ВМ
# с таким именем уже есть — ничего не делает.
set -e
NAME="$1"; PORT="$2"; MEM="${3:-4096}"; CPUS="${4:-4}"
BASE="CyberOps Workstation"
[ -z "$NAME" ] || [ -z "$PORT" ] && { echo "usage: clone.sh ИМЯ ПОРТ [ОЗУ] [ЯДЕР]" >&2; exit 1; }
if VBoxManage list vms | grep -q "\"$NAME\""; then
  echo "ВМ '$NAME' уже существует — пропуск"; exit 0
fi
VBoxManage clonevm "$BASE" --snapshot clean-baseline --options link \
  --name "$NAME" --register >/dev/null
VBoxManage modifyvm "$NAME" --memory "$MEM" --cpus "$CPUS"
# у клона наследуется правило исходной ВМ на 2222 — заменяем на свой порт
VBoxManage modifyvm "$NAME" --natpf1 delete ssh 2>/dev/null || true
VBoxManage modifyvm "$NAME" --natpf1 "ssh,tcp,127.0.0.1,$PORT,,22"
echo "клон '$NAME' готов: ОЗУ ${MEM}МБ, ядер $CPUS, SSH 127.0.0.1:$PORT"
