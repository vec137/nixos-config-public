{ lib, pkgs, ... }:
let
  # Прямые запросы к cachix (nix-community/niri/niri-epireyn/noctalia)
  # идут на общий Cloudflare/Fastly-пул из нескольких IP; на части из них
  # TLS-хендшейк проходит, но передача глохнет на ~19 КБ и висит до
  # таймаута (инцидент 2026-09-24 в CLAUDE.md, воспроизведён вновь
  # 2026-10-04). Какие именно IP сейчас мёртвые -- не константа здесь, а
  # живой rule-provider: cachix-ip-check.timer реально качает .nar через
  # каждый резолвленный IP раз в 10 минут и перезаписывает
  # /var/lib/cachix-bad-ips/ips.yaml, затем дёргает mihomo за ручку
  # reload именно этого провайдера (без рестарта mihomo.service).
  #
  # DOMAIN-SUFFIX для *.cachix.org идёт в DIRECT по умолчанию; RULE-SET
  # перед ним перехватывает конкретные мёртвые IP и уводит их в "proxy"
  # (туннель) -- то есть именно "живой IP напрямую, мёртвый через
  # прокси", а не просто "мёртвый рвётся и всё". Если провайдер ещё не
  # знает ни одного мёртвого IP (пустой payload сразу после установки),
  # всё идёт DIRECT, что безопасно: туннель всё равно доступен как
  # fallback через то же правило, как только таймер найдёт мёртвый IP.
  cachixBadIpsDefault = (pkgs.formats.yaml { }).generate "cachix-bad-ips-default.yaml" {
    payload = [ ];
  };
  cachixBadIpsDir = "/var/lib/cachix-bad-ips";
  cachixBadIpsPath = "${cachixBadIpsDir}/ips.yaml";
in
{
  # Только ноутбук: общий mihomo (modules/nixos/mihomo.nix) дополняется
  # правилом и rule-provider'ом для cachix, остальное ниже — сервис проверки
  # живых/мёртвых IP, который этот provider обновляет.
  services.mihomoBalancer = {
    ruleProviders.cachix-bad-ips = {
      type = "file";
      behavior = "ipcidr";
      path = cachixBadIpsPath;
    };
    # Порядок важен: RULE-SET про мёртвые IP должен сработать раньше
    # общего DOMAIN-SUFFIX для cachix.org, иначе мёртвый IP тоже уйдёт
    # в DIRECT. Всё остальное (не cachix) -- через туннель, как и раньше.
    extraRules = [
      "RULE-SET,cachix-bad-ips,proxy"
      "DOMAIN-SUFFIX,cachix.org,DIRECT"
    ];
  };

  # mihomo с 2026 отказывается читать rule-provider типа "file" из
  # произвольного пути -- только из своего homeDir (DynamicUser → приватный
  # /var/lib/private/mihomo) или из SAFE_PATHS (список через ":", как PATH).
  # Без этого: "Parse config error: path is not subpath of home directory
  # or SAFE_PATHS" и mihomo падает при каждом старте (сам конфиг при этом
  # проходит nix flake check/toplevel-билд, потому что это ошибка времени
  # выполнения mihomo, а не ошибка Nix). Проверено по исходникам
  # (constant/path.go: filepath.SplitList на SAFE_PATHS, затем
  # filepath.Rel + IsLocal -- префиксная проверка каталога, значит сам
  # каталог без хвостового /ips.yaml достаточен).
  systemd.services.mihomo.environment.SAFE_PATHS = cachixBadIpsDir;

  # Сид для rule-provider'а: создаётся один раз при самой первой загрузке
  # ("C" копирует только если файла ещё нет), дальше живёт в /var/lib --
  # переживает рестарты mihomo.service и перезагрузки, никогда не
  # откатывается обратно к пустому списку из стора.
  systemd.tmpfiles.rules = [
    "d ${cachixBadIpsDir} 0755 root root -"
    "C ${cachixBadIpsPath} 0644 root root - ${cachixBadIpsDefault}"
  ];

  systemd.services.cachix-ip-check = {
    description = "Перепроверить, какие IP cachix сейчас мёртвые, и обновить rule-provider mihomo";
    after = [ "mihomo.service" ];
    requires = [ "mihomo.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellApplication {
        name = "cachix-ip-check";
        # glibc.getent, не glibc/glibc.bin -- getent -- отдельный output,
        # которого нет ни в основном, ни в .bin (проверено содержимым
        # ls на обоих). Интерактивно это маскировалось: скрипт экспортирует
        # PATH как "явные store-пути:$PATH", и в логин-шелле хвостовой
        # $PATH уже содержал /run/current-system/sw/bin с системным
        # getent -- под systemd там только этот узкий список, getent не
        # находится вообще, "command not found" гасится через `2>/dev/null`
        # на самом вызове и `|| true` на присваивании, и весь конвейер
        # домен→IP тихо превращается в пустоту без единой ошибки в журнале.
        runtimeInputs = [ pkgs.curl pkgs.gnugrep pkgs.gawk pkgs.coreutils pkgs.findutils pkgs.glibc.getent ];
        text = builtins.readFile ./cachix-ip-check.sh;
      }}/bin/cachix-ip-check";
    };
  };

  systemd.timers.cachix-ip-check = {
    description = "Таймер переоценки живых/мёртвых IP cachix";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "10min";
    };
  };
}
