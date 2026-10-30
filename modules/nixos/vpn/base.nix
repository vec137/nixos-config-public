{ config, lib, pkgs, modulesPath, ... }:
let
  s = import ./settings.nix;

  # JWE этого хоста. Имя файла — networking.hostName (у ru-edge он cloud01,
  # а не ru-edge: см. hosts/ru-edge/default.nix).
  jweSrc = ../../../secrets/clevis + "/${config.networking.hostName}.jwe";

  # Флаг enableClevis общий для всех VPS, а JWE у каждого свой. Поэтому
  # проверяем ещё и наличие файла: без этого включение флага ломало бы eval
  # любого хоста, которому JWE пока не сгенерировали. Флейк видит только
  # git-tracked файлы, так что `git add secrets/clevis/<host>.jwe` —
  # обязательная часть процедуры.
  hasJwe = builtins.pathExists jweSrc;
  clevisReady = s.enableClevis && hasJwe;

  # Отдельный store-path, в котором лежит ТОЛЬКО этот JWE. Это не косметика, а
  # лечение ловушки, на которой деплой падал с
  #   cp: cannot stat '/nix/store/...-source/secrets/clevis/cloud01.jwe'
  #
  # Модуль clevis складывает JWE в boot.initrd.secrets, а генератор
  # append-initrd-secrets (nixpkgs, system/boot/stage-1.nix) подставляет путь
  # через `toString source`. String context в Nix умеет называть только ЦЕЛЫЙ
  # store-path, а не файл внутри него, поэтому `toString` от пути вида
  # <flake-source>/secrets/clevis/cloud01.jwe контекста не даёт: Nix не видит
  # зависимости, JWE не попадает в замыкание системы, nixos-rebuild
  # --target-host его не копирует — и на VPS скрипт на активации делает cp с
  # пути, который существует только на ноутбуке, где шла оценка. Ровно поэтому
  # initrd-ssh-ключ работал без всего этого: он задан абсолютным
  # /etc/secrets/initrd/... вне store, и на VPS реально лежит.
  #
  # builtins.path делает из одного файла САМОСТОЯТЕЛЬНЫЙ store-path — такой
  # `toString` контекст сохраняет, и append-initrd-secrets получает на него
  # честную ссылку (проверяется `nix-store -q --references`). Отдавать модулю
  # путь внутрь flake source нельзя и по второй причине: зависимостью стал бы
  # весь исходник флейка, и на VPS уехала бы копия всего репозитория — лишний
  # вес и прямо против скрытности.
  #
  # ВАЖНО: jweFile трогать можно только под clevisReady — builtins.path падает
  # на несуществующем файле. Для проверок и текста warning'а брать jweSrc.
  jweFile = builtins.path {
    path = jweSrc;
    name = "${config.networking.hostName}.jwe";
  };
