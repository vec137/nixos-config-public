{ config, lib, pkgs, ... }:
let
  s = import ./settings.nix;

  # Порт приманки на loopback. Снаружи его не видно: на него ходит только
  # nginx (и только с 127.0.0.1), а сам nginx слушает :8443 тоже на loopback.
  fbPort = 8080;

  # Куда смотрит файлохранилище и где держит состояние. Каталог с файлами
  # отдельно от БД: в files/ можно складывать «обои» для приманки, не рискуя
  # зацепить database.db.
  fbState = "/var/lib/filebrowser";
  fbRoot = "${fbState}/files";
  fbCache = "/var/cache/filebrowser";

  # Имя БД намеренно НЕ database.db: именно так назывался BoltDB у прежнего
  # services.filebrowser (v2), и на уже установленных хостах этот файл лежит
  # на месте. Схемы у v2 и quantum разные — открыв чужой файл, quantum либо
  # упал бы, либо утащил бы за собой старую запись пользователя. Отдельное имя
  # даёт чистую инициализацию, а старый database.db можно просто удалить.
  fbDb = "${fbState}/quantum.db";

  # Конфиг filebrowser-quantum. ВАЖНО: парсер (goccy/go-yaml) включён с
  # DisallowUnknownField, то есть любой неизвестный ключ — не предупреждение,
  # а фатальная ошибка на старте. Имена ниже сверены с 1.5.2-stable
  # (backend/common/settings/structs.go) и проверены запуском бинаря.
  fbConfig = (pkgs.formats.yaml { }).generate "filebrowser-config.yaml" {
    server = {
      listen = "127.0.0.1";
      port = fbPort;
      baseURL = "/";
      database = fbDb;
      # В cacheDir лежат не только превью, но и SQLite-индекс (sql/index_all.db).
      # Он восстановим, поэтому CacheDirectory, а не StateDirectory.
      cacheDir = fbCache;
      # Имя для ссылок-«поделиться», чтобы они не указывали на 127.0.0.1:8080.
      externalUrl = "https://${s.domain}";
      # Скрытность: без этого сервис периодически стучится на GitHub за новой
      # версией. Исходящий запрос по расписанию от «личного файлохранилища» —
      # лишняя зацепка, и в логи провайдера, и в фингерпринт хоста.
      disableUpdateCheck = true;
      # WebDAV не нужен (клиенты ходят браузером) — минус кусок поверхности.
      disableWebDAV = true;
      logging = [
        {
          # Только проблемы, и только в stdout → journald, а journald на этих
          # хостах держится в RAM (base.nix). На диск не попадает ничего.
          levels = "warning|error";
          output = "stdout";
          noColors = true;
          # Аналог `access_log off` у nginx: apiFilter — это регексп путей,
          # исключаемых из лога запросов, ".*" закрывает их все. Иначе каждый
          # заход писал бы строку с IP и путём.
          apiFilter = ".*";
        }
      ];
      sources = [
        {
          path = fbRoot;
          name = "files";
          config = {
            # Без этого у новых пользователей источник не появляется в scope.
            defaultEnabled = true;
            defaultUserScope = "/";
          };
        }
      ];
    };

    auth = {
      adminUsername = "admin";
      methods.password = {
        enabled = true;
        # Пароль задаётся из sops (см. ниже) и короткий там не нужен.
        minLength = 12;
        # Самое важное для приманки: никакой саморегистрации. Иначе зонд
        # завёл бы себе аккаунт и увидел внутренности.
        signup = false;
      };
    };

    frontend = {
      name = "cloud";
      disableUsedPercentage = true;
    };

    # Если когда-нибудь появится второй пользователь — по умолчанию он не
    # получает ничего, кроме чтения. Admin-права есть только у admin.
    userDefaults = {
      account.permissions = {
        admin = false;
        api = false;
        modify = false;
        create = false;
        delete = false;
        share = false;
        download = true;
      };
      ui.darkMode = true;
    };
  };
