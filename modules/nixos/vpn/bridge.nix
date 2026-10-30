{ config, lib, ... }:
let
  s = import ./settings.nix;
  ph = config.sops.placeholder;

  xrayConfig = {
    log.loglevel = "none"; # скрытность: xray не логирует вообще (нет access/error на диск и в journald)

    # Входов нет вообще: мост сам подключается к ru-edge и держит обратный
    # туннель. Снаружи на nl-exit открыт только SSH.
    inbounds = [ ];

    outbounds = [
      # Первый outbound — по умолчанию: трафик из туннеля выходит отсюда.
      {
        tag = "direct";
        protocol = "freedom";
        # freedom по умолчанию блокирует ВСЁ, что пришло из VLESS reverse
        # («default safety policy»: в логе `blocked target ... blackholing`),
        # — разрешать надо явно. Локальные сети NL (и метаданные хостера)
        # всё равно закрыты.
        settings.finalRules = [
          { action = "block"; ip = [ "geoip:private" ]; }
          { action = "allow"; }
        ];
      }
      { tag = "block"; protocol = "blackhole"; }
      {
        # Подключение к порталу по ДОМЕНУ, а не IP: переезд ru-edge = смена
        # A-записи, мост ничего не заметит.
        tag = "to-portal";
        protocol = "vless";
        settings = {
          address = s.domain;
          port = 443;
          id = ph.link-uuid;
          encryption = "none";
          # Запросы, пришедшие через туннель, входят в маршрутизацию моста с
          # этим inboundTag.
          reverse = {
            tag = "r-in";
            sniffing = {
              enabled = true;
              destOverride = [ "http" "tls" "quic" ];
              routeOnly = true;
            };
          };
        };
        streamSettings = {
          network = "xhttp";
          xhttpSettings = {
            path = ph.xhttp-path;
            mode = "auto";
          };
          security = "reality";
          realitySettings = {
            serverName = s.domain;
            fingerprint = "chrome";
            publicKey = ph.reality-public-key;
            shortId = ph.reality-short-id;
          };
        };
      }
    ];

    routing = {
      domainStrategy = "AsIs";
      rules = [
        # Из туннеля не пускать в локальные сети NL (в т.ч. метаданные
        # хостера) и торренты (жалобы хостеру).
        { inboundTag = [ "r-in" ]; ip = [ "geoip:private" ]; outboundTag = "block"; }
        { inboundTag = [ "r-in" ]; protocol = [ "bittorrent" ]; outboundTag = "block"; }
        { inboundTag = [ "r-in" ]; outboundTag = "direct"; }
      ];
    };
  };
in
{
  sops.secrets = lib.genAttrs [
    "link-uuid"
    "reality-public-key"
    "reality-short-id"
    "xhttp-path"
  ] (_: { restartUnits = [ "xray.service" ]; });

  sops.templates."xray.json" = {
    content = builtins.toJSON xrayConfig;
    restartUnits = [ "xray.service" ];
  };

  services.xray = {
    enable = true;
    settingsFile = config.sops.templates."xray.json".path;
  };
  # Портал может быть недоступен (переезд, перезагрузка) — xray сам
  # переподключается, но если процесс упал, поднять его снова.
  systemd.services.xray.serviceConfig = {
    Restart = lib.mkForce "always";
    RestartSec = 5;
  };
}
