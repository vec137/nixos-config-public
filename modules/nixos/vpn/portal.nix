{ config, lib, ... }:
let
  s = import ./settings.nix;
  ph = config.sops.placeholder;

  # Unix-сокет xhttp-входа. Туда приходят двумя путями:
  #   клиент/мост с xhttp+Reality → :443 Reality → fallback (не VLESS-raw) → сюда;
  #   CDN (обычный TLS) → :443 → не Reality → target nginx :8443 → location → сюда.
  xhttpSock = "/run/xray/xhttp.sock";

  clients = [ "laptop" "phone" ];

  # Метод SS-2022: ключ сервера и ключи пользователей — base64 ровно 16 байт
  # (`openssl rand -base64 16`). Клиент подключается с паролем "сервер:юзер".
  ssMethod = "2022-blake3-aes-128-gcm";

  # Сертификат LE для hy2 приходит в xray через LoadCredential (xray под
  # DynamicUser, в /var/lib/acme ему не зайти).
  certDir = "/var/lib/acme/${s.domain}";
  credDir = "/run/credentials/xray.service";

  sniffing = {
    enabled = true;
    destOverride = [ "http" "tls" "quic" ];
    routeOnly = true;
  };

  xrayConfig = {
    log.loglevel = "none"; # скрытность: xray не логирует вообще (нет access/error на диск и в journald)

    inbounds = [
      {
        # Главный вход: VLESS + Reality с «кражей» собственного домена.
        # Reality target — наш же nginx с настоящим LE-сертификатом, поэтому
        # сертификат, который видит зонд, совпадает с доменом и IP.
        tag = "reality";
        listen = "0.0.0.0";
        port = 443;
        protocol = "vless";
        settings = {
          decryption = "none";
          clients = map (c: {
            id = ph."client-${c}";
            email = c;
            flow = "xtls-rprx-vision";
          }) clients;
          # Всё, что прошло Reality, но не оказалось VLESS-raw (т.е. xhttp
          # поверх Reality), уходит во вход xhttp.
          fallbacks = [{ dest = xhttpSock; xver = 0; }];
        };
        streamSettings = {
          network = "raw";
          security = "reality";
          realitySettings = {
            target = "127.0.0.1:8443";
            xver = 0;
            serverNames = [ s.domain ];
            privateKey = ph.reality-private-key;
            shortIds = [ ph.reality-short-id ];
          };
        };
        inherit sniffing;
      }
      {
        tag = "xhttp";
        listen = "${xhttpSock},0666";
        protocol = "vless";
        settings = {
          decryption = "none";
          clients = map (c: { id = ph."client-${c}"; email = "${c}-xhttp"; }) clients ++ [
            {
              # Мост nl-exit. `reverse` превращает подключения этого
              # пользователя в обратный туннель: outbound `r-nl` на этом
              # сервере отправляет трафик через них на NL. Без Vision —
              # reverse мультиплексирует соединения.
              id = ph.link-uuid;
              email = "nl-exit";
              reverse.tag = "r-nl";
            }
          ];
        };
        streamSettings = {
          network = "xhttp";
          xhttpSettings = {
            path = ph.xhttp-path;
            # auto — принимать все режимы (packet-up/stream-up/stream-one):
            # клиенты сами выбирают, что лучше проходит.
            mode = "auto";
          };
        };
        inherit sniffing;
      }
      {
        # Hysteria2 (QUIC/UDP). Пароль клиента — его UUID: отдельный секрет
        # не нужен, а 122 бита энтропии для пароля достаточно. Сертификат —
        # тот же LE, что у приманки: на UDP 443 с SNI домена зонд видит то же,
        # что и на TCP 443.
        tag = "hy2";
        listen = "0.0.0.0";
        port = s.hy2Port;
        protocol = "hysteria";
        settings = {
          version = 2;
          clients = map (c: { auth = ph."client-${c}"; email = "${c}-hy2"; }) clients;
        };
        streamSettings = {
          network = "hysteria";
          security = "tls";
          tlsSettings = {
            alpn = [ "h3" ];
            certificates = [{
              certificateFile = "${credDir}/fullchain.pem";
              keyFile = "${credDir}/key.pem";
            }];
          };
          hysteriaSettings.version = 2;
        };
        inherit sniffing;
      }
      {
        tag = "ss";
        listen = "0.0.0.0";
        port = s.ssPort;
        protocol = "shadowsocks";
        settings = {
          method = ssMethod;
          password = ph.ss-server-key;
          network = "tcp,udp";
          clients = map (c: { password = ph."ss-${c}"; email = "${c}-ss"; }) clients;
        };
        inherit sniffing;
      }
    ];

    outbounds = [
      { tag = "direct"; protocol = "freedom"; }
      { tag = "block"; protocol = "blackhole"; }
    ];

    routing = {
      # AsIs: домены НЕ резолвятся ради IP-правил. Иначе каждый зарубежный
      # домен резолвился бы российским DNS, и подменённый ответ (IP-заглушка
      # в РФ) уводил бы заблокированный сайт в direct.
      domainStrategy = "AsIs";
      rules = [
        { ip = [ "geoip:private" ]; outboundTag = "block"; }
        { protocol = [ "bittorrent" ]; outboundTag = "block"; }
        # Российское — напрямую с ru-edge (быстро, и RU-сайты не видят
        # зарубежный IP).
        {
          domain = [
            "geosite:category-ru"
            "geosite:category-gov-ru"
            "domain:ru"
            "domain:su"
            "domain:xn--p1ai" # .рф
          ];
          outboundTag = "direct";
        }
        { ip = [ "geoip:ru" ]; outboundTag = "direct"; }
        # Остальное — через обратный туннель на NL.
        { inboundTag = [ "reality" "xhttp" "hy2" "ss" ]; outboundTag = "r-nl"; }
      ];
    };
  };
