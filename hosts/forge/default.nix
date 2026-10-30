{ config, lib, pkgs, ... }:

let
  #############################################################################
  # ГЛАВНЫЙ ПЕРЕКЛЮЧАТЕЛЬ ПЕРВОЙ УСТАНОВКИ
  #############################################################################
  #
  # sops-nix расшифровывает секреты хостовым SSH-ключом (modules/nixos/
  # common.nix, sops.age.sshKeyPaths). Пока age-ключ этого хоста не внесён в
  # .sops.yaml И файлы не перешифрованы (`sops updatekeys`, делает
  # пользователь — у Claude нет admin-ключа), forge не может открыть
  # secrets/common.yaml. А sops-install-secrets падает
  # жёстко: не «предупреждение», а провал всей активации, то есть
  # неудавшийся `nixos-install` или нерабочий `nixos-rebuild switch`.
  #
  # Поэтому всё, что требует секретов (mihomo, то есть выход в интернет через
  # наш туннель, и omniroute-ключ), собрано под один флаг:
  #
  #   false — машину можно установить и загрузить прямо сейчас, без sops.
  #           Агенты при этом работают только через прямой интернет
  #           (claude-code к api.anthropic.com из РФ так не достучится).
  #   true  — штатный режим; ставить ПОСЛЕ шага 5 в docs/install-forge.md.
  #
  # Это обычная let-переменная, а не опция модуля: она влияет на imports,
  # а их список вычисляется до того, как модульная система собирает config,
  # и ссылаться там на config.* нельзя (бесконечная рекурсия).
  secretsReady = true;

  # Публичный ключ ноутбука — ровно тот же, который лежит в authorizedKeys у
  # server (hosts/server/default.nix): это один клиентский ключ ноутбука на
  # оба хоста, а не ключ «от forge». Назван отдельно, чтобы в месте
  # использования было видно, ЧЕЙ это ключ, а не 80 символов base64.
  laptopKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAypF7YGdE7HjrhUdZB/WSsrvTH4Qaylm4zN6PR3QpE+ server";
