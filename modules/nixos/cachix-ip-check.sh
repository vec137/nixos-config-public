#!/usr/bin/env bash
# Перепроверяет, какие IP из текущего DNS-ответа cachix-доменов реально
# тянут большой файл (а не только /nix-cache-info -- см. комментарий в
# proxy-balancer.nix про то, почему мелкий запрос не ловит зависание), и
# переписывает rule-provider mihomo (ipcidr-файл), а не весь конфиг --
# после этого достаточно дёрнуть reload именно этого провайдера через
# REST API, без рестарта mihomo.service.
set -euo pipefail

declare -A test_domains=(
  [niri.cachix.org]="niri-unstable"
  [niri-epireyn.cachix.org]="niri-unstable"
  [noctalia.cachix.org]="noctalia"
)

find_payload() {
  # Якорь $ на конце -- иначе "noctalia-5.2.1" цепляет и
  # "noctalia-5.2.1-fish-completions", которого на кэше может и не быть
  # (мелкие производные часто собираются локально, а не подставляются).
  find /nix/store -maxdepth 1 -regextype posix-extended \
    -regex ".*/[a-z0-9]{32}-$1-[0-9][0-9.-]*[0-9a-f]*$" \
    ! -name '*.drv' -printf '%f\n' 2>/dev/null | head -1
}

bad_ips=()

for domain in "${!test_domains[@]}"; do
  path=$(find_payload "${test_domains[$domain]}") || true
  # Пакета ещё нет в /nix/store (первая загрузка до первой подстановки из
  # этого кэша) -- тестировать нечем, пропускаем домен в этом прогоне, а не
  # считаем его IP виновными.
  [ -z "$path" ] && continue
  hash="${path%%-*}"

  ips=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.' | sort -u) || true
  for ip in $ips; do
    narinfo=$(curl --noproxy '*' --resolve "$domain:443:$ip" -sS --max-time 8 "https://$domain/$hash.narinfo" 2>/dev/null) || {
      bad_ips+=("$ip")
      continue
    }
    # || true: grep не находит "URL:" в теле 404 (путь просится на кэше,
    # где его нет -- законный случай, не ошибка), а под set -e пустой
    # результат grep в конвейере внутри var=$(...) иначе убивает весь
    # скрипт молча на этой строке.
    narurl=$(printf '%s\n' "$narinfo" | grep '^URL:' | cut -d' ' -f2) || true
    # Пути нет именно на этом кэше (не каждый домен хостит оба пакета) --
    # не можем протестировать IP этим payload'ом, не выносим вердикт.
    [ -z "$narurl" ] && continue
    if ! curl --noproxy '*' --resolve "$domain:443:$ip" -sS -o /dev/null --max-time 15 "https://$domain/$narurl" 2>/dev/null; then
      bad_ips+=("$ip")
    fi
  done
done

mapfile -t bad_ips < <(printf '%s\n' "${bad_ips[@]-}" | grep -v '^$' | sort -u)

out=/var/lib/cachix-bad-ips/ips.yaml
{
  echo "payload:"
  for ip in "${bad_ips[@]}"; do
    echo "  - '${ip}/32'"
  done
} > "$out.tmp"
mv "$out.tmp" "$out"

# Живая перезагрузка только этого rule-provider -- mihomo.service не
# перезапускается, остальные правила/группы не трогаются.
curl -sS -X PUT --max-time 5 "http://127.0.0.1:9090/providers/rules/cachix-bad-ips" >/dev/null 2>&1 || true

echo "cachix-ip-check: мёртвых IP сейчас: ${#bad_ips[@]} (${bad_ips[*]-нет})"