in
{
  # Общее для всех VPS. Сознательно НЕ импортирует modules/nixos/common.nix:
  # там кэши десктопных оверлеев, прокси для nix-daemon на 127.0.0.1:4080
  # (на VPS его нет — nix просто перестал бы качать), doas и прочее, что на
  # 1 ГБ RAM только мешает.
  imports = [
    # virtio-драйверы в initrd — все VPS тут KVM.
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/minimal.nix")
    ./disk-config.nix
  ];

  # --- Загрузка ------------------------------------------------------------
  # GRUB сразу в оба режима: у хостеров бывает и SeaBIOS, и OVMF, и заранее
  # это не всегда видно. disko сам подставит boot.loader.grub.devices по
  # разделу EF02 (см. disk-config.nix).
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true; # не трогать NVRAM, которого может не быть
    configurationLimit = 5; # /boot на 512 МБ
  };
  # /tmp в RAM (tmpfs), а не на диске: ничего временного не оседает на
  # зашифрованном корне в открытом виде между перезагрузками. На 1 ГБ RAM
  # tmpfs ограничен половиной памяти — для наших сервисов с запасом.
  boot.tmp.useTmpfs = true;

  # Своп в сжатой памяти вместо раздела: на 1 ГБ RAM активация новой
  # генерации и xray+nginx вместе без него упираются в OOM.
  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  # --- Разблокировка зашифрованного корня на загрузке ----------------------
  # Корень — LUKS (disk-config.nix). Чтобы headless-VPS поднимался без
  # клавиатуры, фразу надо подать в initrd. Два пути, оба через systemd-initrd
  # (он нужен и для сети, и для clevis-юнита):
  #   * Clevis + Tang (основной, см. enableClevis) — фраза приходит с дома;
  #   * SSH в initrd (break-glass) — ввод руками, когда дом недоступен.
  boot.initrd.systemd.enable = true;

  # Сеть в initrd: DHCP на любом ethernet (virtio_net уже в qemu-guest
  # profile). Нужна и для Clevis (дойти до Tang), и для break-glass SSH.
  boot.initrd.network.enable = true;
  boot.initrd.systemd.network = {
    enable = true;
    networks."10-wan" = {
      matchConfig.Type = "ether";
      networkConfig.DHCP = "yes";
    };
  };

  # Break-glass: SSH прямо в initrd. Зайти, когда авто-разблокировка не
  # сработала (дом/Tang недоступны), и ввести фразу LUKS руками:
  #   ssh -p ${toString s.initrdSshPort} root@<vps>   → затем `systemd-tty-ask-password-agent`
  # (или подождать приглашение cryptsetup). Сессия живёт только до конца
  # stage-1, после расшифровки корня initrd-sshd убивается.
  boot.initrd.network.ssh = {
    enable = true;
    port = s.initrdSshPort;
    authorizedKeys = s.deployKeys;
    # Хост-ключ initrd НЕ в git и НЕ в /nix/store: кладётся на VPS при
    # установке в /etc/secrets/initrd/ и доупаковывается в initrd на активации
    # (модуль сам заводит boot.initrd.secrets; GRUB умеет initrd-secrets).
    # Он всё равно лежит на НЕшифрованном /boot, поэтому это служебный ключ
    # идентичности initrd, а НЕ рабочий ssh-host-key стадии 2 — роли не
    # смешивать. Сгенерировать заранее:
    #   ssh-keygen -t ed25519 -N "" -f ~/.nix/ssh/<host>_initrd_ed25519_key
    # и доставить nixos-anywhere --extra-files в /etc/secrets/initrd/.
    hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
  };

  # Clevis: достаёт фразу LUKS у Tang на доме и подаёт cryptsetup — загрузка
  # без человека. JWE не секрет (бесполезен без Tang), поэтому лежит в git.
  #
  # Включается при двух условиях сразу: s.enableClevis И наличие JWE этого
  # хоста (см. hasJwe выше). Так дерево остаётся собираемым, пока у части
  # хостов JWE ещё нет, а новый хост подхватывает авторазблокировку сам, как
  # только его JWE попадает в git.
  #
  # Модуль nixpkgs разворачивает это в initrd-юнит cryptsetup-clevis-<name>,
  # который умеет Wants/After=network-online.target при useTang (luksroot.nix),
  # а в stage 1 этот target гейтится systemd-networkd-wait-online. То есть
  # clevis не побежит раньше, чем у интерфейса появится адрес. DNS в initrd не
  # нужен: в JWE зашит URL с IP (settings.home.ip).
  boot.initrd.clevis = lib.mkIf clevisReady {
    enable = true;
    useTang = true;
    devices.${s.luksName}.secretFile = jweFile;
  };

  # Повторы и таймаут вместо вечного ожидания. Штатный юнит nixpkgs
  # (luksroot.nix) вызывает `clevis decrypt` ровно один раз, а curl внутри него
  # запущен только с --connect-timeout: если ответ Tang потеряется после
  # установки соединения, curl ждёт его бесконечно. Это случилось на nl-exit
  # 2026-10-09: канал NL↔дом теряет примерно каждый четвёртый поток (в initrd
  # 12 запросов /adv подряд — 3 таймаута), Tang отвечал 200, но ответ до NL не
  # дошёл. Юнит висел на «start running», а так как systemd-cryptsetup
  # упорядочен ПОСЛЕ него, приглашение фразы не появлялось вообще, и break-glass
  # SSH был бесполезен: вводить фразу было некуда.
  #
  # Перевод строки в конце JWE вычищаем: с ним `clevis decrypt` выдаёт верный
  # ключ, но завершается кодом 1 (jose не принимает "\n" после тега), и цикл
  # ниже честно крутился все 60 попыток (~80 с) при том, что Tang отвечал 200
  # на каждую. Так вышло с cloud02.jwe 2026-10-09 (файл заканчивался на 0x0a;
  # проверено: tr -d '\n' → код 0 с тем же ключом). Редакторы и `sops`/`echo`
  # такой перевод строки добавляют легко, поэтому чистим здесь, а не в файле.
  #
  # Теперь: у curl общий max-time 3 с (через CURL_HOME/.curlrc — аргументы curl
  # в clevis-decrypt-tang не поменять; удачный запрос занимает ~0.2 с, а потери
  # бывают у большинства потоков, поэтому много коротких попыток), и если за
  # ~4 минуты не вышло, юнит ЗАВЕРШАЕТСЯ ошибкой. НЕ задавать здесь `path`: он
  # заменяет PATH юнита целиком, и пропадает mount (так и случилось). Он подключён через wantedBy (мягкая
  # зависимость), поэтому systemd-cryptsetup после этого спросит фразу и
  # break-glass снова работает.
  boot.initrd.systemd.services."cryptsetup-clevis-${s.luksName}" = lib.mkIf clevisReady {
    script = lib.mkForce ''
      mkdir -p /clevis-${s.luksName} /run/clevis-curl
      mount -t ramfs none /clevis-${s.luksName}
      umask 277
      echo "max-time = 3" > /run/clevis-curl/.curlrc
      export CURL_HOME=/run/clevis-curl
      for attempt in {1..60}; do
        if ${pkgs.coreutils}/bin/tr -d '\n' < /etc/clevis/${s.luksName}.jwe \
          | clevis decrypt > /clevis-${s.luksName}/decrypted; then
          exit 0
        fi
        echo "clevis: попытка $attempt не удалась, повтор" >&2
        ${pkgs.coreutils}/bin/sleep 1
      done
      echo "clevis: Tang недоступен, жду ручного ввода фразы" >&2
      exit 1
    '';
  };

  # Без этого пропавший файл ключа НЕ приводит к запросу фразы: systemd-cryptsetup
  # падает сразу («key file missing»), и сидеть в initrd можно сколько угодно.
  # keyfile-timeout в crypttab говорит ждать файл N секунд и затем спрашивать
  # пароль — это и есть путь к break-glass, когда Tang недоступен.
  boot.initrd.luks.devices.${s.luksName}.keyFileTimeout = lib.mkIf clevisReady 5;

  # Подстраховка к builtins.path выше (подробности там же). Ссылку на JWE уже
  # несёт сам append-initrd-secrets, так что строка избыточна — но она делает
  # требование «JWE обязан быть в замыкании» явным и не зависящим от того, как
  # nixpkgs обходится с контекстом в stage-1.nix. Цена — одна строка, а цена
  # регрессии — упавший деплой.
  system.extraDependencies = lib.optional clevisReady jweFile;

  # Отсутствие JWE при поднятом флаге НЕ должно пройти молча: симптом —
  # «загрузился и недоступен», и отличить его от сетевой проблемы трудно.
  warnings = lib.optional (s.enableClevis && !hasJwe) ''
    clevis: нет ${toString jweSrc} — ${config.networking.hostName} не разблокируется
    сам и будет ждать ручного ввода фразы (break-glass SSH на порту ${toString s.initrdSshPort}).
    Как сгенерировать (нужен ключ СЛОТА 1 из disk-config.nix, не парольная фраза):
      clevis encrypt tang '{"url":"http://${s.home.ip}:${toString s.home.tangPort}"}' \
        < luks-clevis.key > secrets/clevis/${config.networking.hostName}.jwe
      git add secrets/clevis/${config.networking.hostName}.jwe
  '';

  # --- Сеть ----------------------------------------------------------------
  # DHCP (v4) + RA (v6) через networkd. Если хостер выдаёт адрес только
  # статикой — задать systemd.network.networks в hosts/<h>/default.nix.
  networking.useNetworkd = true;
  networking.useDHCP = lib.mkDefault true;

  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };

  # --- Фаервол -------------------------------------------------------------
  # nftables-бэкенд networking.firewall: одна таблица `inet` — правила
  # одинаково действуют на IPv4 и IPv6, политика input — drop, established/
  # related и loopback пропускаются самим модулем. Исходящие не режем.
  # Правила проверяются `nft -c` ещё при сборке (networking.nftables.checkRuleset).
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    # Отказы не логируем: на публичном IP это сотни строк в минуту от
    # сканеров, забивающие журнал на маленьком диске.
    logRefusedConnections = false;
    allowPing = true;
    pingLimit = "5/second burst 10 packets";
    # SSH — не через allowedTCPPorts (там безусловный accept), а с лимитом
    # новых соединений на адрес источника: перебор ключей бессмыслен и так,
    # но сканеры не будут бесконечно дёргать sshd. Сверх лимита пакет
    # проваливается в политику drop.
    extraInputRules = ''
      tcp dport ${toString s.sshPort} ct state new meter ssh4 { ip saddr limit rate 10/minute burst 5 packets } accept
      tcp dport ${toString s.sshPort} ct state new meter ssh6 { ip6 saddr and ffff:ffff:ffff:ffff:: limit rate 10/minute burst 5 packets } accept
    '';
  };

  # --- SSH -----------------------------------------------------------------
  services.openssh = {
    enable = true;
    ports = [ s.sshPort ];
    openFirewall = false; # порт открыт выше, с лимитом
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AllowUsers = [ "nix" ];
      ClientAliveInterval = 60;
      ClientAliveCountMax = 5;
    };
    # Только ed25519: этот же ключ — age-идентичность хоста для sops, он
    # сгенерирован заранее на ноутбуке и кладётся при установке
    # (nixos-anywhere --extra-files), см. ~/Stuff/xray-bypass/CLAUDE.md.
    hostKeys = [{ path = "/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }];
  };

  # --- Пользователи --------------------------------------------------------
  # mutableUsers = false: состояние пользователей целиком из конфига, `passwd`
  # на самом VPS ничего не меняет надолго. Хэш пароля nix — в sops
  # (secrets/vps.yaml, общий для всех VPS), расшифровывается до создания
  # пользователей (neededForUsers).
  users.mutableUsers = false;
  users.users.root.hashedPassword = "!"; # вход root невозможен ни как
  users.users.nix = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPasswordFile = config.sops.secrets.nix-password.path;
    openssh.authorizedKeys.keys = s.deployKeys;
  };
  sops.secrets.nix-password.neededForUsers = true;

  # sudo, а не doas, как на остальных машинах: nixos-rebuild
  # --ask-sudo-password передаёт пароль через `sudo --stdin`, чего нет ни в
  # doas, ни в doas-sudo-shim. Пароль нужен (wheelNeedsPassword): ключ от SSH
  # сам по себе root не даёт.
  security.sudo = {
    enable = true;
    execWheelOnly = true;
    wheelNeedsPassword = true;
  };

  # --- sops ----------------------------------------------------------------
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ../../../secrets/vps.yaml;

  # --- Nix -----------------------------------------------------------------
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    # Сюда пути приходят только готовыми: собирает домашний сервер или
    # ноутбук (deploy-rs, см. flake.nix) и подписывает своим ключом, либо
    # они из cache.nixos.org. trusted-users остаётся по умолчанию (только
    # root).
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      # Часть замыкания (CUDA-пакеты) приходит с подписью cache.nixos-cuda.org:
      # сервер её качает и отдаёт дальше с чужой подписью, и без этого ключа
      # VPS отвергает такие пути при `nix copy` (тот же ключ — hosts/server).
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      s.serverSigningKey
    ] ++ lib.optional (s.laptopSigningKey != "") s.laptopSigningKey;
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  # Каналы на VPS не нужны — система приезжает готовой из флейка.
  nix.channel.enable = false;

  # --- Прочее --------------------------------------------------------------
  time.timeZone = "UTC";
  # Скрытность: журнал ТОЛЬКО в RAM (tmpfs /run/log/journal), на диск ничего
  # не пишется и при перезагрузке исчезает. На работающей машине journalctl
  # по-прежнему доступен для диагностики; RuntimeMaxUse ограничивает объём,
  # чтобы журнал не отъел память на 1 ГБ RAM.
  services.journald.storage = "volatile";
  services.journald.extraConfig = ''
    RuntimeMaxUse=50M
  '';
  environment.systemPackages = with pkgs; [ vim htop curl tmux ];

  # minimal.nix режет terminfo-базу ncurses до пары основных записей. SSH-клиент
  # передаёт сюда локальный $TERM (это часть pty-запроса, не SendEnv/AcceptEnv),
  # и современные терминалы (Ghostty → "xterm-ghostty", Kitty, WezTerm...) в
  # усечённой базе не находятся. systemd (systemctl status и другие юниты с
  # цветным/табличным выводом) при неизвестном TERM тихо падает на определении
  # возможностей терминала и не печатает вообще ничего — выглядит как зависший
  # или пустой вывод, хотя команда отработала. enableAllTerminfo возвращает
  # полную базу ncurses вместо урезанной.
  environment.enableAllTerminfo = true;

  system.stateVersion = "26.05";
}