in
{
  # Временный второй сервер: платформа (мать + CPU + RAM) от старого ПК,
  # посаженная на второй комплект разъёмов блока питания основного сервера.
  # Назначение — тяжёлые агентские задачи: агент (pi/claude-code) поднимает
  # здесь виртуалки и работает внутри них. Инференс остаётся на `server`,
  # этот хост его не дублирует и ничего на нём не меняет.
  #
  # Почему отдельный хост, а не ещё один профиль на server: гипервизоры
  # забирают VMX/SVM монопольно (см. раздел «Виртуализация» ниже), и держать
  # VirtualBox/VMware на машине, которая круглосуточно считает на GPU, —
  # значит ломать инференс ради лаб.
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/server.nix
  ] ++ lib.optionals secretsReady [
    # Выход в интернет — mihomo на 127.0.0.1:6080 (mixed http+socks5) поверх
    # подписок; через него ходят claude-code и pi.
    ../../modules/nixos/mihomo.nix
    ../../modules/nixos/mihomo-subscriptions.nix

    # Настройки этих модулей лежат здесь же, а не ниже в теле файла: при
    # secretsReady = false опции services.mihomoBalancer не существует вовсе
    # (модуль не подключён), и любое присваивание ей уронило бы eval с
    # «option does not exist». Вложенный attrset в imports — это полноценный
    # модуль, так что оба куска включаются и выключаются одним флагом.
    {
      services.mihomoBalancer.enable = true;

      # Локального xray@ на этой машине нет и не планируется — работаем
      # только через подписки (в т.ч. нашу ruedge). Без этой строки модуль
      # оставил бы в группах auto/proxy апстрим "xray" на 127.0.0.1:3080,
      # то есть заведомо мёртвый узел, который url-test будет дёргать
      # впустую. Заодно не нужен ни один файл из secrets/xray/, значит
      # forge не надо вносить в получатели этих секретов.
      services.mihomoBalancer.xrayUpstream = false;

      # Ключ OmniRoute для MCP-сервера Claude Code (modules/home/
      # omniroute-mcp.nix читает его из /run/secrets при активации
      # home-manager). owner = nix, потому что читает не системный сервис, а
      # пользовательский activation-скрипт — тот же приём, что на ноутбуке.
      sops.secrets.omniroute-api-key.owner = "nix";
    }
  ];

  networking.hostName = "forge";
  time.timeZone = "Europe/Moscow";

  # Шрифт консоли с кириллицей вместо lat4a-19 из modules/nixos/common.nix (в
  # нём её нет): и агент (claude/pi), и этот репозиторий отвечают по-русски, а
  # с латинским шрифтом такой вывод в tty превращается в знаки вопроса.
  #
  # Оговорка: у машины нет видеовыхода, так что сейчас эта строка — задел на
  # случай, если видео появится (на последовательную консоль шрифт не влияет,
  # там рисует терминал на том конце провода). Работать с forge предполагается
  # по SSH.
  #
  # mkForce, потому что common.nix задаёт console.font обычным присваиванием.
  console.font = lib.mkForce "latarcyrheb-sun16";

  ###########################################################################
  # Шрифты
  ###########################################################################

  # Тот же блок, что в hosts/server/default.nix, и по той же причине: здесь
  # живёт ~/Stuff/sut с пайплайном отчётов, а modules/nixos/server.nix (его
  # импортирует и forge) выключает шрифты по умолчанию как headless-машине.
  #
  # Это не косметика, а условие работоспособности приёмки: шаг «docx → pdf»
  # идёт через soffice, который при отсутствии Times New Roman молча подставляет
  # замену с другими метриками, и разбиение на страницы меняется. Замерено
  # 2026-10-30 на уже принятом отчёте: принятый PDF (server, с corefonts) —
  # 13 страниц и TimesNewRomanPSMT в pdffonts; тот же .docx, отрендеренный на
  # forge без шрифтов, — 15 страниц и DejaVuSans. Разница в две страницы — это
  # ровно тот дефект, который приёмка по числу страниц обязана ловить.
  #
  # corefonts/vista-fonts — настоящие Times New Roman/Arial от Microsoft
  # (несвободные, уже разрешены в allowUnfreePredicate в modules/nixos/common.nix,
  # который mkHost подмешивает всем хостам).
  fonts.enableDefaultPackages = lib.mkForce true;
  fonts.packages = with pkgs; [
    corefonts
    vista-fonts
    liberation_ttf
    noto-fonts
    dejavu_fonts
  ];
  ###########################################################################
  # Загрузчик
  ###########################################################################

  # ГИБРИДНЫЙ GRUB: загрузчик ставится И в UEFI (ESP), И в MBR диска.
  #
  # Зачем так, а не как обычно: у этой машины нет видеовыхода, систему ставят
  # на диск в ДРУГОЙ машине и потом переставляют. Значит угадать режим
  # загрузки заранее нельзя, а проверить на месте — нечем: если прошивка
  # окажется Legacy/CSM, а загрузчик стоит только в ESP (или наоборот),
  # получится машина, которая молча не грузится и не даёт никаких признаков.
  #
  # Механика (nixos/modules/system/boot/loader/grub/install-grub.pl,
  # getEfiTarget): скрипт установки смотрит на два значения — `grub` и
  # `grubEfi`. Первое непусто, когда devices ≠ [ "nodev" ], второе — когда
  # efiSupport = true. Если оба непусты, efiTarget становится "both", и
  # grub-install вызывается ДВА раза: `--target=i386-pc` на сам диск (код в
  # MBR + вторая стадия в раздел bios_grub, который disko создаёт первым) и
  # `--target=x86_64-efi` в ESP. Один диск, грузится в любом режиме.
  #
  # efiInstallAsRemovable = true кладёт EFI-часть в \EFI\BOOT\BOOTX64.EFI —
  # путь «съёмного носителя», который пробует любая прошивка, и не требует
  # записи NVRAM-переменных (canTouchEfiVariables остаётся false). Для диска,
  # который переезжает между машинами, это обязательно: NVRAM-запись сделана
  # была бы на машине-установщике и в forge всё равно не действовала.
  #
  # ОТКУДА БЕРЁТСЯ `devices`, которого здесь нет: его задаёт disko.
  # В lib/types/gpt.nix он добавляет `boot.loader.grub.devices = [ <диск> ]`,
  # если среди разделов есть хоть один типа EF02 — а он есть, это раздел
  # bios_grub из hosts/forge/disk-config.nix. То есть путь к диску остаётся
  # объявленным в одном месте (_module.args.disks во flake.nix), а здесь
  # достаточно включить efiSupport, чтобы установка стала гибридной.
  #
  # Дублировать строку тут нельзя: списки в модульной системе сливаются, и
  # диск попал бы в devices дважды — grub-install честно выполнился бы на одном
  # и том же диске два раза (проверено на сгенерированном grub-config.xml).
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;

    # GRUB дублирует меню и ввод в последовательный порт. На машине без
    # видеовыхода это единственный способ увидеть, что вообще происходит до
    # загрузки ядра (нужен USB-UART на COM-порт платы, если он есть).
    # `terminal_* serial console` — оба терминала сразу: если видео когда-то
    # появится, меню будет и там.
    extraConfig = ''
      serial --unit=0 --speed=115200
      terminal_input serial console
      terminal_output serial console
    '';
  };

  # Windows/другие ОС на этой машине не ожидаются (диски старого ПК переехали
  # в основной сервер), поэтому os-prober не включается — он замедляет каждый
  # rebuild и требует монтировать чужие разделы.
  boot.loader.grub.useOSProber = false;

  # /tmp чистится при загрузке, но остаётся НА ДИСКЕ. tmpfs (/tmp в RAM) на
  # VPS оправдан — там он прячет временные файлы с незашифрованного диска, —
  # а здесь был бы вредом: он съедает ту самую RAM, под которую нарезаются
  # виртуалки, и агент, распаковывающий в /tmp образ Windows, уронил бы хост
  # в OOM.
  boot.tmp.cleanOnBoot = true;

  ###########################################################################
  # Сеть
  ###########################################################################

  # DHCP: имя интерфейса на незнакомой плате заранее неизвестно, а статику
  # удобнее держать резервацией по MAC на роутере. Если адрес всё же надо
  # зафиксировать на хосте — раскомментировать, подставив `ip -br link`.
  #
  # networking.useDHCP = false;
  # networking.interfaces.enp3s0.ipv4.addresses = [{
  #   address = "192.168.1.147";
  #   prefixLength = 24;
  # }];
  # networking.defaultGateway = "192.168.1.1";
  # networking.nameservers = [ "192.168.1.1" ];

  # Фаервол включён (modules/nixos/server.nix), 22 уже открыт. Наружу с этой
  # машины больше ничего торчать не должно: к консолям виртуалок ходят через
  # SSH-туннель (см. docs/install-forge.md), а не открытым VNC/SPICE-портом.
  #
  # Виртуальные мосты гипервизоров — доверенные интерфейсы. Без этого ВМ в
  # NAT-сети libvirt не получают адрес: dnsmasq на virbr0 слушает 53/67, а
  # INPUT-цепочка NixOS их режет (libvirt ставит свои правила в filter, но
  # после политики NixOS). vboxnet0 — host-only сеть VirtualBox, vmnet1/
  # vmnet8 — host-only и NAT у VMware; появляются только когда соответствующий
  # гипервизор поднят, перечисление отсутствующего интерфейса безвредно.
  # docker0 здесь по той же причине, что virbr0: docker ставит свои правила в
  # FORWARD/DOCKER, но запросы контейнеров к самому хосту (DNS на 53, порты
  # сервисов) приходят в INPUT и режутся политикой NixOS.
  networking.firewall.trustedInterfaces = [ "virbr0" "vboxnet0" "vmnet1" "vmnet8" "docker0" ];

  # mDNS (avahi) здесь сознательно НЕ включается, хотя у машины нет
  # видеовыхода и выданный ей DHCP-адрес посмотреть глазами негде. Имена в
  # локальной сети раздаёт роутер (OpenWrt): dnsmasq заводит на каждую аренду
  # запись в зоне `lan`, то есть этот хост разрешается как `forge.lan` сам,
  # без участия хоста. А поскольку DHCP выдаёт клиентам ещё и `domain-name
  # lan`, в их resolv.conf попадает `search lan` — и короткого `forge`
  # достаточно, резолвер сам допишет домен. Второй механизм обнаружения
  # (avahi + nssmdns4 на клиентах + открытый UDP 5353) дал бы ровно тот же
  # результат другим путём, поэтому его нет: `networking.hostName` ниже —
  # единственное, что этому хосту нужно, чтобы отвечать на своё имя.

  ###########################################################################
  # Доступ
  ###########################################################################

  # Тот же клиентский ключ ноутбука, которым открывается server (ssh/server,
  # приватная половина гитигнорится). Второй ключ заводить незачем: машина
  # временная, а доверие и так сводится к одному ноутбуку.
  #
  # Личность САМОЙ машины — это другой ключ: ssh/forge_host_ed25519_key,
  # сгенерирован заранее (иначе sops нечем расшифровывать при установке) и
  # кладётся в /etc/ssh/ руками, см. docs/install-forge.md.
  users.users.nix.openssh.authorizedKeys.keys = [ laptopKey ];

  # Агентские задачи длинные и переживают выход из SSH: без linger systemd
  # убивает пользовательский менеджер (а с ним и всё, что агент запустил через
  # systemd-run --user) в момент закрытия последней сессии. Обратная сторона —
  # устаревающие home.sessionVariables, см. docs/repo-notes.md.
  users.users.nix.linger = true;

  # isNormalUser/shell/doas — modules/nixos/common.nix; здесь только группы.
  users.users.nix.extraGroups = [
    "wheel"
    "libvirtd"    # virsh/virt-install без root
    "kvm"         # /dev/kvm
    "vboxusers"   # иначе VBoxManage не видит ВМ пользователя
    # docker: членство в этой группе равносильно root на хосте (сокет демона
    # позволяет запустить контейнер с --privileged и смонтировать /). Здесь
    # это осознанно: у nix и так есть wheel/doas, а гонять каждый агентский
    # `docker run` через doas — лишний трение без выигрыша в безопасности.
    "docker"
    "systemd-journal"
    # Группы `disk` здесь сознательно нет: она даёт сырой доступ ко всем
    # блочным устройствам (фактически права root), а guestfish/qemu-img
    # работают с файлами образов, а не с дисками хоста.
  ];

  ###########################################################################
  # Виртуализация: libvirt/KVM + VirtualBox + VMware Workstation
  ###########################################################################
  #
  # ГЛАВНОЕ, что надо знать про три гипервизора на одной машине: аппаратную
  # виртуализацию (VMX у Intel, SVM у AMD) ядро отдаёт кому-то ОДНОМУ. С ядра
  # 6.12 KVM по умолчанию входит в «VMX root mode» СРАЗУ при загрузке модуля
  # kvm_intel/kvm_amd и не выходит из него до выгрузки модуля — а и VirtualBox
  # (свой гипервизор в vboxdrv), и VMware (vmmon) требуют VMX себе. Отсюда
  # классические ошибки: VERR_VMX_IN_VMX_ROOT_MODE у VirtualBox и
  # «could not enter VMX root / VT disabled» у VMware, причём на пустой
  # машине, где ни одной ВМ не запущено.
  #
  # Лечится параметром ядра ниже: kvm.enable_virt_at_load=0 возвращает старое
  # поведение — KVM берёт VMX только на время работы ВМ и отдаёт обратно,
  # когда последняя гостевая машина остановлена. То есть все три гипервизора
  # уживаются, но НЕ ОДНОВРЕМЕННО: пока крутится ВМ в libvirt, VirtualBox и
  # VMware не стартуют, и наоборот. Для агентов это означает простое правило —
  # один гипервизор за раз; проверить, кто чем занят, можно командой `hv`
  # (ставится ниже).
  #
  # Оба `options` безопасны одновременно: modprobe применяет настройки того
  # модуля, который реально загрузился (на Intel kvm_amd не существует и
  # строка просто игнорируется). nested=1 нужен, чтобы внутри ВМ работал ещё
  # один гипервизор — типичная агентская задача «подними стенд внутри стенда».
  # console= : последний в списке становится основным. tty0 оставлен первым,
  # чтобы вывод шёл и на экран, если видеовыход когда-нибудь появится, а
  # ttyS0 — чтобы загрузку можно было читать через USB-UART на COM-порт. На
  # машине без видео это единственная диагностика; если COM-порта на плате
  # нет, ядро просто не зарегистрирует консоль, вреда никакого.
  boot.kernelParams = [
    "kvm.enable_virt_at_load=0"
    "console=tty0"
    "console=ttyS0,115200n8"
  ];
  boot.extraModprobeConfig = ''
    options kvm_intel nested=1
    options kvm_amd nested=1
  '';

  # libvirt/QEMU-KVM — основной гипервизор для агентов: единственный из трёх,
  # который полноценно управляется из командной строки и по API (virsh,
  # virt-install, libvirt-python), то есть его может водить агент без GUI.
  virtualisation.libvirtd = {
    enable = true;
    # ВМ не поднимаются сами при загрузке: что запускать — решает агент, а не
    # хост. Выключение — через suspend, чтобы долгий стенд не терялся при
    # перезагрузке хоста.
    onBoot = "ignore";
    onShutdown = "suspend";
    qemu = {
      # UEFI-прошивки (OVMF) для гостей здесь НЕ настраиваются: подопция
      # virtualisation.libvirtd.qemu.ovmf в nixos-26.05 удалена — все образы
      # OVMF, идущие с QEMU, теперь подключаются сами (попытка задать её даёт
      # жёсткий assertion при сборке). То есть гостя с UEFI/Secure Boot можно
      # ставить без дополнительных строк.
      #
      # Программный TPM 2.0 — требование Windows 11.
      swtpm.enable = true;
      # runAsRoot = false (в отличие от ноутбука): qemu работает под учёткой
      # qemu-libvirtd. Для автоматизации это важнее удобства — ВМ, которую
      # поднял агент по своей инструкции, не должна иметь прав root на хосте.
      # Цена: образы должны лежать там, где эта учётка их читает, то есть в
      # /var/lib/libvirt/images (ACL ставит libvirt сам), а не в /home/nix.
      runAsRoot = false;
      vhostUserPackages = [ pkgs.virtiofsd ];
    };
  };

  # Сеть `default` (мост virbr0, NAT 192.168.122.0/24, свой dnsmasq с DHCP) —
  # то, к чему по умолчанию цепляются все гайды и `virt-install --network
  # default`. В NixOS её нет: пакет libvirt в nixpkgs идёт БЕЗ штатного
  # default.xml (каталог $out/var/lib/libvirt/network пустой), а модуль
  # libvirtd ничего не определяет. Без этого юнита первая же попытка поднять
  # ВМ упирается в «Network not found: no network with matching name
  # 'default'».
  #
  # Сеть определяется один раз и живёт дальше в /var/lib/libvirt (состояние
  # переживает rebuild), поэтому define — только если её ещё нет.
  systemd.services.libvirt-default-net = {
    description = "Определение и автозапуск сети default в libvirt";
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script =
      let
        netXml = pkgs.writeText "libvirt-default-net.xml" ''
          <network>
            <name>default</name>
            <forward mode='nat'/>
            <bridge name='virbr0' stp='on' delay='0'/>
            <ip address='192.168.122.1' netmask='255.255.255.0'>
              <dhcp>
                <range start='192.168.122.2' end='192.168.122.254'/>
              </dhcp>
            </ip>
          </network>
        '';
      in
      ''
        virsh=${pkgs.libvirt}/bin/virsh
        $virsh net-info default >/dev/null 2>&1 || $virsh net-define ${netXml}
        $virsh net-autostart default
        # Уже запущенная сеть — не ошибка этого юнита.
        $virsh net-start default || true
      '';
  };

  # VirtualBox — под него написаны .ova-образы курсов и большинство готовых
  # «стендов» из интернета.
  #
  # Extension Pack включён с 2026-10-30: без него в гостя нельзя пробросить
  # USB (только USB 1.1) и не работает VRDP, а проброс флешки — прямое
  # требование контрольного задания ПАСЗИ. Несвободный (PUEL), разрешён
  # `nixpkgs.config.allowUnfree = true` в modules/nixos/common.nix.
  #
  # Как он устроен в nixpkgs — это не «пакет сверху, ставится активацией»:
  # опция подменяет сборку virtualbox на variant с extpack, где
  # VBoxExtPackHelperApp install --tarball выполняется ещё на этапе сборки и
  # укладывает его в $out/share/ExtensionPacks (см.
  # pkgs/applications/virtualization/virtualbox/default.nix). Отсюда три
  # следствия, которые иначе всплывут сюрпризом:
  #   - такая сборка не берётся из бинарного кеша (несвободная), то есть
  #     включение = полная локальная сборка VirtualBox и, следом, модулей
  #     ядра для него;
  #   - версия extpack привязана к версии VirtualBox (в nixpkgs обе 7.2.22,
  #     что совпало с уже стоявшим VBoxManage 7.2.22r175245); при обновлении
  #     VirtualBox они едут парой, рассинхронизировать их нельзя;
  #   - он несовместим с enableKvm (см. ниже) — эти две сборки исключают
  #     друг друга.
  #
  # На server Extension Pack не включён; если USB-проброс понадобится там,
  # включать так же и помнить про цену сборки.
  #
  # Альтернатива, если конфликт за VMX всё-таки будет мешать:
  # virtualisation.virtualbox.host.enableKvm = true — сборка VirtualBox с
  # KVM-бэкендом (форк Cyberus), которая вместо своего гипервизора использует
  # KVM и потому с ним не воюет. Не включено по умолчанию, потому что это
  # другая, менее обкатанная сборка, несовместимая с Extension Pack.
  virtualisation.virtualbox.host.enable = true;
  virtualisation.virtualbox.host.enableExtensionPack = true;
  # GUI-сборка на этом хосте бессмысленна: видеовыхода у платы нет вовсе
  # (см. раздел про BIOS Setup), а ВМ ведутся через VBoxManage/VBoxHeadless.
  # Плюс Qt6 в зависимостях сборки — а сборка VirtualBox локальная всё равно
  # (несвободный extpack-вариант из бинарного кеша не берётся).
  virtualisation.virtualbox.host.headless = true;

  # VMware Workstation — ради готового стенда «Континент» и прочих .vmx,
  # которые уже есть у пользователя (раньше они крутились на этой же машине
  # под Windows, см. ~/Stuff/server/CLAUDE.md).
  #
  # Модуль собирает модули ядра vmmon/vmnet из исходников пакета и поднимает
  # юниты vmware-networks (vmnet1/vmnet8) и vmware-usbarbitrator. Сама
  # Workstation — GUI-приложение, и графической сессии здесь нет; headless
  # управление — через vmrun, который идёт в том же пакете:
  #   vmrun -T ws start /path/to/vm.vmx nogui
  #   vmrun -T ws list
  #   vmrun -T ws stop /path/to/vm.vmx soft
  # GUI при необходимости пробрасывается по `ssh -X` (X11Forwarding на этом
  # хосте не включён по умолчанию — добавить в services.openssh.settings).
  #
  # РИСК, который стоит проверять при каждом обновлении flake.lock: vmmon/
  # vmnet — внешние модули под конкретное ядро, и апстрим VMware регулярно
  # отстаёт от свежих ядер. Если сборка хоста упадёт на vmware-workstation —
  # это оно; обойти можно, прибив ядро к LTS (boot.kernelPackages =
  # pkgs.linuxPackages_6_12) или временно выключив эту строку.
  virtualisation.vmware.host.enable = true;

  # Docker — третий способ «изолированной среды» на этом хосте, и самый
  # дешёвый: контейнеру не нужна аппаратная виртуализация, поэтому он
  # работает ОДНОВРЕМЕННО с любым из трёх гипервизоров и не участвует в драке
  # за VMX. Для агентских задач, где нужна не целая ОС, а чистое окружение с
  # нужными пакетами, это правильный инструмент.
  virtualisation.docker.enable = true;
  # Демон не поднимается при загрузке: docker.socket стартует его при первом
  # обращении. Иначе docker.service тянет network-online.target и добавляет
  # секунды к каждой загрузке просто на всякий случай (та же правка, что на
  # ноутбуке).
  virtualisation.docker.enableOnBoot = false;
  # Автоудаление мусора раз в неделю: на машине, где агент собирает образы
  # пачками, /var/lib/docker иначе растёт без потолка.
  virtualisation.docker.autoPrune = {
    enable = true;
    dates = "weekly";
    flags = [ "--all" "--filter" "until=168h" ];
  };

  # KSM (Kernel Samepage Merging) — ядро находит одинаковые страницы памяти в
  # разных ВМ и держит одну копию. На машине, где агент поднимает десяток
  # однотипных гостей из одного образа, это экономит гигабайты RAM почти
  # бесплатно по CPU. Для одиночных разнородных ВМ смысла мало — тогда просто
  # лишний демон.
  hardware.ksm.enable = true;

  # Маленькая утилита-подсказка: кто сейчас держит аппаратную виртуализацию.
  # Нужна ровно из-за монопольности VMX/SVM, описанной выше: ошибка
  # VirtualBox/VMware «не могу войти в VMX root» не говорит, КТО виноват.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "hv" ''
      set -eu
      case "''${1:-status}" in
        status)
          echo "== загруженные модули гипервизоров =="
          lsmod | grep -E '^(kvm_intel|kvm_amd|kvm|vboxdrv|vmmon)\b' || echo "  (ни одного)"
          echo
          echo "== работающие ВМ =="
          echo "-- libvirt:"
          ${pkgs.libvirt}/bin/virsh list 2>/dev/null | sed 's/^/   /' || echo "   (libvirtd недоступен)"
          echo "-- VirtualBox:"
          VBoxManage list runningvms 2>/dev/null | sed 's/^/   /' || echo "   (нет)"
          echo "-- VMware:"
          vmrun -T ws list 2>/dev/null | sed 's/^/   /' || echo "   (vmrun недоступен)"
          ;;
        free)
          # Аварийный вариант: отдать VMX принудительно. С
          # kvm.enable_virt_at_load=0 это нужно только если какая-то ВМ
          # зависла и не отпускает модуль.
          echo "выгружаю модули KVM (нужен doas)"
          doas modprobe -r kvm_intel 2>/dev/null || true
          doas modprobe -r kvm_amd 2>/dev/null || true
          doas modprobe -r kvm 2>/dev/null || true
          lsmod | grep -E '^kvm' || echo "VMX свободен"
          ;;
        *)
          echo "usage: hv [status|free]"
          exit 1
          ;;
      esac
    '')

    # Инструменты автоматизации ВМ (libvirt-ветка). Всё — командная строка:
    # именно этим агент и будет пользоваться.
    pkgs.virt-manager   # сам GUI не нужен, но в этом же пакете лежат virt-install/virt-clone/virt-xml
    pkgs.cloud-utils    # cloud-localds: seed-образ cloud-init для автоустановки гостей
    pkgs.cdrkit         # genisoimage — то же самое вручную, плюс любые ISO
    pkgs.qemu-utils     # qemu-img: convert .vmdk/.vdi/.qcow2, create, snapshot
    pkgs.docker-compose # многоконтейнерные стенды одним файлом

    # Обслуживание шифрования корня. systemd-cryptenroll лежит в самом
    # systemd и уже в PATH, а эти два — нет:
    pkgs.cryptsetup     # luksDump: посмотреть слоты и токены заголовка LUKS2
    pkgs.tpm2-tools     # tpm2_pcrread/tpm2_getcap: проверить, что fTPM виден и какие PCR

    # guestfs-tools (virt-customize/virt-sysprep/guestfish — правка образа ВМ
    # без её запуска) сознательно НЕ включены: пакет тянет
    # libguestfs-appliance, а это 4.1 ГБ в замыкании, то есть примерно треть
    # размера установочного образа (hosts/installer-forge/default.nix вшивает
    # систему целиком в ISO). Когда понадобится — либо раскомментировать
    # строку и пересобрать уже на машине с сетью, либо разово:
    #   nix shell nixpkgs#guestfs-tools
    # pkgs.guestfs-tools
  ];

  ###########################################################################
  # Агентские инструменты: чего не хватает в nixpkgs-пакетах
  ###########################################################################

  # nix-ld даёт стандартный путь динамического загрузчика
  # (/lib64/ld-linux-x86-64.so.2), которого на NixOS нет. Без него падает всё,
  # что агенты притаскивают готовыми бинарниками: npm-пакеты с нативными
  # модулями (omniroute, playwright-браузеры), pip-колёса, расширения VS Code.
  # Список библиотек — тот же, что на ноутбуке и server.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    zlib zstd stdenv.cc.cc curl openssl attr libssh bzip2 libxml2 acl libsodium util-linux xz systemd
  ];

  # Оболочка пользователя — fish (modules/nixos/common.nix), включение на
  # уровне системы — в modules/nixos/server.nix.

  ###########################################################################
  # Выход в интернет для агентов (туннель)
  ###########################################################################

  # Сами модули и их настройки — в imports в начале файла, под флагом
  # secretsReady. Коротко, что получается в итоге: mihomo на 127.0.0.1:6080
  # собирает узлы из подписок (URL — в secrets/common.yaml), url-test'ит их и
  # выбирает живой; `claude` и pi ходят через 6080 (см. hosts/forge/home.nix).
  # Локального xray@ здесь нет — xrayUpstream = false.
  #
  # Почему свой экземпляр, а не проброс чужого: mihomo на ноутбуке и на server
  # слушает только 127.0.0.1, и выставить его в локальную сеть ради временной
  # машины — значит открыть в домашней сети анонимный прокси.

  ###########################################################################
  # Второй диск: HDD 1 ТБ с материалом стендов (NTFS)
  ###########################################################################

  # Toshiba HDWD110 (931 ГБ) — тот самый диск, что сейчас стоит в основном
  # сервере как /dev/sdb и смонтирован там в /mnt. На нём ~283 ГБ в одном
  # NTFS-разделе: Continent_4_stand, continent376, PASZI, образы win10,
  # webui_forge_*. Если его переставляют в forge, он должен подключаться
  # ДАННЫМИ, а не как цель установки: в disko (hosts/forge/disk-config.nix) он
  # НЕ описан, потому что disko затирает всё, что там перечислено.
  #
  # Путь by-id не зависит от машины (модель + серийник), так что строка верна
  # и после переезда. Раскомментировать, когда диск окажется в forge:
  #
  # boot.supportedFilesystems = [ "ntfs" ];
  # fileSystems."/mnt/stands" = {
  #   device = "/dev/disk/by-id/ata-TOSHIBA_HDWD110_911J5U1FS-part1";
  #   fsType = "ntfs3";
  #   # nofail обязателен: emergency mode на этом хосте выключен
  #   # (modules/nixos/server.nix), и отвалившийся диск иначе просто не даст
  #   # машине подняться в сеть. uid/gid — чтобы файлы были доступны nix:
  #   # у NTFS нет unix-прав, владельца задаёт монтирование.
  #   options = [ "nofail" "x-systemd.device-timeout=10s" "uid=1000" "gid=100" "windows_names" ];
  # };
  #
  # ntfs3 (драйвер в ядре), а не ntfs-3g через FUSE: на гигабайтных .vmdk и
  # .ova разница в скорости кратная. Писать в NTFS из Linux можно, но если на
  # этом разделе потом снова будет работать Windows — размонтировать аккуратно
  # (`umount`, не выдёргивать питание), иначе раздел останется «грязным».

  ###########################################################################
  # Сборка
  ###########################################################################

  # max-jobs/cores сознательно не заданы: сколько ядер у этой платформы —
  # выяснится на месте. Дефолт (max-jobs = auto, cores = 0) занимает все ядра
  # одной сборкой; если машина будет одновременно крутить ВМ, стоит оставить
  # им запас, по образцу hosts/server/default.nix:
  #   nix.settings.max-jobs = 4;
  #   nix.settings.cores = 2;

  # Машина временная, а /nix/store у неё свой: чистка чаще, чем недельная из
  # modules/nixos/common.nix, плюс порог по свободному месту, чтобы образы ВМ
  # и gc не воевали за диск.
  nix.settings.min-free = 10 * 1024 * 1024 * 1024;
  nix.settings.max-free = 40 * 1024 * 1024 * 1024;

  # Соответствует версии nixpkgs, с которой хост СТАВИТСЯ, и дальше не
  # меняется (это не «версия системы», а точка совместимости для состояния на
  # диске: формат БД сервисов и т.п.).
  system.stateVersion = "26.05";
}
