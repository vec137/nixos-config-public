{ config, lib, pkgs, ... }:
let
  cfg = config.services.mihomoBalancer;

  # Общий балансировщик mihomo для ноутбука и сервера: один порт, за которым
  # mihomo сам выбирает живой туннель. Различия хостов выражены опциями ниже,
  # сам конфиг один:
  #   xray        → socks 127.0.0.1:3080 (xray@: hosts/{laptop,server}/xray.nix
  #                 и hosts/server/default.nix) — есть всегда;
  #   extraProxies → статические апстримы хоста (ноутбук: Throne на 2080);
  #   subscriptions → proxy-provider'ы: имя → ключ в sops с URL подписки.
  # Слушает mixed (http+socks5) 127.0.0.1:<port>. 3080 — только апстрим
  # mihomo, напрямую на него никто больше ходить не должен.
  #
  # Группа "proxy" — select: в metacubexd (http://127.0.0.1:9090/ui, на
  # сервере — через `ssh -L 9091:127.0.0.1:9090 server`, панель сама берёт
  # адрес бэкенда из своих настроек, проверь её) руками выбираешь "auto" либо
  # конкретный узел, даже с большим пингом. Править выбор можно только в
  # select-группе: в url-test mihomo не даёт закрепить узел. Закреплённый узел
  # автопереключения не имеет — если он умрёт, вернуть "auto" надо вручную.
  testUrl = "https://www.gstatic.com/generate_204";
  # Порядок подписок в группах (use): сначала перечисленные в subscriptionOrder,
  # потом остальные по алфавиту (attrNames сортирует, порядок записи в Nix не
  # хранится). Имена из subscriptionOrder, которых нет в subscriptions,
  # пропускаются, чтобы опечатка не роняла сборку.
  allSubNames = builtins.attrNames cfg.subscriptions;
  subNames =
    lib.filter (n: builtins.elem n allSubNames) cfg.subscriptionOrder
    ++ lib.filter (n: !builtins.elem n cfg.subscriptionOrder) allSubNames;
  extraNames = map (p: p.name) cfg.extraProxies;
  upstreams = lib.optional cfg.xrayUpstream "xray" ++ extraNames;
  withSubs = group: group // lib.optionalAttrs (subNames != [ ]) { use = subNames; };

  settings = {
    mixed-port = cfg.port;
    bind-address = "127.0.0.1";
    allow-lan = false;
    mode = "rule";
    log-level = "warning";
    ipv6 = false;
    # REST API + веб-панель (services.mihomo.webui ниже).
    external-controller = "127.0.0.1:9090";

    # Помнить ручной выбор в select-группе между рестартами mihomo
    # (кэш в его StateDirectory, /var/lib/private/mihomo).
    profile.store-selected = true;

    proxies = lib.optional cfg.xrayUpstream
      { name = "xray"; type = "socks5"; server = "127.0.0.1"; port = cfg.xrayPort; udp = true; }
    ++ cfg.extraProxies ++ cfg.localProxies;

    proxy-providers = lib.mapAttrs (name: key: {
      type = "http";
      # Подставляется sops при активации (sops.templates ниже).
      url = config.sops.placeholder.${key};
      # Кэш в StateDirectory: если подписка недоступна, mihomo стартует с
      # прошлой копией.
      path = "./${name}.yaml";
      interval = 3600;
      # Качать через группу "dl": напрямую, а если не вышло — через активный
      # прокси (см. группу ниже). Раньше было жёстко через xray, и мёртвый
      # xray оставлял подписки пустыми: самые нужные тогда, когда он не
      # работает. Уже скачанный кэш работает и без сети.
      proxy = "dl";
      health-check = {
        enable = true;
        url = testUrl;
        interval = 60;
      };
    }) cfg.subscriptions;

    proxy-groups = [
      {
        # Только для скачивания подписок (proxy-providers.*.proxy): fallback
        # берёт первый живой — DIRECT, а если проверка не проходит, то
        # группу "proxy" (то, что выбрано/автовыбрано сейчас).
        name = "dl";
        type = "fallback";
        proxies = [ "DIRECT" "proxy" ];
        url = testUrl;
        interval = 30;
        timeout = 5000;
      }
      (withSubs {
        name = "proxy";
        type = "select";
        proxies = [ "auto" ] ++ upstreams;
      })
      (withSubs {
        name = "auto";
        type = "url-test";
        proxies = upstreams;
        url = testUrl;
        interval = 30;
        timeout = 5000;
        # Не переключаться, пока другой апстрим быстрее меньше чем на
        # 150 мс — иначе трафик прыгал бы туда-сюда на каждом замере.
        tolerance = 150;
        # Проверять и тогда, когда через группу ничего не идёт: иначе
        # первый запрос после простоя может уйти в уже мёртвый туннель.
        lazy = false;
      })
    ] ++ cfg.extraGroups;

    # Вход для VM libvirt: mixed-порт только на адресе моста virbr0 (виден
    # лишь с хоста и из VM, не из внешних сетей). Правила те же, что у основного.
    listeners = lib.optional cfg.libvirtSocks.enable {
      name = "libvirt";
      type = "mixed";
      listen = cfg.libvirtSocks.address;
      port = cfg.libvirtSocks.port;
      udp = true;
    };

    rule-providers = cfg.ruleProviders;
    # Порядок важен: extraRules срабатывают раньше общего MATCH.
    rules = cfg.extraRules ++ [ "MATCH,proxy" ];
  } // lib.optionalAttrs (cfg.dns != { }) { dns = cfg.dns; };
