{ config, lib, pkgs, ... }:
let
  s = import ./settings.nix;
  secrets = config.sops.secrets;

  # Те же клиенты, что в portal.nix (UUID = client-<имя>, ключ SS = ss-<имя>).
  clients = [ "laptop" "phone" ];

  subRoot = "/run/sub";

  # Подписка — «сложный путь»: файлы лежат в /run/sub/<sub-path>/, а nginx
  # отдаёт только этот каталог (location с секретным именем). Всё прочее на
  # домене — приманка. Токен — один случайный сегмент без «/»:
  #   openssl rand -hex 24
  #
  # Генерация — скриптом, а не sops-шаблоном: ссылки требуют url-кодирования и
  # base64, а шаблон умеет только подставлять строки. Скрипт читает те же
  # секреты, что и xray, поэтому подписка не может разойтись с сервером:
  # сменил UUID/ключ в sops → рестарт sub-gen (restartUnits) → новые файлы.
  #
  # Файлы на клиента:
  #   <имя>.yaml — proxy-provider для mihomo (formats: proxies: [...]);
  #   <имя>.txt  — ссылки по одной в строке (v2rayN, Hiddify, Nekoray);
  #   <имя>.b64  — то же в base64 (v2rayNG, Streisand: классический формат).
  genScript = pkgs.writeShellScript "sub-gen" ''
    set -eu
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.jq ]}
    domain=${s.domain}
    cdn=${s.cdnDomain}
    sp=$(cat ${secrets.sub-path.path})
    pbk=$(cat ${secrets.reality-public-key.path})
    sid=$(cat ${secrets.reality-short-id.path})
    xpath=$(cat ${secrets.xhttp-path.path})
    srv=$(cat ${secrets.ss-server-key.path})
    enc() { jq -rn --arg v "$1" '$v|@uri'; }

    out=${subRoot}/$sp
    rm -rf ${subRoot}
    install -d -m 0755 ${subRoot} "$out"

    ${lib.concatMapStrings (c: ''
      uuid=$(cat ${secrets."client-${c}".path})
      usr=$(cat ${secrets."ss-${c}".path})

      jq -n \
        --arg d "$domain" --arg cdn "$cdn" --arg u "$uuid" --arg pbk "$pbk" --arg sid "$sid" \
        --arg xp "$xpath" --arg ss "$srv:$usr" \
        --argjson hy2 ${toString s.hy2Port} --argjson sp ${toString s.ssPort} '
        def reality: { tls: true, servername: $d, "client-fingerprint": "chrome",
                       "reality-opts": { "public-key": $pbk, "short-id": $sid } };
        { proxies: [
          ({ name: "edge-xhttp", type: "vless", server: $d, port: 443, uuid: $u,
             network: "xhttp", udp: true,
             "xhttp-opts": { path: $xp, mode: "auto" } } + reality),
          ({ name: "edge-vision", type: "vless", server: $d, port: 443, uuid: $u,
             network: "tcp", flow: "xtls-rprx-vision", udp: true,
             "packet-encoding": "xudp" } + reality),
          { name: "edge-cdn", type: "vless", server: $cdn, port: 443, uuid: $u,
            network: "xhttp", tls: true, servername: $cdn, udp: true,
            "client-fingerprint": "chrome", alpn: ["h2"],
            "xhttp-opts": { path: $xp, host: $cdn, mode: "auto" } },
          # Сплит: аплоад и даунлоад идут разными путями. Имя читается как
          # «куда идёт аплоад / откуда приходит даунлоад». Сервер один и тот же
          # (xhttp-вход), путь и сессия совпадают, различается только транспорт.
          { name: "edge-split-cdn-up", type: "vless", server: $cdn, port: 443, uuid: $u,
            network: "xhttp", tls: true, servername: $cdn, udp: true,
            "client-fingerprint": "chrome", alpn: ["h2"],
            "xhttp-opts": { path: $xp, host: $cdn, mode: "auto",
              "download-settings": ({ path: $xp, host: $d, server: $d, port: 443 } + reality) } },
          ({ name: "edge-split-cdn-down", type: "vless", server: $d, port: 443, uuid: $u,
             network: "xhttp", udp: true,
             "xhttp-opts": { path: $xp, mode: "auto",
               "download-settings": { path: $xp, host: $cdn, server: $cdn, port: 443,
                 tls: true, servername: $cdn, "client-fingerprint": "chrome", alpn: ["h2"],
                 # mihomo наследует Reality родителя, если reality-opts не задан, и
                 # пытается Reality-рукопожатие с CDN ("REALITY authentication
                 # failed"). Пустой public-key отключает Reality для этой части.
                 "reality-opts": { "public-key": "", "short-id": "" } } } } + reality),
          { name: "edge-hy2", type: "hysteria2", server: $d, port: $hy2,
            password: $u, sni: $d, alpn: ["h3"] },
          { name: "edge-ss", type: "ss", server: $d, port: $sp,
            cipher: "2022-blake3-aes-128-gcm", password: $ss, udp: true }
        ] }' > "$out/${c}.yaml"

      {
        echo "vless://$uuid@$domain:443?encryption=none&type=xhttp&security=reality&sni=$domain&fp=chrome&pbk=$pbk&sid=$sid&path=$(enc "$xpath")&mode=auto#edge-xhttp"
        echo "vless://$uuid@$domain:443?encryption=none&flow=xtls-rprx-vision&type=tcp&security=reality&sni=$domain&fp=chrome&pbk=$pbk&sid=$sid#edge-vision"
        echo "vless://$uuid@$cdn:443?encryption=none&type=xhttp&security=tls&sni=$cdn&fp=chrome&alpn=h2&host=$cdn&path=$(enc "$xpath")&mode=auto#edge-cdn"
        # Сплит для xray-клиентов: downloadSettings передаётся в extra=.
        dlr=$(jq -nc --arg d "$domain" --arg xp "$xpath" --arg pbk "$pbk" --arg sid "$sid" \
          '{downloadSettings:{address:$d,port:443,network:"xhttp",security:"reality",
            realitySettings:{serverName:$d,fingerprint:"chrome",publicKey:$pbk,shortId:$sid},
            xhttpSettings:{path:$xp,host:$d,mode:"auto"}}}')
        dlc=$(jq -nc --arg cdn "$cdn" --arg xp "$xpath" \
          '{downloadSettings:{address:$cdn,port:443,network:"xhttp",security:"tls",
            tlsSettings:{serverName:$cdn,fingerprint:"chrome",alpn:["h2"]},
            xhttpSettings:{path:$xp,host:$cdn,mode:"auto"}}}')
        echo "vless://$uuid@$cdn:443?encryption=none&type=xhttp&security=tls&sni=$cdn&fp=chrome&alpn=h2&host=$cdn&path=$(enc "$xpath")&mode=auto&extra=$(enc "$dlr")#edge-split-cdn-up"
        echo "vless://$uuid@$domain:443?encryption=none&type=xhttp&security=reality&sni=$domain&fp=chrome&pbk=$pbk&sid=$sid&path=$(enc "$xpath")&mode=auto&extra=$(enc "$dlc")#edge-split-cdn-down"
        echo "hysteria2://$uuid@$domain:${toString s.hy2Port}/?sni=$domain&alpn=h3#edge-hy2"
        echo "ss://2022-blake3-aes-128-gcm:$(enc "$srv:$usr")@$domain:${toString s.ssPort}#edge-ss"
      } > "$out/${c}.txt"
      base64 -w0 < "$out/${c}.txt" > "$out/${c}.b64"
    '') clients}

    chmod -R a+rX ${subRoot}
  '';