in
{
  # «Приманка» для self-steal: всё, что приходит на :443 и не является
  # Reality-клиентом (сканеры, активные зонды ТСПУ, браузер, CDN), xray
  # прозрачно отдаёт сюда — на nginx с НАСТОЯЩИМ сертификатом LE для нашего
  # домена. Снаружи сервер выглядит как обычное личное файлохранилище.
  #
  # nginx слушает :8443 только на loopback (снаружи его не видно) и :80
  # публично — для ACME HTTP-01 и редиректа на https.
  #
  # Путь xhttp (для CDN) секретный и в store не попадает: location
  # подключается из sops-шаблона, см. portal.nix.

  # --- filebrowser-quantum ---------------------------------------------------
  # Модуля services.filebrowser-quantum в nixpkgs нет (только пакет), поэтому
  # юнит свой. Форк выбран ради того, что креды задаются конфигом: у
  # services.filebrowser пароль admin генерировался случайно при первой
  # инициализации БД, его приходилось вылавливать из журнала и сбрасывать
  # руками с остановкой сервиса (BoltDB держит монопольную блокировку).
  #
  # Здесь пароль приходит из sops в FILEBROWSER_ADMIN_PASSWORD, и
  # validateUserInfo() применяет его к пользователю admin на КАЖДОМ старте
  # (backend/cmd/user.go) — не только при создании БД. То есть ротация пароля
  # это правка secrets/vps.yaml + рестарт, руками в контейнер лезть не нужно.
  sops.secrets."decoy-admin-password" = {
    restartUnits = [ "filebrowser.service" ];
  };

  # EnvironmentFile, а не Environment=: иначе пароль был бы видён в
  # `systemctl show filebrowser` и в /nix/store (юнит-файл — публичный).
  sops.templates."filebrowser.env" = {
    content = "FILEBROWSER_ADMIN_PASSWORD=${config.sops.placeholder.decoy-admin-password}\n";
    restartUnits = [ "filebrowser.service" ];
  };

  users.users.filebrowser = {
    isSystemUser = true;
    group = "filebrowser";
  };
  users.groups.filebrowser = { };

  systemd.tmpfiles.settings.filebrowser."${fbRoot}".d = {
    user = "filebrowser";
    group = "filebrowser";
    mode = "0700";
  };

  systemd.services.filebrowser = {
    description = "FileBrowser Quantum";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    # nginx проксирует сюда — пусть приманка поднимается первой, чтобы первый
    # же зонд не получил 502 вместо страницы входа.
    before = [ "nginx.service" ];

    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.filebrowser-quantum} -c ${fbConfig}";
      EnvironmentFile = config.sops.templates."filebrowser.env".path;
      # Бинарь пишет предупреждение, если не находит БД по пути из
      # FILEBROWSER_DATABASE ещё до чтения конфига. Путь тот же, что в
      # конфиге, — просто чтобы не было ложной тревоги в журнале.
      Environment = [ "FILEBROWSER_DATABASE=${fbDb}" ];

      User = "filebrowser";
      Group = "filebrowser";
      StateDirectory = "filebrowser";
      CacheDirectory = "filebrowser";
      WorkingDirectory = fbState;
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;

      # Приманка смотрит в интернет (через nginx), поэтому песочница плотная.
      NoNewPrivileges = true;
      CapabilityBoundingSet = [ "" ];
      AmbientCapabilities = [ "" ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectProc = "invisible";
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      DevicePolicy = "closed";
      SystemCallFilter = [ "@system-service" ];
      SystemCallArchitectures = "native";
    };
  };

  security.acme = {
    acceptTerms = true;
    # Почта необязательна: LE больше не рассылает напоминания об истечении,
    # а продление автоматическое (systemd-таймер).
  };

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedProxySettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    serverTokens = false;

    virtualHosts.${s.domain} = {
      default = true;
      enableACME = true;
      forceSSL = true;
      http2 = true;
      listen = [
        { addr = "127.0.0.1"; port = 8443; ssl = true; }
        { addr = "0.0.0.0"; port = 80; }
        { addr = "[::]"; port = 80; }
      ];
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString fbPort}";
        proxyWebsockets = true;
        extraConfig = ''
          client_max_body_size 0;
        '';
      };
      extraConfig = ''
        # Скрытность: ни access-, ни error-лог на диск. access полностью
        # выключен, ошибки — в stderr (→ journald, а он volatile), только
        # критические. На диске (даже зашифрованном) следов запросов нет.
        access_log off;
        error_log stderr crit;
        include ${config.sops.templates."nginx-xhttp.conf".path};
      '';
    };
  };

  # forceSSL перенаправляет на https://домен/ — то есть на :443, где
  # слушает xray, который отдаст соединение обратно в nginx. Всё сходится.
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
