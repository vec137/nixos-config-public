# Общие параметры связки ru-edge (portal) ↔ nl-exit (bridge). Обычный
# attrset, не NixOS-модуль: его читают и модули VPS, и ssh-конфиг ноутбука
# (modules/home/misc.nix), чтобы порт/адреса были записаны ровно в одном месте.
#
# Секретное (UUID, ключи Reality, shortId, путь xhttp, хэш пароля) здесь НЕ
# лежит — оно в secrets/vps.yaml и secrets/ru-edge.yaml (sops), а в конфиги
# подставляется при активации через sops.templates.
{
  # Домен для self-steal: A-запись → IP ru-edge, на него же выпускается
  # сертификат LE, его же SNI у клиентов и у моста. При переезде ru-edge
  # меняется только A-запись — клиенты и nl-exit ничего не замечают.
  #
  # Это ОБЯЗАТЕЛЬНО отдельное имя от CDN-входа: self-steal держится на том,
  # что имя публично резолвится именно в IP ru-edge (проверка SNI↔IP у ТСПУ,
  # ACME HTTP-01, зонд видит настоящий сайт по этому адресу). Апекс
  # example.net при этом остаётся за CDN-провайдером (A → 203.0.113.40,
  # зона на ns01/ns02 этого провайдера) — второй вход, origin которого нужно
  # перевести на это имя. Поддомена достаточно, второй домен не нужен.
  domain = "cloud.example.com";

  # Имя второго, CDN-входа: апекс зоны, делегированной на ns01/ns02 CDN-провайдера,
  # A → узел CDN (203.0.113.40), origin CDN — `domain` выше (по имени, HTTPS 443).
  # Клиент идёт на CDN обычным TLS (сертификат LE выпускает сам CDN), дальше CDN
  # → nginx на ru-edge → секретный путь xhttp → xray (portal.nix, decoy.nix). Reality
  # здесь нет: снаружи это обычный HTTPS к сайту за CDN.
  cdnDomain = "example.net";

  # SSH на обоих VPS: только этот порт, только ключ, с rate-limit в nftables
  # (см. base.nix). 41467 — тот же, что на прежних VPS в misc.nix.
  sshPort = 41467;

  # Публичные адреса — только для ssh-конфига ноутбука и для
  # nixos-anywhere; сами системы от них не зависят (адрес берут по DHCP,
  # если в hosts/<h>/default.nix не задан статический).
  # TODO: IP ru-edge — после аренды.
  hosts = {
    ru-edge = "203.0.113.10";
    nl-exit = "203.0.113.20";
  };

  # Публичный ключ, которым домашний сервер подписывает свои сборки
  # (приватная часть — secrets/server.yaml → nix.settings.secret-key-files).
  # VPS принимают только подписанные пути, поэтому деплой-пользователю не
  # нужно быть trusted-user (а trusted-user в nix — это фактически root без
  # пароля).
  serverSigningKey = "server-builds-1:cIct2BprPMrVLFl8Ngj0qLVrzEiss1PHqCimuRhn1Rw=";

  # То же самое, но для ноутбука. Нужен отдельно от serverSigningKey: с
  # deploy-rs (flake.nix) сборка не всегда целиком уходит на server через
  # distributedBuilds — мелкие деривации (unit-script'ы, manifest-for-users.json)
  # демон иногда собирает локально, даже когда server доступен, и без этого
  # ключа VPS их отвергает ("lacks a signature by a trusted key"). Плюс
  # ноутбук не всегда имеет связь с домашней сетью — с этим ключом он может
  # собрать и задеплоить VPS-конфиг целиком сам, без server. Приватная часть —
  # secrets/laptop.yaml → nix.settings.secret-key-files (hosts/laptop/default.nix).
  laptopSigningKey = "laptop-builds-1:SNoYdQXC5vDzRikFuXYnnOlwFUVps5MO7FnYxUHcNss=";

  # Ключи, с которыми ноутбук ходит на VPS пользователем nix (приватные части —
  # ~/.nix/ssh/vps_deploy*, в git не попадают). Список, а не один ключ: ротация
  # идёт «наложение → проверка → отзыв». Один деплой атомарно подменяет ключ и в
  # /etc/ssh/authorized_keys.d/nix (NixOS 26.05 пишет туда, а не в
  # ~/.ssh/authorized_keys; см. AuthorizedKeysFile в sshd_config), и в break-glass
  # initrd (boot.initrd.network.ssh → etc/ssh/authorized_keys.d/root внутри initrd),
  # а users.mutableUsers = false — так что замена «в лоб» при опечатке в
  # публичной части = самоличный бан на обеих ВПСК, включая аварийный вход.
  # Отзыв старого ключа (VMmanager 6, 17.10.2026) — 2026-10-20.
  deployKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPzv+5kaYJ9LkmuIPN9VUXBT1detovXrcd7/dBhKgUiO nix@laptop→vps 2026-10"
  ];

  # --- Скрытность: FDE + сетевая разблокировка (максимальный вариант) --------
  # Корень VPS зашифрован LUKS (disk-config.nix). Разблокировка на загрузке:
  #   * основная — Clevis достаёт парольную фразу у Tang на домашнем сервере
  #     (боту не нужно хранить ключ: Tang сам ключа не знает, см. clevis/tang);
  #   * запасная (break-glass) — SSH в initrd, ввод той же фразы руками, когда
  #     дом недоступен (иначе ребут без дома повесил бы загрузку навсегда).
  # Парольная фраза LUKS в репозиторий НЕ кладётся: задаётся при установке
  # (nixos-anywhere --disk-encryption-keys) и ею же порождается JWE для Clevis.
  home = {
    # Белый IP (или DDNS-имя) домашнего сервера, где поднят Tang. Clevis на
    # VPS ходит сюда на этапе initrd, ДО расшифровки корня, поэтому нужна
    # прямая доступность снаружи (проброс порта/белый адрес; за CGNAT — DDNS
    # + проброс). Фаервол сервера открывает tangPort только для IP обоих VPS.
    # Проверено 2026-10-07 с ru-edge: curl http://<ip>:<tangPort>/adv → 200.
    ip = "203.0.113.30";
    tangPort = 7654;
  };

  # Прямые входы ru-edge для клиентов (не через CDN, идут на сам IP):
  #   hy2Port — Hysteria2, UDP (QUIC; рядом с Reality на TCP 443 порт тот же);
  #   ssPort  — Shadowsocks-2022, TCP+UDP.
  # Оба входа в portal.nix, трафик с них, как и с Reality, уходит в r-nl.
  hy2Port = 443;
  ssPort = 8388;

  # Порт TCP-релея Tang на ru-edge (modules/nixos/vpn/tang-relay.nix): через
  # него nl-exit достаёт ключ, потому что прямой путь NL → дом теряет потоки.
  # JWE nl-exit (secrets/clevis/cloud02.jwe) должен указывать на
  # http://<hosts.ru-edge>:<tangRelayPort>, а не на home.ip.
  tangRelayPort = 7655;

  # Clevis-авторазблокировка. Условия выполнены: Tang поднят на доме
  # (hosts/server/default.nix), home.ip ниже — реальный белый адрес, порт
  # проброшен на роутере (проверено с ru-edge: GET /adv отдаёт 200).
  #
  # Флаг общий для всех VPS, но base.nix включает clevis только тем хостам, у
  # кого есть свой secrets/clevis/<hostName>.jwe (имя — networking.hostName,
  # то есть cloud01/02, а не ru-edge/nl-exit), и ругается warning'ом на
  # остальных. Поэтому держать его true безопасно даже когда часть JWE ещё не
  # сгенерирована: сейчас есть cloud01.jwe (ru-edge) и cloud02.jwe (nl-exit) —
  # оба разблокируются сами, break-glass остаётся только если Tang/дом/релей
  # недоступны.
  enableClevis = true;

  # Имя LUKS-маппинга (disko) — оно же в boot.initrd.clevis.devices.
  luksName = "cryptroot";

  # Порт SSH в initrd для break-glass-разблокировки. Хост-ключ initrd НЕ в git
  # и НЕ в store: кладётся на VPS при установке в /etc/secrets/initrd/ и
  # до-упаковывается в initrd на активации (boot.initrd.secrets, GRUB умеет).
  initrdSshPort = 2222;
}
