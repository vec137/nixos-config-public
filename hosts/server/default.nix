{ config, lib, pkgs, ... }:

let
  # Общие параметры связки VPS: отсюда берём порт Tang и белые адреса VPS для
  # сужения доступа к Tang (см. секцию «Tang» ниже).
  vpn = import ../../modules/nixos/vpn/settings.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/server.nix
    ../../modules/nixos/mihomo.nix
    ../../modules/nixos/xray-client.nix
    ../../modules/nixos/mihomo-subscriptions.nix
  ];

  # Балансировщик mihomo (modules/nixos/mihomo.nix): апстримы — xray@ (3080)
  # и подписки (общие с ноутбуком: modules/nixos/mihomo-subscriptions.nix).
  services.mihomoBalancer.enable = true;

  networking.hostName = "server";

  ###########################################################################
  # Tang — сетевая разблокировка LUKS на VPS (Clevis/Tang)
  ###########################################################################

  # VPS (ru-edge/nl-exit) при загрузке, ещё в initrd, достают у этого Tang
  # парольную фразу своего LUKS-корня и расшифровываются без человека. Tang
  # безопасен к прослушке и к компрометации сервера: он НЕ знает ни ключа, ни
  # фразы — хранит лишь публичную половину пары, участвует в протоколе
  # McCallum–Relyea и отдаёт ответ, бесполезный в отрыве от JWE на VPS.
  # Поэтому даже выставленный наружу он не раскрывает секрета.
  #
  # Доступ всё равно сужен: модуль сам ставит на сокет и сервис
  # IPAddressDeny=any + IPAddressAllow=<эти адреса> (cgroup-фильтр ядра),
  # так что отвечает Tang только обоим VPS, а не всему интернету.
  # Адреса в settings.hosts — реальные, оба VPS в whitelist (проверено
  # 2026-10-07: GET /adv с ru-edge отдаёт 200 за ~120 мс).
  services.tang = {
    enable = true;
    listenStream = [ (toString vpn.home.tangPort) ];
    ipAddressAllow = [ vpn.hosts.ru-edge vpn.hosts.nl-exit ];
  };
  # Фаервол открывает порт (источник уже ограничен самим Tang выше).
  # НАПОМИНАНИЕ: на роутере пробросить TCP ${toString vpn.home.tangPort}
  # на этот сервер, а home.ip в settings.nix держать актуальным (белый IP/DDNS).
  networking.firewall.allowedTCPPorts = [ vpn.home.tangPort ];
  time.timeZone = "Europe/Moscow";

  ###########################################################################
  # Загрузка и дуал-бут с Windows
  ###########################################################################

  # GRUB с os-prober: одно меню на обе ОС, Windows выбирается строкой в списке,
  # без захода в boot-меню платы.
  #
  # При этом GRUB ставится в ESP на NVMe (hosts/server/disk-config.nix), то есть
  # на свой диск, а НЕ на ESP Windows. Это важно и даёт лучшее из двух вариантов:
  # крупное обновление Windows переписывает загрузочные записи на своём ESP и до
  # нашего GRUB не дотягивается, а os-prober находит на том, чужом ESP файл
  # bootmgfw.efi и генерирует для него пункт-chainloader. Ломать друг друга им
  # по-прежнему нечем.
  #
  # Что стоит знать про os-prober, потому что это не всегда очевидно:
  #  * он запускается не при загрузке, а при `nixos-rebuild` (во время генерации
  #    grub.cfg). Windows, установленная или переставленная позже, сама в меню
  #    не появится — нужно прогнать rebuild ещё раз;
  #  * он читает разделы других ОС, поэтому в Windows стоит выключить
  #    «быстрый запуск» (Fast Startup). С ним Windows при завершении работы не
  #    выключается, а уходит в гибернацию, оставляя NTFS в «грязном» состоянии —
  #    это и мешает определению, и грозит повреждением раздела при монтировании
  #    из Linux;
  #  * Windows Update иногда ставит свою запись первой в NVRAM. Тогда машина
  #    загрузится сразу в Windows мимо GRUB — лечится порядком загрузки в BIOS
  #    (или `efibootmgr -o`), это не поломка конфигурации.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    # Для EFI-установки целевой «диск» не указывается: GRUB кладётся в ESP,
    # смонтированный в /boot, а не в MBR. Отсюда nodev.
    device = "nodev";
    useOSProber = true;
    configurationLimit = 10; # ESP на 1 ГБ, не копить ядра бесконечно
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # modules/nixos/server.nix ставит 3 секунды (headless-машине меню читать
  # некому). Здесь меню — это именно то, ради чего всё и делалось, поэтому
  # времени на выбор чуть больше.
  boot.loader.timeout = 5;

  # Windows хранит в аппаратных часах локальное время, Linux по умолчанию — UTC.
  # Без этой строки две системы при каждой смене ОС переставляют RTC друг другу,
  # и часы уезжают на величину часового пояса (здесь — на 3 часа).
  time.hardwareClockInLocalTime = true;

  ###########################################################################
  # Сеть
  ###########################################################################

  # По умолчанию DHCP — подтверждено установкой 2026-09-20, адрес получен сам
  # (192.168.1.148, реальный сгенерированный hardware-configuration.nix не
  # содержит явного networking.useDHCP — в отличие от прежнего плейсхолдера,
  # это ничему не мешает).
  # Машину находят по SSH, поэтому адрес должен быть стабильным: либо
  # зарезервировать его по MAC на роутере, либо раскомментировать статику ниже,
  # подставив реальное имя интерфейса (`ip -br link`) и адреса своей сети.
  #
  # networking.useDHCP = false;
  # networking.interfaces.enp1s0.ipv4.addresses = [{
  #   address = "192.168.1.10";
  #   prefixLength = 24;
  # }];
  # networking.defaultGateway = "192.168.1.1";
  # networking.nameservers = [ "192.168.1.1" ];

  ###########################################################################
  # Доступ
  ###########################################################################

  # Ключ, которым ноутбук входит на этот сервер. Вход по паролю выключен в
  # modules/nixos/server.nix, так что пустой список здесь означал бы машину,
  # в которую нельзя попасть вообще.
  #
  # Приватная половина — ssh/server на ноутбуке (каталог целиком в .gitignore),
  # она же прописана как identityFile в профиле "server" в
  # modules/home/misc.nix. Это НЕ ssh/server_host_ed25519_key: тот отвечает за
  # личность самого сервера и его публичная часть лежит в
  # programs.ssh.knownHosts (hosts/laptop/default.nix). Роли не смешивать —
  # см. docs/repo-notes.md.
  users.users.nix.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAypF7YGdE7HjrhUdZB/WSsrvTH4Qaylm4zN6PR3QpE+ server"
  ];

  # Без linger systemd останавливает пользовательский менеджер при выходе из
  # последней сессии — а на машине, куда заходят по SSH и сразу выходят, это
  # означает, что юниты systemd --user живут ровно столько, сколько открыт
  # терминал. Здесь такие юниты есть: hermes-backend (hosts/server/home.nix),
  # и ему положено работать между заходами. home-manager сам `loginctl
  # enable-linger` вызвать не может, поэтому строка стоит здесь.
  #
  # Обратная сторона, уже описанная в docs/repo-notes.md про ноутбук: менеджер с linger
  # не перезапускается вообще, то есть home.sessionVariables, которые
  # home-manager кладёт в ~/.config/environment.d/, он читает один раз при
  # своём старте и потом годами отдаёт устаревшее значение. Лечится
  # `systemctl --user unset-environment ИМЯ` или перезапуском
  # user@1000.service, но не перелогином.
  users.users.nix.linger = true;

  # isNormalUser/shell/doas — из modules/nixos/common.nix, здесь только группы
  # этого хоста поверх (списки в модульной системе сливаются, а не заменяются).
  users.users.nix.extraGroups = [
    "wheel"
    "vboxusers" # без неё VBoxManage не увидит ВМ пользователя
    "systemd-journal"
    "video"
    "render"
  ];

  ###########################################################################
  # GPU: RTX 4070, только под вычисления
  ###########################################################################

  # services.xserver.enable = false (modules/nixos/server.nix), но videoDrivers
  # всё равно нужен: именно эта опция подключает модуль hardware.nvidia,
  # собирает модуль ядра и кладёт в систему libcuda/nvidia-smi. Без неё
  # драйвера на headless-машине просто не будет.
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # Открытый модуль ядра — рекомендованный NVIDIA путь для Turing и новее
    # (4070 — Ada), проприетарный для этих чипов объявлен устаревшим.
    # Если упрётся в сборку/загрузку модуля — поменять на false.
    open = true;
    modesetting.enable = true;
    nvidiaSettings = false; # GUI-утилита, на сервере не нужна
    powerManagement.enable = false; # незачем: машина не засыпает
  };
  hardware.enableRedistributableFirmware = true;

  # Бинарный кеш проекта cuda-maintainers. Без него любая сборка с
  # cudaSupport = true (в т.ч. llama-cpp из modules/home/profiles/
  # local-inference.nix) компилируется локально часами — CUDA-пакеты
  # несвободные, и cache.nixos.org их не раздаёт.
  nix.settings.extra-substituters = [ "https://cache.nixos-cuda.org" ];
  nix.settings.extra-trusted-public-keys = [
    "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
  ];

  ###########################################################################
  # VirtualBox — гипервизор, под который написаны образы курса (.ova)
  ###########################################################################

  virtualisation.virtualbox.host.enable = true;
  # Extension Pack сознательно не включён: он несвободный, собирается локально
  # и нужен ради USB 2.0/3.0 passthrough и VRDP. Пайплайн лаб работает через
  # headless + SSH с пробросом порта, ему это не требуется.
  # virtualisation.virtualbox.host.enableExtensionPack = true;

  ###########################################################################
  # Сборка
  ###########################################################################

  # 24 ядра / 48 потоков. max-jobs — сколько пакетов собирается параллельно,
  # cores — сколько потоков даётся каждому. 8 x 6 = 48 потоков под полной
  # загрузкой; специально не 48 x 1, потому что многие сборки сами по себе
  # плохо параллелятся, и не 1 x 48 — тогда простаивают ядра между пакетами.
  nix.settings.max-jobs = 8;
  nix.settings.cores = 6;

  # Ноутбук использует этот хост как distributed-build машину (см. nix.
  # buildMachines в hosts/laptop/default.nix), подключаясь по ssh как "nix",
  # не root. Без этого — только root доверенный по умолчанию — daemon
  # отказывает в сборке input-addressed (обычных, не content-addressed)
  # деривации с "you are not privileged to build input-addressed
  # derivations": для не-CA деривации результат нельзя проверить по хешу
  # после сборки, поэтому демон требует, чтобы сборку запрашивал доверенный
  # пользователь — недоверенный builder мог бы подсунуть что угодно.
  nix.settings.trusted-users = [ "nix" ];

  # Подпись всего, что собирает этот сервер. Нужна VPS (ru-edge, nl-exit):
  # они собираются здесь (nixos-rebuild --build-host server) и принимают
  # только подписанные пути, не делая деплой-пользователя trusted-user.
  # Публичная половина — modules/nixos/vpn/settings.nix (serverSigningKey).
  # Подписываются только пути, собранные ПОСЛЕ включения; уже лежащие в
  # store — вручную: doas nix store sign -k /run/secrets/nix-signing-key -r <путь>.
  nix.settings.secret-key-files = [ config.sops.secrets.nix-signing-key.path ];

  ###########################################################################
  # HDD 1 ТБ — пока не используется
  ###########################################################################

  # Диск сознательно не описан в disko (иначе установка его затрёт) и не
  # монтируется. Когда понадобится под бэкапы: разметить и отформатировать
  # руками один раз, узнать UUID (`lsblk -f`) и раскомментировать. nofail
  # обязателен — без него отвалившийся или неотформатированный диск уронит
  # загрузку в emergency mode, а он на этом хосте выключен, то есть машина
  # просто не поднимется в сеть.
  #
  # fileSystems."/mnt/backup" = {
  #   device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
  #   fsType = "ext4";
  #   options = [ "nofail" "x-systemd.device-timeout=10s" ];
  # };

  ###########################################################################
  # Шрифты — не для красоты, а ради правильной вёрстки отчётов
  ###########################################################################

  # modules/nixos/server.nix выключает шрифты по умолчанию (headless-машине они
  # не нужны), но здесь нужны, и именно эти. Шаг 9 пайплайна лаб конвертирует
  # .docx в .pdf через soffice и вычитывает из PDF реальные номера страниц для
  # оглавления. Если Times New Roman в системе нет, LibreOffice подставит
  # замену с другими метриками, текст перетечёт по-другому, и номера страниц
  # разойдутся с теми, что получались на ноутбуке, — причём молча.
  #
  # corefonts — настоящие Times New Roman/Arial от Microsoft (несвободные,
  # уже разрешены в allowUnfreePredicate в modules/nixos/common.nix).
  # liberation_ttf — метрически совместимые запасные,
  # noto-fonts — покрытие кириллицы там, где её нет в остальных.
  fonts.enableDefaultPackages = lib.mkForce true;
  fonts.packages = with pkgs; [
    corefonts
    vista-fonts
    liberation_ttf
    noto-fonts
    dejavu_fonts
  ];

  ###########################################################################
  # HuggingFace — токен для скачивания моделей
  ###########################################################################

  # Декрифруется в /run/secrets/hf-token. owner = "nix", потому что читает его
  # не системный сервис, а интерактивная fish-функция от пользователя (см.
  # llama-server/llama-cli в hosts/server/home.nix) — тем же приёмом, что
  # omniroute-api-key/obsidian-api-key на ноутбуке.
  # sopsFile переопределяет defaultSopsFile (secrets/common.yaml) из
  # modules/nixos/common.nix: это заведено под именно этот хост ещё в
  # .sops.yaml (ключа ноутбука среди получателей secrets/server.yaml нет).

  ###########################################################################
  # xray — клиент VPN
  ###########################################################################

  # Клиент xray — общий модуль с ноутбуком (modules/nixos/xray-client.nix):
  # шаблонный юнит xray@ и sops-секреты вариантов. Здесь только выбор варианта
  # по умолчанию, тот же, что на ноутбуке: с домашнего IP прямой Reality до NL
  # (203.0.113.20:443) не устанавливается (проверено 2026-10-09, таймаут), а
  # через CDN работает.
  services.xrayClient = {
    enable = true;
    default = "xhttp_cdn";
  };

  sops.secrets = {
    # Дешифруется в /run/secrets/hf-token. owner = "nix", потому что читает
    # его не системный сервис, а интерактивная fish-функция от пользователя
    # (llama-server/llama-cli в hosts/server/home.nix) — тем же приёмом, что
    # omniroute-api-key/obsidian-api-key на ноутбуке. sopsFile переопределяет
    # defaultSopsFile (secrets/common.yaml) из modules/nixos/common.nix: это
    # заведено под именно этот хост ещё в .sops.yaml (ключа ноутбука среди
    # получателей secrets/server.yaml нет).
    hf-token = {
      owner = "nix";
      sopsFile = ../../secrets/server.yaml;
    };

	openrouter-api-key.owner = "nix";

	# Приватный ключ подписи сборок (см. secret-key-files выше); читает
	# nix-daemon, т.е. root — владелец по умолчанию подходит.
	nix-signing-key.sopsFile = ../../secrets/server.yaml;

	omniroute-api-key.owner = "nix";
  };

  ###########################################################################
  # proxychains
  ###########################################################################

  # Обёртка, заворачивающая TCP-соединения произвольной программы в SOCKS/HTTP-
  # прокси: `proxychains4 <команда>`. Нужна там же, где и на ноутбуке — обойти
  # гео-блокировки провайдеров моделей (`draft.sh`/omniroute из пайплайна лаб
  # упирались в них напрямую, см. ~/Stuff/sut/ЗОССС_ЛАБЫ/CLAUDE.md).
  #
  # Здесь используется штатный модуль programs.proxychains, а не ручная запись
  # environment.etc."proxychains.conf" как в hosts/laptop/default.nix: модуль
  # сам ставит пакет, генерирует конфиг и проверяет типы (порт — это port, тип
  # прокси — enum из http/socks4/socks5), тогда как ручной файл — просто текст,
  # в котором опечатка обнаружится только в рантайме.
  #
  # Ходит через mihomo на 6080 (modules/nixos/mihomo.nix): он сам
  # выбирает между xray@ (3080, экземпляр services.xrayClient.default) и
  # узлами подписки, а ручной выбор делается в metacubexd. Если mihomo
  # остановлен или все апстримы мертвы, proxychains не уйдёт в обход, а
  # вернёт приложению ошибку, см. про dynamic ниже.
  #
  # Запасной вариант, когда на сервере VPN-клиент поднимать не хочется:
  # пробросить уже работающий порт ноутбука обратным туннелем поверх того же
  # SSH-подключения — `ssh -R 3080:127.0.0.1:3080 server` (порт 3080, не
  # 6080: 6080 занят mihomo сервера, а 3080 — это socks xray и есть апстрим
  # mihomo). Тогда xray@ здесь можно не запускать вовсе.
  programs.proxychains = {
    enable = true;
    # dynamic (как в proxychains.conf на ноутбуке), а не strict по умолчанию:
    # мёртвые прокси из цепочки пропускаются, и когда позже добавится второй
    # вход, отвалившийся первый не будет ронять всю цепочку. Важная тонкость:
    # это НЕ означает «если прокси недоступен, пойти напрямую» — если живых в
    # списке не осталось вовсе, приложение получает EINTR. То есть тихой утечки
    # мимо туннеля не будет, что здесь как раз и нужно.
    chain.type = "dynamic";
    # DNS тоже через прокси. Иначе имена резолвятся напрямую, и запрос выдаёт
    # и факт обращения, и реальное местоположение — при обходе гео-блокировок
    # это сводит на нет весь смысл.
    proxyDNS = true;
    tcpReadTimeOut = 15000;
    tcpConnectTimeOut = 15000;
    proxies = {
      # Имена ключей задают порядок в цепочке (атрибуты сортируются по имени),
      # поэтому у добавляемых дальше прокси имена стоит выбирать осознанно.
      mihomo = {
        enable = true;
        type = "socks5";
        host = "127.0.0.1";
        port = 6080;
      };
    };
  };

  ###########################################################################
  # SearXNG — метапоисковик, через который ищет hermes
  ###########################################################################

  # Опция называется services.searx (историческое имя), но пакет по умолчанию —
  # searxng, живой форк.
  #
  # Режим запуска — встроенный HTTP-сервер: configureUwsgi/configureNginx
  # оставлены выключенными. Связка uwsgi + nginx в модуле предусмотрена для
  # публичного или нагруженного инстанса; здесь слушатель на петле и ровно один
  # клиент — hermes с этой же машины. Цена простоты: встроенный сервер по
  # умолчанию пишет в журнал все запросы, то есть поисковые запросы агента
  # видны в journalctl.
  services.searx = {
    enable = true;
    settings = {
      general.instance_name = "server";
      general.debug = false;

      # Наружу не торчит: доступ к веб-интерфейсу — туннелем поверх SSH
      #   ssh -N -L 8888:127.0.0.1:8888 server
      # ровно как к llama-server и к панели hermes. В фаервол ничего добавлять
      # не нужно (openFirewall остаётся false).
      server.bind_address = "127.0.0.1";
      server.port = 8888;

      # Значение подставляется из environmentFile ниже: модуль прогоняет
      # settings.yml через envsubst в юните searx-init, поэтому здесь стоит имя
      # переменной, а не сам ключ. Писать ключ строкой прямо сюда нельзя —
      # settings.yml уезжает в /nix/store, который читается всеми.
      server.secret_key = "$SEARXNG_SECRET_KEY";

      # Главное, ради чего вообще всё. SearXNG из коробки отдаёт только HTML, а
      # на /search?format=json отвечает 403 — и hermes ходит именно в JSON-API.
      # Если web_search вдруг вернёт {"success": false}, проверять надо в первую
      # очередь эту строку.
      search.formats = [ "html" "json" ];

      # Если поисковики начнут отказывать из-за географии (та же беда, из-за
      # которой на этой машине вообще есть xray и proxychains), SearXNG умеет
      # ходить к ним через прокси сам. Форма ключа — httpx-овская, вида
      # `all://`; перед включением сверяться с документацией SearXNG, раздел
      # outgoing.proxies — здесь это непроверенная подсказка, а не готовая
      # настройка:
      #
      # outgoing.proxies."all://" = [ "socks5h://127.0.0.1:6080" ];
    };

    # Тип опции — path, но строка, начинающаяся со слэша, путём в /nix/store не
    # становится: файл читается в рантайме, как и пути от sops-nix.
    environmentFile = "/var/lib/searx-secret/env";
  };

  # SearXNG подписывает этим ключом пользовательские настройки и отказывается
  # работать со значением по умолчанию. Ключ нужен один-единственной машине и
  # между хостами не разделяется — а sops в этом репозитории существует ровно
  # ради обратного, ради секретов, которые должны расшифровываться на
  # нескольких машинах. Поэтому ключ не кладётся в secrets/, а генерируется на
  # месте при первом запуске и дальше просто лежит в /var/lib.
  #
  # Порядок здесь не косметика: EnvironmentFile systemd читает силами PID 1 в
  # момент запуска юнита, то есть файл обязан существовать ДО старта
  # searx-init. requiredBy + before дают ровно это (и заодно избавляют от
  # wantedBy — юнит поднимется сам, когда его потребует searx-init).
  systemd.services.searx-secret-key = {
    description = "Сгенерировать secret_key для SearXNG при первом запуске";
    requiredBy = [ "searx-init.service" ];
    before = [ "searx-init.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # StateDirectory создаёт /var/lib/searx-secret и следит за правами; 0700
      # и root:root достаточно, потому что читать файл будет systemd, а не сам
      # searx (он к этому моменту уже получит значение через окружение).
      StateDirectory = "searx-secret";
      StateDirectoryMode = "0700";
      UMask = "0077";
    };
    script = ''
      if [ ! -s /var/lib/searx-secret/env ]; then
        printf 'SEARXNG_SECRET_KEY=%s\n' "$(${pkgs.openssl}/bin/openssl rand -hex 32)" \
          > /var/lib/searx-secret/env
      fi
    '';
  };

  ###########################################################################
  # Прочее
  ###########################################################################

  # Страховка для os-prober: он монтирует разделы чужих ОС, чтобы их опознать.
  # Для Windows на EFI обычно хватает чтения vfat-раздела ESP, но если
  # понадобится заглянуть в сам NTFS — без драйвера попытка молча не даст
  # результата, и Windows просто не появится в меню.
  environment.systemPackages = [ 
  	  pkgs.ntfs3g
  	  # see https://wiki.nixos.org/wiki/Python#Using_nix-ld
  	  (pkgs.writeShellScriptBin "pythonld" ''
    	export LD_LIBRARY_PATH=$NIX_LD_LIBRARY_PATH
    	exec -a "$0" ${pkgs.python3}/bin/python "$@"
  	  '')
  ];

  # nix-ld даёт стандартный путь к динамическому линковщику
  # (/lib64/ld-linux-x86-64.so.2), которого в NixOS нет. Нужен, чтобы запускать
  # непропатченные чужие бинарники: готовые релизы llama.cpp с GitHub (запасной
  # путь, если сборка с CUDA окажется неподъёмной) и native-модули, которые
  # npm тянет сам при `npm install` в пайплайне отчётов.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
  	  zlib zstd stdenv.cc.cc curl openssl attr libssh bzip2 libxml2 acl libsodium util-linux xz systemd
  ];

  programs.fish.enable = true;

  # llama-server слушает 127.0.0.1 и наружу не открывается: доступ с ноутбука
  # делается туннелем поверх уже имеющегося SSH
  #   ssh -N -L 8080:127.0.0.1:8080 server
  # Это и безопаснее (порт не торчит в сеть), и не требует ничего добавлять в
  # фаервол. Если всё же захочется открыть напрямую:
  # networking.firewall.allowedTCPPorts = [ 8080 ];

  # Первая версия NixOS на этой машине — не менять после установки.
  system.stateVersion = "26.05";
}
