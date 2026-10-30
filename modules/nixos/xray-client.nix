{ config, lib, pkgs, ... }:
let
  cfg = config.services.xrayClient;
in
{
  # Клиент xray как шаблонный системный юнит xray@<вариант> — один на
  # ноутбук и сервер. Штатный services.xray одноэкземплярный и под пять
  # вариантов не подходит, поэтому юнит свой.
  #
  # Пять вариантов транспорта лежат в репозитории зашифрованными целиком
  # (binary-режим sops, см. secrets/xray/ и раздел про секреты в CLAUDE.md,
  # получатели — admin, laptop и server, .sops.yaml). Каждый разворачивается
  # в свой /run/secrets/xray-<имя> и подхватывается одноимённым экземпляром.
  #
  # Переключиться на другой вариант (первый перестал работать):
  #   doas systemctl stop 'xray@*'
  #   doas systemctl start xray@xtls_reality
  # Остановка обязательна: все варианты слушают один и тот же 3080/4080, и
  # второй экземпляр просто упадёт с занятым портом. Держится до перезагрузки;
  # чтобы закрепить — поменять `default` у хоста и пересобрать.
  #
  # ВАЖНО, чего этот юнит НЕ умеет: заметить, что туннель перестал работать.
  # При блокировке транспорта xray не падает — процесс остаётся active
  # (running), просто соединения не устанавливаются. Restart=on-failure ловит
  # только настоящее падение процесса. Переключение между апстримами на такой
  # случай делает mihomo (modules/nixos/mihomo.nix), а не этот юнит.
  options.services.xrayClient = {
    enable = lib.mkEnableOption "клиент xray (шаблонный юнит xray@<вариант>)";

    variants = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "xhttp_reality"
        "xtls_reality"
        "xhttp_cdn"
        "cdn_up_reality_down"
        "cdn_down_reality_up"
      ];
      description = ''
        Имена клиентских конфигов xray — они же имена файлов в
        secrets/xray/<имя>.bin и имена экземпляров xray@. Новый вариант —
        это строка здесь и файл в secrets/xray/.
      '';
    };

    default = lib.mkOption {
      type = lib.types.str;
      description = ''
        Какой вариант поднимается при загрузке. Переключение на лету — см.
        комментарий в начале модуля.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = builtins.elem cfg.default cfg.variants;
      message = "services.xrayClient.default (${cfg.default}) нет в variants";
    }];

    # listToAttrs строит из списка имён атрибутсет вида
    #   { "xray-xhttp_reality" = { ... }; "xray-xtls_reality" = { ... }; ... }
    # — то же самое, что выписать пять блоков руками, только без копипасты.
    sops.secrets = builtins.listToAttrs (map (name: {
      name = "xray-${name}";
      value = {
        # binary, а не yaml/json: файл зашифрован одним блоком целиком, в нём
        # нет полей, которые sops мог бы разбирать по отдельности.
        format = "binary";
        # Путь нельзя записать как ../../secrets/xray/${name}.json:
        # подстановка внутрь литерала пути в Nix не работает. Сложение пути со
        # строкой даёт ровно тот же путь и делается именно для этого.
        sopsFile = ../../secrets/xray + "/${name}.bin";
        # Перевыпустил ключи REALITY, перешифровал файл — и nixos-rebuild сам
        # перезапустит нужный экземпляр, а не оставит его работать со старым
        # конфигом до следующей перезагрузки.
        restartUnits = [ "xray@${name}.service" ];
      };
    }) cfg.variants);

    # Шаблонный юнит: то, что стоит после @ в имени экземпляра, подставляется
    # вместо %i.
    systemd.services."xray@" = {
      description = "xray (конфиг %i)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # Команда через script, а не ExecStart: $CREDENTIALS_DIRECTORY systemd
      # заводит для дочернего процесса, и в подстановке внутри самой строки
      # ExecStart= его ещё нет — неизвестная переменная молча раскрывается в
      # пустую строку, и демон стартует с -config /config.json. На этом
      # спотыкался штатный модуль xray в nixpkgs, пока его не исправили тем же
      # способом. NixOS оборачивает script в обычный шелл-скрипт, где
      # переменная уже настоящая.
      script = ''
        exec ${pkgs.xray}/bin/xray run -c "$CREDENTIALS_DIRECTORY/config.json"
      '';
      serviceConfig = {
        DynamicUser = true;
        # LoadCredential читает файл силами systemd, то есть от root, ещё до
        # сброса привилегий, и кладёт копию в $CREDENTIALS_DIRECTORY с правами
        # 0400 на динамического пользователя. Поэтому сам секрет может
        # остаться root-only (как sops и разворачивает его по умолчанию) —
        # раздавать на него права никому не нужно.
        LoadCredential = "config.json:/run/secrets/xray-%i";
        NoNewPrivileges = true;
        # Штатный модуль выдаёт CAP_NET_ADMIN и CAP_NET_BIND_SERVICE — они
        # нужны прозрачному прокси и привязке к портам ниже 1024. Здесь чистый
        # клиент на localhost:3080/4080, так что не нужна ни одна.
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    # Какой экземпляр поднимать при загрузке.
    #
    # Форма ровно такая, как в hardware/infiniband.nix из самого nixpkgs, где
    # тем же способом включают экземпляры шаблона opensm@ — то есть это не
    # самодеятельность, а штатный приём.
    #
    # overrideStrategy = "asDropin" обязателен: без него NixOS сгенерировал бы
    # полноценный файл xray@<имя>.service, а конкретный юнит в systemd имеет
    # приоритет над шаблоном — вместо «дополнить» вышла бы молчаливая подмена,
    # и экземпляр по умолчанию поехал бы по пустому юниту вместо настоящего.
    systemd.services."xray@${cfg.default}" = {
      enable = true;
      wantedBy = [ "multi-user.target" ];
      overrideStrategy = "asDropin";
    };
  };
}
