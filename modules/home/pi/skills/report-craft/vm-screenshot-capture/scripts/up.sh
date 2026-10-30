#!/usr/bin/env bash
# Запустить ВМ headless, дождаться экрана входа, войти как analyst и
# убедиться, что SSH отвечает. Идемпотентен: если ВМ уже поднята — просто
# проверяет канал. ВМ/порт — из CYVM/CYPORT (см. vmenv.sh).
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/vmenv.sh"
if ! VBoxManage list runningvms | grep -q "\"$CYVM\""; then
  VBoxManage startvm "$CYVM" --type headless >/dev/null
  # ждём, пока отрисуется greeter (снимок перестаёт быть крошечным)
  for _ in $(seq 1 60); do
    sleep 3
    VBoxManage controlvm "$CYVM" screenshotpng /tmp/.cyboot.$$.png 2>/dev/null || continue
    [ "$(stat -c%s /tmp/.cyboot.$$.png)" -gt 8000 ] && break
  done
  rm -f /tmp/.cyboot.$$.png
  VBoxManage controlvm "$CYVM" keyboardputstring "cyberops"
  VBoxManage controlvm "$CYVM" keyboardputscancode 1c 9c
fi
for _ in $(seq 1 45); do
  if "$DIR/cy.sh" 'exit 0' 2>/dev/null; then echo "ВМ '$CYVM' готова, SSH на :$CYPORT отвечает"; exit 0; fi
  sleep 4
done
echo "ВМ '$CYVM' запущена, но SSH на :$CYPORT не отвечает" >&2; exit 1
