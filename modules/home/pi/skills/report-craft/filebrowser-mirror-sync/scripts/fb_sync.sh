#!/usr/bin/env bash
# fb_sync.sh — синхронизация с FileBrowser (Quantum) по REST со сверкой sha256.
#
# Креды берутся из .env рядом со скриптом или из переменных окружения:
#   FB_URL, FB_USER, FB_PASSWORD, FB_SOURCE
#
# Команды:
#   login
#   up   ЛОКАЛЬНЫЙ_ФАЙЛ  /УДАЛЁННЫЙ/ПУТЬ          загрузка (переопределение)
#   down /УДАЛЁННЫЙ/ПУТЬ  ЛОКАЛЬНЫЙ_ФАЙЛ          скачивание
#   del  /УДАЛЁННЫЙ/ПУТЬ                          удаление
#   ls   /УДАЛЁННЫЙ/КАТАЛОГ                       листинг (проверка после массовой загрузки)
#   ver  ЛОКАЛЬНЫЙ_ФАЙЛ  /УДАЛЁННЫЙ/ПУТЬ          сверка sha256 без загрузки
#   sync ЛОКАЛЬНЫЙ_КАТАЛОГ /УДАЛЁННЫЙ/КАТАЛОГ     зеркальное копирование дерева
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Креды: ./.env рядом со скриптом, либо файл из FB_ENV, либо известные места.
for f in "$DIR/.env" "${FB_ENV:-}" /home/nix/local-mcps/filebrowser-mcp/.env; do
  [ -n "$f" ] && [ -f "$f" ] && { . "$f"; break; }
done
: "${FB_URL:?FB_URL не задан}"; : "${FB_USER:?}"; : "${FB_PASSWORD:?}"; : "${FB_SOURCE:=files}"
TOKEN_CACHE="${FB_TOKEN_CACHE:-/tmp/fb_token.$$}"

enc() { python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$1"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

login() {
  if [ -s "$TOKEN_CACHE" ]; then
    # /api/renew на Quantum 404 — проверка живости токена дешёвым листингом корня:
    # иначе login() долбит /api/auth/login на каждый файл и упирается в лимит
    # 10 логинов/мин (массовый sync валился волнами 401).
    local ok; ok=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(cat "$TOKEN_CACHE")" "$FB_URL/api/resources?path=%2F&source=$FB_SOURCE")
    [ "$ok" = 200 ] && return 0
  fi
  # НЕ долбить /api/auth/login в цикле: лимит 10 логинов/мин на IP
  curl -s -X POST "$FB_URL/api/auth/login?username=$FB_USER" -H "X-Password: $FB_PASSWORD" > "$TOKEN_CACHE"
  [ -s "$TOKEN_CACHE" ] || { echo "login failed" >&2; return 1; }
}
T() { cat "$TOKEN_CACHE"; }

up() { # up ЛОКАЛЬНЫЙ /УДАЛЁННЫЙ
  login; local e; e=$(enc "$2")
  local code; code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    "$FB_URL/api/resources?path=$e&source=$FB_SOURCE&override=true" \
    -H "Authorization: Bearer $(T)" --data-binary @"$1")
  if [ "$code" = 401 ]; then   # токен протух посреди массового синка — перелогин и ещё раз
    rm -f "$TOKEN_CACHE"; login
    code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
      "$FB_URL/api/resources?path=$e&source=$FB_SOURCE&override=true" \
      -H "Authorization: Bearer $(T)" --data-binary @"$1")
  fi
  local rem; rem=$(curl -s "$FB_URL/api/resources/download?file=$e&source=$FB_SOURCE" -H "Authorization: Bearer $(T)" | sha256sum | cut -d' ' -f1)
  if [ "$(sha "$1")" = "$rem" ]; then echo "OK   $2"; else echo "FAIL $2 http=$code"; return 1; fi
}

down() { login; local e; e=$(enc "$1")
  curl -s "$FB_URL/api/resources/download?file=$e&source=$FB_SOURCE" -H "Authorization: Bearer $(T)" -o "$2"; }

del() { login; local e; e=$(enc "$1")
  curl -s -o /dev/null -w 'del %s %s\n' -X DELETE \
    "$FB_URL/api/resources?path=$e&source=$FB_SOURCE" -H "Authorization: Bearer $(T)"; }

ls_() { login; local e; e=$(enc "$1")
  # В Quantum листинг тоже только через query: GET /api/resources?path=…&content=1
  # (форма /api/resources/<path> отдаёт 404).
  curl -s "$FB_URL/api/resources?path=$e&source=$FB_SOURCE&content=1" -H "Authorization: Bearer $(T)" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(x.get("name"), x.get("size","")) for x in d.get("files",[])]'; }

ver() { login; local e; e=$(enc "$2")
  local rem; rem=$(curl -s "$FB_URL/api/resources/download?file=$e&source=$FB_SOURCE" -H "Authorization: Bearer $(T)" | sha256sum | cut -d' ' -f1)
  [ "$(sha "$1")" = "$rem" ] && echo "OK   $2" || { echo "РАЗЛИЧИЕ $2"; return 1; }; }

sync() { # sync ЛОКАЛЬНЫЙ_КАТАЛОГ /УДАЛЁННЫЙ/КАТАЛОГ
  local src="${1%/}" dst="$2" ok=0 fail=0 f rel
  # ВНИМАНИЕ: все подстановки $(...) в кавычках — неэкранированный dirname
  # ронял в цикл мусорное значение и 42 файла ушли в чужой каталог.
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    if up "$f" "$dst/$rel"; then ok=$((ok+1)); else fail=$((fail+1)); fi
  done < <(find "$src" -type f -print0)
  echo "загружено: $ok, сбоев: $fail"
  ls_ "$dst"
  [ "$fail" = 0 ]
}

case "${1:-}" in
  login) login && echo "login ok" ;;
  up)    up "${@:2}" ;;
  down)  down "${@:2}" ;;
  del)   del "${@:2}" ;;
  ls)    ls_ "${@:2}" ;;
  ver)   ver "${@:2}" ;;
  sync)  sync "${@:2}" ;;
  *)     sed -n '2,20p' "$0" ;;
esac