in
{
  options.services.mihomoBalancer = {
    enable = lib.mkEnableOption "общий балансировщик mihomo (xray + подписки)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6080;
      description = ''
        mixed-порт (http+socks5) на 127.0.0.1. Не 4080: он прописан http-входом
        в клиентских конфигах xray, и xray целиком не стартует, если хоть один
        вход не смог занять порт. Не 5080: его держит ocproxy для VMware.
      '';
    };

    libvirtSocks = {
      enable = lib.mkEnableOption "mixed-вход (socks5+http) для VM libvirt на мосту virbr0";
      address = lib.mkOption {
        type = lib.types.str;
        default = "192.168.122.1";
        description = "Адрес моста libvirt (default-сеть 192.168.122.0/24). Только он, не 0.0.0.0.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 7891;
        description = "Порт входа для VM. Файрвол настраивается отдельно.";
      };
    };

    xrayUpstream = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Держать апстрим "xray" (socks на xrayPort). Хосту без xray@ (ноутбук
        после перехода на подписку ru-edge) ставится false, иначе в auto
        остаётся мёртвый узел.
      '';
    };

    xrayPort = lib.mkOption {
      type = lib.types.port;
      default = 3080;
      description = "socks-вход локального xray@ — апстрим \"xray\".";
    };

    subscriptions = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { sub = "mihomo-subscription-url"; };
      description = ''
        Подписки: имя proxy-provider → ключ в sopsFile с URL. Пустой набор —
        mihomo работает только с xray и extraProxies. Общий набор для всех
        хостов — modules/nixos/mihomo-subscriptions.nix (там же порядок
        добавления подписки).
      '';
    };

    subscriptionOrder = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "ruedge" ];
      description = ''
        Имена подписок, которые идут первыми в группах proxy и auto (порядок
        узлов в select-группе и в панели). Остальные следуют за ними по
        алфавиту. Порядок строк в subscriptions ничего не значит: атрибуты Nix
        не хранят порядок записи. На выбор url-test (auto) порядок не влияет:
        он берёт узел с наименьшей задержкой.
      '';
    };

    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Файл sops с ключами подписок. Задаётся явно, а не берётся из
        defaultSopsFile: значение одно на все хосты в
        modules/nixos/mihomo-subscriptions.nix (secrets/common.yaml).
      '';
    };

    extraProxies = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = ''
        Статические апстримы mihomo помимо xray (формат proxies: mihomo).
        Внимание: всё отсюда попадает в upstreams, т.е. становится
        кандидатом в группах "proxy" и "auto" — интернет-выходом, который
        url-test пингует каждые 30 с и может выбрать для всего трафика.
        Для туннелей, которые выходом в интернет не являются (домашний WG),
        есть localProxies ниже.
      '';
    };

    localProxies = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = ''
        Прокси, которые только объявляются в proxies, но НЕ входят в
        "proxy"/"auto" — для туннелей, которые нужны как доступ куда-то
        конкретно, а не как выход в интернет. Используются из extraGroups
        (ноутбук: "wg-home"/"wg-home-proxy" в группах "lan"/"home").

        Зачем отдельно: пока домашний WG лежал в extraProxies, url-test
        "auto" пинговал его каждые 30 с запросом к gstatic — то есть тянул
        интернет-трафик через домашний роутер — и мог выбрать его как самый
        быстрый узел для всего трафика (замерено 255–406 мс, вполне
        конкурентно с ru-edge). Дома это вдобавок WG на публичный адрес
        собственного роутера (NAT hairpin), который часто отваливается.
        Сюда же упирался риск петли: dialer-proxy у "wg-home-proxy"
        указывает на группу, в которой иначе лежал бы сам WG.
      '';
    };

    dns = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = {
        enable = true;
        nameserver = [ "system" ];
      };
      description = ''
        Секция dns конфига mihomo. Пустой набор (по умолчанию) — секции в
        конфиге нет вообще, т.е. mihomo своего резолвера не поднимает и для
        DIRECT-соединений спрашивает системный (/etc/resolv.conf). Как только
        секция появляется, внутренний резолвер mihomo становится
        единственным для всех его соединений, поэтому в nameserver нужен
        осмысленный список (например [ "system" ] — тот же системный
        резолвер, но уже через mihomo). Задано только на ноутбуке
        (hosts/laptop/default.nix) ради политики для *.lan.
      '';
    };

    ruleProviders = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Дополнительные rule-providers (ноутбук: cachix-bad-ips).";
    };

    extraRules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Правила перед финальным MATCH,proxy.";
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = ''
        Дополнительные proxy-groups (формат как у mihomo: name/type/proxies/…),
        дописываются в конец общего списка. Например, fallback "DIRECT, а если
        недоступно — туннель" для определения, в домашней сети клиент или нет.
      '';
    };

    nixDaemonProxy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Прокси для nix-daemon общий с серверами и задан в common.nix (4080 —
        http-вход xray@). Перенаправляем на mihomo; mkForce нужен, т.к. опция
        задана с тем же приоритетом.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # В конфиге может быть секретный URL подписки, поэтому файл — sops-шаблон
    # (root:0400). Модуль mihomo отдаёт его сервису через LoadCredential,
    # DynamicUser читать /run/secrets не должен. JSON — валидный YAML.
    sops.secrets = lib.mapAttrs' (_: key:
      lib.nameValuePair key { sopsFile = cfg.sopsFile; }
    ) cfg.subscriptions;
    sops.templates."mihomo.yaml" = {
      content = builtins.toJSON settings;
      restartUnits = [ "mihomo.service" ];
    };

    # Системный сервис (DynamicUser, без root-прав и без TUN): стартует при
    # загрузке; пока апстримы не подняты, проверки просто проваливаются, а
    # через ≤30 с после старта туннеля он подхватывается.
    services.mihomo = {
      enable = true;
      configFile = config.sops.templates."mihomo.yaml".path;
      webui = pkgs.metacubexd;
    };

    # Адрес virbr0 появляется только после старта libvirtd и его default-сети,
    # а без него listener не займёт порт: ждём libvirtd и адрес на мосту
    # (до 30 с; не дождались — стартуем без этого входа, а не падаем).
    systemd.services.mihomo = lib.mkIf cfg.libvirtSocks.enable {
      after = [ "libvirtd.service" ];
      wants = [ "libvirtd.service" ];
      serviceConfig.ExecStartPre = "-${pkgs.writeShellScript "wait-virbr" ''
        for _ in $(seq 30); do
          ${pkgs.iproute2}/bin/ip -4 -o addr show | grep -qF "inet ${cfg.libvirtSocks.address}/" && exit 0
          sleep 1
        done
        exit 0
      ''}";
    };

    systemd.services.nix-daemon = lib.mkIf cfg.nixDaemonProxy {
      environment = {
        https_proxy = lib.mkForce "http://127.0.0.1:${toString cfg.port}";
        http_proxy = lib.mkForce "http://127.0.0.1:${toString cfg.port}";
      };
      wants = [ "mihomo.service" ];
      after = [ "mihomo.service" ];
    };
  };
}