in
{
  sops.secrets = lib.genAttrs [
    "reality-public-key" # vps.yaml (defaultSopsFile)
    "reality-short-id"
    "xhttp-path"
  ] (_: { restartUnits = [ "sub-gen.service" ]; })
  // lib.genAttrs ([ "ss-server-key" ] ++ map (c: "ss-${c}") clients ++ map (c: "client-${c}") clients) (_: {
    sopsFile = ../../../secrets/ru-edge.yaml;
    restartUnits = [ "sub-gen.service" ];
  })
  # Токен пути — только на ru-edge, мосту он не нужен.
  // { sub-path = { sopsFile = ../../../secrets/ru-edge.yaml; restartUnits = [ "sub-gen.service" ]; }; };

  systemd.services.sub-gen = {
    description = "Генерация клиентских подписок";
    wantedBy = [ "multi-user.target" ];
    before = [ "nginx.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = genScript;
    };
  };

  # Отдаём только секретный каталог. Кэш запрещён — прокси не должны
  # запоминать содержимое.
  sops.templates."nginx-sub.conf" = {
    owner = config.services.nginx.user;
    restartUnits = [ "nginx.service" ];
    content = ''
      location /${config.sops.placeholder.sub-path}/ {
        root ${subRoot};
        default_type text/plain;
        add_header Cache-Control "no-store";
        autoindex off;
      }
    '';
  };

  services.nginx.virtualHosts.${s.domain}.extraConfig = ''
    include ${config.sops.templates."nginx-sub.conf".path};
  '';
}