in
{
  imports = [ ./decoy.nix ];

  sops.secrets = lib.genAttrs [
    "link-uuid"
    "reality-short-id"
    "xhttp-path"
  ] (_: { restartUnits = [ "xray.service" ]; }) // lib.genAttrs (
    [ "reality-private-key" "ss-server-key" ]
    ++ map (c: "client-${c}") clients
    ++ map (c: "ss-${c}") clients
  ) (_: {
    sopsFile = ../../../secrets/ru-edge.yaml;
    restartUnits = [ "xray.service" ];
  });

  sops.templates."xray.json" = {
    content = builtins.toJSON xrayConfig;
    restartUnits = [ "xray.service" ];
  };

  # Секретный путь xhttp для nginx (CDN → origin), подключается в decoy.nix.
  sops.templates."nginx-xhttp.conf" = {
    owner = config.services.nginx.user;
    restartUnits = [ "nginx.service" ];
    content = ''
      location ${ph.xhttp-path} {
        grpc_pass unix:${xhttpSock};
        grpc_socket_keepalive on;
        grpc_read_timeout 1h;
        grpc_send_timeout 1h;
        grpc_buffer_size 16k;
        client_max_body_size 0;
        client_body_timeout 1h;
        grpc_set_header Host $host;
        grpc_set_header X-Real-IP $remote_addr;
      }
    '';
  };

  # Продление сертификата перезапускает xray (hy2 читает файлы на старте).
  security.acme.certs.${s.domain}.reloadServices = [ "xray.service" ];

  networking.firewall.allowedUDPPorts = [ s.hy2Port s.ssPort ];
  networking.firewall.allowedTCPPorts = [ s.ssPort ];

  services.xray = {
    enable = true;
    settingsFile = config.sops.templates."xray.json".path;
  };
  systemd.services.xray = {
    # Каталог под unix-сокет; 0755, чтобы nginx мог до него дойти.
    serviceConfig.RuntimeDirectory = "xray";
    serviceConfig.RuntimeDirectoryMode = "0755";
    # Сертификат и ключ для hy2 (root читает, xray получает копию в
    # $CREDENTIALS_DIRECTORY). mkForce: штатный модуль задаёт строку.
    serviceConfig.LoadCredential = lib.mkForce [
      "config.json:${config.sops.templates."xray.json".path}"
      "fullchain.pem:${certDir}/fullchain.pem"
      "key.pem:${certDir}/key.pem"
    ];
    # До первого выпуска NixOS кладёт самоподписанный сертификат
    # (acme-selfsigned-*): ждём его, а настоящий подхватим по reloadServices.
    after = [ "acme-selfsigned-${s.domain}.service" ];
    wants = [ "acme-selfsigned-${s.domain}.service" ];
    # nginx проксирует в сокет xray — пусть xray поднимается первым.
    before = [ "nginx.service" ];
  };
}
