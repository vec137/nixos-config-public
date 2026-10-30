# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, inputs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x390
      # mihomo на 127.0.0.1:6080 — сам выбирает живой туннель из
      # Throne (2080), xray (3080) и подписок; туда же смотрят claude,
      # nix-daemon, Discord и proxychains. Общий модуль с сервером, плюс
      # ноутбучная часть про cachix.
      ../../modules/nixos/mihomo.nix
      ../../modules/nixos/mihomo-subscriptions.nix
      ../../modules/nixos/mihomo-cachix.nix
      # xray как системный сервис xray@ (конфиги из sops), общий с сервером.
      ../../modules/nixos/xray-client.nix
      # NFS + CIFS share of /srv/iso, for feeding ISOs to the server's BMC
      # virtual media. Remove this import when the server work is done.
      # ../../modules/nixos/iso-share.nix
    ];

  # Shared nix.settings (substituters/experimental-features), nixpkgs.config
  # (unfree/insecure policy), locale/console, doas, and the base user
  # account live in modules/nixos/common.nix — shared with any future host.
  nix = {
  	  distributedBuilds = true;
  	  extraOptions = ''
  	  	builders-use-substitutes = true
  	  '';
  	  buildMachines = [
  	  	{
  	  		# EPYC 7402 (48 threads) / 62G RAM headless box, see hosts/server/.
  	  		# maxJobs left below the full thread count so a build doesn't
  	  		# starve out llama-server/hermes-agent/SearXNG already running
  	  		# there. speedFactor above wsl's on the assumption a server-class
  	  		# EPYC beats whatever wsl's host is — revisit if that's wrong.
  	  		hostName = "server";
  	  		system = "x86_64-linux";
  	  		maxJobs = 32;
  	  		speedFactor = 4;
			supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
  	  	}
  	  ];
  	  settings = {
  		max-jobs = 4;
  		cores = 2;
  		connect-timeout = 5;
  		# Подпись сборок этого ноутбука (приватная часть — secrets/
  		# laptop.yaml, публичная — vpn/settings.nix laptopSigningKey, VPS
  		# доверяет ей наравне с serverSigningKey). Нужна, т.к.
  		# distributedBuilds выше не гарантирует, что ВСЁ уйдёт на server:
  		# мелкие деривации демон иногда собирает локально, даже когда
  		# server доступен (так и всплыло — deploy .#ru-edge упал на
  		# "lacks a signature by a trusted key" для unit-script'а).
  		secret-key-files = [ config.sops.secrets.nix-signing-key.path ];
  	  };
  };

  boot = {
  	  kernelPackages = pkgs.linuxKernel.packages.linux_zen;
  	  kernelParams = [ "i915.enable_guc=3" ];
  	  kernelModules = [ "thinkpad_acpi" ];
  	  extraModprobeConfig = ''
  	  	options kvm_intel nested=1
  	  	options thinkpad_acpi fan_control=1
  	  '';
  	  loader = {
  	  	  systemd-boot.enable = false;
  	  	  grub.enable = true;
  	  	  grub.efiSupport = true;
  	  	  grub.efiInstallAsRemovable = true;
  	  	  grub.enableCryptodisk = true;
  	  	  grub.devices = [ "nodev" ];
  	  	  grub.useOSProber = false;
  	  };
  };

  # Compressed RAM-backed swap as the fast/preferred tier (LZ4/zstd instead
  # of paging out to the LUKS-encrypted disk swap below). Sized modestly
  # (25% of 15GiB ≈ 4GiB ceiling, not a static reservation — it only uses
  # real RAM proportional to what's actually stored+compressed in it)
  # because this machine sometimes runs QEMU/KVM VMs with several GiB of
  # their own RAM; a bigger zram budget would compete with that instead of
  # just absorbing normal host-side memory pressure. Explicit high priority
  # so the kernel prefers it over the disk swap partition (which keeps its
  # default/unset priority, i.e. lower) — the disk swap stays as a fallback
  # for pressure beyond what zram's ceiling can absorb.
  zramSwap = {
    enable = true;
    memoryPercent = 25;
    priority = 100;
  };
  # Default swappiness (60) assumes swap is slow disk, so the kernel avoids
  # it until fairly late. With zram as the preferred tier, swapping is cheap
  # enough to lean into more readily — bumped moderately, not aggressively,
  # since raising it too far would also make the kernel more willing to
  # reclaim anonymous memory in general, including a running VM's guest RAM.
  boot.kernel.sysctl."vm.swappiness" = 100;

  networking.hostName = "laptop"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "Europe/Moscow";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable the X11 windowing system.
  # services.xserver.enable = true;


  

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.printing.cups-pdf.enable = true;

  # Enable sound.
  # hardware.pulseaudio.enable = true;
  # OR
  hardware.keyboard.qmk.enable = true;
  hardware.bluetooth.enable = true;
  hardware.sensor.iio.enable = true;
  # hardware.sensor.hddtemp.enable = true;
  hardware.graphics = {
  	enable = true;
  	extraPackages = with pkgs; [ intel-media-driver intel-ocl intel-vaapi-driver ];
  };
  hardware.enableRedistributableFirmware = true;
  services.gvfs.enable = true;
  services.blueman.enable = true;
  services.tlp.enable = lib.mkForce false;
  services.tuned.enable = true;
  services.upower.enable = true;
  services.thinkfan = {
    enable = true;
    smartSupport = true;
    sensors = [
      {
        type = "hwmon";
        query = "/sys/devices/platform/coretemp.0/hwmon/hwmon1/temp1_input";
      }
    ];
    fans = [
      {
        type = "tpacpi";
        query = "/proc/acpi/ibm/fan";
      }
    ];
    levels = [
      [ 0 0 55 ]
      [ 1 50 62 ]
      [ 2 57 68 ]
      [ 3 63 74 ]
      [ 5 70 82 ]
      [ 7 78 88 ]
      [ 127 84 32767 ]
    ];
  };
  services.thermald.enable = true;
  # services.throttled.enable comes from nixos-hardware's lenovo-thinkpad-x390
  # module. Its default /etc/throttled.conf allows PL1=PL2=44W on AC with
  # Trip_Temp_C=95 — a generic "unlock everything" template from the
  # upstream package, not tuned to this chassis. This CPU (i7-8665U) has a
  # 15W nominal TDP / 25W configurable cTDP-up ceiling per Intel's spec, so
  # 44W sustained was routinely pushing it to 95°C+ under load (confirmed
  # via thinkfan's log: fan already at max level 127 at that point, so
  # there was no more cooling headroom left to give). Lower, chassis-
  # appropriate limits below — trades some sustained heavy-load performance
  # for meaningfully less heat/fan noise. These are a reasoned starting
  # point, not a precisely benchmarked optimum; adjust and rebuild to
  # taste.
  services.throttled.extraConfig = ''
    [GENERAL]
    Enabled: True
    Sysfs_Power_Path: /sys/class/power_supply/AC*/online
    Autoreload: True

    [BATTERY]
    Update_Rate_s: 30
    PL1_Tdp_W: 15
    PL1_Duration_s: 28
    PL2_Tdp_W: 25
    PL2_Duration_S: 0.002
    Trip_Temp_C: 80
    cTDP: 0
    Disable_BDPROCHOT: False

    [AC]
    Update_Rate_s: 5
    PL1_Tdp_W: 20
    PL1_Duration_s: 28
    PL2_Tdp_W: 35
    PL2_Duration_S: 0.002
    Trip_Temp_C: 90
    cTDP: 0
    Disable_BDPROCHOT: False

    [UNDERVOLT.BATTERY]
    CORE: 0
    GPU: 0
    CACHE: 0
    UNCORE: 0
    ANALOGIO: 0

    [UNDERVOLT.AC]
    CORE: 0
    GPU: 0
    CACHE: 0
    UNCORE: 0
    ANALOGIO: 0
  '';
  services.logind.settings.Login.HandleLidSwitch = "suspend";
  services.logind.settings.Login.HandleLidSwitchDocked = "suspend";
  services.pipewire = {
    enable = true;
    systemWide = false;
    pulse.enable = true;
    jack.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    wireplumber = {
    	enable = true;
    };
  };
  # Stream kernel log messages over UDP to the "wsl" build machine
  # (192.168.1.205, same LAN segment — see programs.ssh.extraConfig below for
  # where that IP comes from). This exists to catch the two full hard
  # lockups we've had during `rebuild-switch` (screen/input/VT-switch/audio
  # all frozen, journald never got a chance to flush anything to disk): the
  # netconsole driver transmits each printk() line directly via the NIC's
  # own raw TX path, independent of the block layer/journald/disk — so it
  # keeps working even through a lockup severe enough to freeze everything
  # else, and gives us a real backtrace to diagnose instead of silence.
  #
  # Loaded as a oneshot service (not boot.kernelModules) specifically so it
  # attaches after the wired NIC actually has a link and an address —
  # netconsole registers its listener once at module-load time and won't
  # retry, so loading it too early (before network-online.target) would
  # silently leave it non-functional for the rest of the boot.
  #
  # Target MAC is given explicitly (found via `ip neigh`) so netconsole
  # addresses the WSL box directly at L2 and skips ARP entirely — useful
  # since ARP itself can't be relied on to work during the kind of lockup
  # this is meant to survive.
  #
  # To listen on the WSL side: `socat -u UDP-LISTEN:6666,fork -
  # /var/log/netconsole.log` (or `nc -ul 6666 | tee -a netconsole.log`).
  systemd.services.netconsole = {
    description = "netconsole: stream kernel log to wsl over UDP";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.kmod}/bin/modprobe netconsole netconsole=6665@192.168.1.166/enp0s31f6,6666@192.168.1.205/10:ff:e0:62:a8:1e";
      ExecStop = "${pkgs.kmod}/bin/modprobe -r netconsole";
    };
  };
  # Suspend (S3) tears down and recreates the NIC, which makes netconsole
  # unregister itself ("network logging stopped ... as it unregistered") --
  # confirmed happening on this laptop's normal sleep cycles, not just
  # during a lockup. The systemd.services.netconsole unit above only runs
  # once at boot, so without this it silently stays dead until the next
  # reboot. systemd-sleep calls every executable under here with
  # `pre|post <suspend|...>` around each sleep cycle -- this is the
  # standard hook point for exactly this (there's no target that fires
  # specifically *after* resume to hang a normal service off of).
  environment.etc."systemd/system-sleep/netconsole-rearm" = {
    mode = "0755";
    text = ''
      #!${pkgs.runtimeShell}
      if [ "$1" = post ]; then
        ${pkgs.kmod}/bin/modprobe -r netconsole 2>/dev/null
        ${pkgs.kmod}/bin/modprobe netconsole netconsole=6665@192.168.1.166/enp0s31f6,6666@192.168.1.205/10:ff:e0:62:a8:1e
      fi
    '';
  };
  # Silence the recurring "Cannot enable" kernel spam from usb2-port4 (an
  # empty internal WWAN M.2 slot's floating USB2 sideband — see the comment
  # on services.udev.extraRules below for how this was diagnosed). This is a
  # journald-side content filter (systemd ≥254's LogFilterPatterns=), not a
  # kernel-side fix — the kernel still logs it to dmesg/the ring buffer, this
  # just stops journald from persisting/showing it. The `~` prefix means
  # "deny": entries matching this regex are dropped, everything else passes
  # through unaffected.
  services.journald.extraConfig = ''
    LogFilterPatterns=~usb2-port4: Cannot enable
  '';
  # The journald filter above only stops the message from being stored/shown
  # by journald — it does nothing about the kernel printing it straight to
  # the active tty, which is a separate path (console_loglevel) that bypasses
  # journald entirely. Confirmed via `journalctl -k -o verbose` that this
  # line is emitted at PRIORITY=3 (KERN_ERR); the running console_loglevel
  # (first field of kernel.printk, default 4/KERN_WARNING here) prints
  # anything with a *lower* priority number, i.e. anything at or above
  # err-severity, straight to the console — that's what's clobbering the
  # shell prompt. Lowering console_loglevel to 3 stops err-level messages
  # (and, as a side effect, any other future err-level kernel message) from
  # hitting the console, while leaving them fully intact in dmesg/journald
  # (governed by the 2nd/3rd/4th printk fields, untouched here) — so nothing
  # is lost, it's just not interrupting the terminal anymore. Applied via
  # boot.kernel.sysctl (not a `loglevel=` kernel param) so it takes effect
  # on the next `nixos-rebuild switch` without needing a reboot.
  boot.kernel.sysctl."kernel.printk" = "3 4 1 7";
  # Decrypted to /run/secrets/obsidian-api-key at activation (see
  # modules/nixos/common.nix for the sops-nix wiring). owner = "nix" since
  # this is read by a home-manager activation script (modules/home/
  # obsidian-mcp.nix) running as that user, not by a root-owned service.
  # sopsFile переопределяет defaultSopsFile из common.nix: это секрет
  # графической сессии (Obsidian живёт только здесь), и серверу он
  # недоступен — его ключа нет в получателях secrets/laptop.yaml.
  sops.secrets.obsidian-api-key = {
    owner = "nix";
    sopsFile = ../../secrets/laptop.yaml;
  };
  # Decrypted to /run/secrets/ha-token, injected into noctalia's live
  # settings.toml by modules/home/noctalia.nix's activation script (that
  # plugin only ever reads the token from settings.toml, no env var support
  # -- see that file for how the real value is kept out of the git-tracked
  # mirror).
  # Тоже только для этого хоста: виджет noctalia — часть графической
  # оболочки, на headless-сервере его нет.
  sops.secrets.ha-token = {
    owner = "nix";
    sopsFile = ../../secrets/laptop.yaml;
  };
  # Decrypted to /run/secrets/omniroute-api-key, injected into the
  # `claude mcp add` call for the omniroute MCP server (modules/home/
  # omniroute-mcp.nix) as OMNIROUTE_API_KEY -- same pattern as
  # obsidian-api-key above. owner = "nix" for the same reason: read by a
  # home-manager activation script running as that user.
  # Без sopsFile — берётся дефолтный secrets/common.yaml: MCP понадобится
  # и на сервере, когда туда переедет агентская часть пайплайна.
  sops.secrets.omniroute-api-key = {
    owner = "nix";
  };

  sops.secrets.openrouter-api-key.owner = "nix";

  # Приватная половина laptopSigningKey (vpn/settings.nix). owner по
  # умолчанию root/0400 — читает nix-daemon (nix.settings.secret-key-files
  # выше), не нужен home-manager/user-уровню.
  sops.secrets.nix-signing-key.sopsFile = ../../secrets/laptop.yaml;

  # Публичная часть host-ключа сервера, сгенерированного заранее (приватная
  # лежит в гитигнорном ssh/server_host_ed25519_key и при установке кладётся
  # в /mnt/etc/ssh/). Прописана декларативно, чтобы первое подключение не
  # упиралось в «The authenticity of host ... can't be established» с
  # предложением подтвердить отпечаток вслепую: именно в этот момент
  # подмену сервера заметить уже невозможно, а «да» на этот вопрос — самый
  # распространённый способ её пропустить.
  #
  # Это ПУБЛИЧНЫЙ ключ и подтверждает он личность СЕРВЕРА. Для входа он не
  # используется — за это отвечает отдельный ключ пользователя, см.
  # users.users.nix.openssh.authorizedKeys в hosts/server/default.nix.
  #
  # publicKey по схеме модуля — только тип и сам ключ, без имени хоста и
  # без комментария в конце (комментарий `nix@laptop` из .pub-файла убран:
  # ключ сгенерирован на ноутбуке, но принадлежит серверу).
  programs.ssh.knownHosts.server = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICWgm7q6RC13+XJhDLsDyBhjAGQdUWIfj6ZJMmbWG08u";
    # Имя `server` подставляется автоматически; сюда — адрес, по которому
    # к нему реально ходят. ЗАПОЛНИТЬ после установки, когда станет известен
    # адрес (машина та же, что сейчас отдаёт WSL на 192.168.1.148, но после
    # переустановки DHCP может выдать другой).
    extraHostNames = [ "192.168.1.148" ];
  };
  # Временный второй сервер (hosts/forge). Ключ сгенерирован заранее на
  # ноутбуке — ssh/forge_host_ed25519_key, при установке кладётся в /etc/ssh
  # (docs/install-forge.md), поэтому его публичная половина известна ДО
  # первого входа: подключение не будет спрашивать «unknown host».
  programs.ssh.knownHosts.forge = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIcv2Sb2c7r7yUBOXtHjZShMKPlNc2WwJ30is9XCktfz";
    # extraHostNames здесь не нужен: имя атрибута (`forge`) модуль сам
    # ставит первым полем в /etc/ssh/ssh_known_hosts, а ходят на этот хост
    # ровно под коротким именем — `hostname = "forge"` в matchBlocks
    # (modules/home/misc.nix). IP не вписан намеренно: он от DHCP, а имя в
    # зоне `lan` роутер отдаёт сам.
  };
  services.udev.packages = [ pkgs.vial ];
  # Disable faulty internal USB port (usb2-port4 / 2-4) to prevent continuous
  # reset loops. This alone is sufficient — udev rules fire whenever the
  # device shows up, so the systemd.tmpfiles.rules version that used to sit
  # here (targeting the same sysfs path once at boot) was a redundant
  # duplicate, and a stale one at that: the port doesn't even exist under
  # this exact path every boot (USB controller enumeration order varies).
  # services.udev.extraRules = ''
  #   SUBSYSTEM=="usb_port", KERNEL=="usb2-port4", ATTR{disable}="1"
  #   SUBSYSTEM=="usb", KERNEL=="2-4", ATTR{authorized}="0"
  # '';
  services.iptsd.enable = true;

  # xray@ (modules/nixos/xray-client.nix): вариант по умолчанию при загрузке.
  # Переключение на лету и про «мёртвый» туннель — в комментарии модуля.
  # Выключен совсем: ноутбук ходит через mihomo и подписку ru-edge
  # (mihomo-subscriptions.nix). Варианты и секреты xray остаются в репозитории
  # (на них сидит сервер); вернуть — enable = true и xrayUpstream = true ниже.
  services.xrayClient = {
    enable = false;
    default = "xhttp_cdn";
  };

  # Балансировщик mihomo (modules/nixos/mihomo.nix). Подписки общие с
  # сервером (modules/nixos/mihomo-subscriptions.nix). Throne пока остаётся
  # дополнительным апстримом; когда подписок хватит, убери его из
  # extraProxies.
  # wg-home: mihomo как WG-клиент до домашнего роутера — замена прежнего
  # networking.wg-quick.interfaces.home-lan (та же identity и тот же peer,
  # misc/wg.conf; wg-quick больше не запускается, поэтому один и тот же
  # ключ на двух сессиях одновременно не конфликтует). Приватный ключ —
  # только в sops; публичный ключ/порт/endpoint роутера не секрет (те же
  # значения, что были в wg.conf, и home.ip в modules/nixos/vpn/settings.nix).
  sops.secrets."wg-home-private-key".sopsFile = ../../secrets/laptop.yaml;
  # Отдельная identity для проксированного WG (см. узел "wg-home-proxy"):
  # у роутера на этот ключ завёрнут свой пир с адресом 10.0.0.12.
  sops.secrets."wg-home-proxy-private-key".sopsFile = ../../secrets/laptop.yaml;

  services.mihomoBalancer = {
    enable = true;
    xrayUpstream = false;
    # socks5/http для VM libvirt: 192.168.122.1:7891 (только на ноутбуке).
    libvirtSocks.enable = true;
    extraProxies = [
      { name = "throne"; type = "socks5"; server = "127.0.0.1"; port = 2080; udp = true; }
    ];
    # WG до дома — не интернет-выход, поэтому localProxies, а не
    # extraProxies: иначе он попадает в "proxy"/"auto" (см. upstreams в
    # modules/nixos/mihomo.nix), url-test пингует его каждые 30 с через
    # gstatic и может выбрать домашний роутер выходом для всего трафика.
    localProxies = [
      # Заглушка для группы "udp-up" — специально никуда не ведущий socks5
      # (на 127.0.0.1:9 ничего не слушает). Нужна, чтобы группа была непустой
      # с нулевой секунды: mihomo собирает члены группы только из провайдеров
      # (component/outboundgroup/groupbase.go, GetProxies), а узлы из "proxies"
      # заворачивает в compatible-provider, который готов сразу при загрузке
      # конфига и под filter не попадает. Пока удалённый provider "ruedge" не
      # загрузился, группа из одних "use" пуста, и тогда groupbase.go:220
      # подставляет плейсхолдер "COMPATIBLE" — а это adapter/outbound/direct.go
      # NewCompatible(), то есть обычный DIRECT. Измерено 21.10.2026: mihomo
      # перезапустился, через 22 мс health-check группы "lan" дёрнул
      # wg-home-proxy, провайдер ещё не отдал узлы, bind создался через
      # COMPATIBLE и остался прямым на всё время жизни процесса (цепочка в
      # /connections: ['COMPATIBLE','udp-up'], 4 мс и LAN-адрес в endpoint на
      # роутере вместо адреса ru-edge). Сам по себе bind не переподключится:
      # sing-wireguard делает это только по ошибке чтения/записи, а прямой путь
      # дома просто работает, а вне дома молча таймаутится — ошибки нет.
      # Заглушка ломает именно это: в худшем случае bind создаётся через неё,
      # получает connection refused (настоящая ошибка!), и следующий пакет
      # уходит уже через загруженный провайдер. В обычном режиме fallback
      # пропускает её как мёртвую.
      {
        name = "udp-up-stub";
        type = "socks5";
        server = "127.0.0.1";
        port = 9;
        udp = true;
      }
      {
        name = "wg-home";
        type = "wireguard";
        server = "203.0.113.30"; # home.ip, modules/nixos/vpn/settings.nix
        port = 51820;
        public-key = "1HMsqCsAX9BfngGsOfezL5nAeRqMnsU+s6BniRoyzkI=";
        private-key = config.sops.placeholder."wg-home-private-key";
        ip = "10.0.0.11/32"; # тот же адрес, что был у home-lan (misc/wg.conf: Address)
        allowed-ips = [ "192.168.1.0/24" ];
        persistent-keepalive = 25;
        udp = true;
      }
      # Тот же WG-пир, но набираемый не напрямую, а через прокси: dialer-proxy
      # — поле mihomo, которое заставляет исходящее соединение узла идти не в
      # сеть, а внутрь другого прокси/группы. Нужен там, где UDP до дома не
      # доходит вообще (провайдер/DPI рубит 51820, симметричный NAT):
      # handshake уезжает внутри туннеля ru-edge, снаружи виден только
      # обычный прокси-трафик.
      #
      # Апстрим — группа "udp-up" (ниже), а не "proxy": он обязан пропускать
      # UDP, а в "proxy" лежит ~220 узлов сторонних подписок, часть которых
      # UDP не пропускает. Измерено 21.10.2026 по логу mihomo:
      #   * активен "throne" (не запущен) → "connect to server: ...
      #     connection refused";
      #   * активен hysteria2-узел, чей сервер отвечает "Hysteria-UDP: false"
      #     → "connect to server: UDP disabled by server" (строка из
      #     sing-quic/hysteria2/client.go) — туннель мёртв, хотя для TCP этот
      #     узел живой и даже самый быстрый в "auto".
      # Сам механизм проверен и работает: через edge-xhttp WG-рукопожатие
      # доходит до роутера, HTTP к 192.168.1.1 отдаёт 200 за ~270 мс.
      {
        name = "wg-home-proxy";
        type = "wireguard";
        server = "203.0.113.30";
        port = 51820;
        public-key = "1HMsqCsAX9BfngGsOfezL5nAeRqMnsU+s6BniRoyzkI=";
        # Своя пара ключей и свой адрес — НЕ те же, что у wg-home. Иначе для
        # роутера это один пир, а у пира один endpoint: любой пакет от любого
        # из двух устройств его переписывает. Рукопожатие при этом проходит
        # (ответ WG уходит на адрес источника initiation), а ответные данные
        # роутер шлёт на последний записанный endpoint — и проксированная
        # сессия замирает на 15 с и перерукопожимается. Измерено 21.10.2026:
        # с общим ключом HTTP к 192.168.1.1 через прокси давал 200 лишь в 5
        # случаях из 8. Хватает одних keepalive'ов прямого узла (25 с),
        # health-check тут не при чём.
        private-key = config.sops.placeholder."wg-home-proxy-private-key";
        ip = "10.0.0.12/32";
        allowed-ips = [ "192.168.1.0/24" ];
        persistent-keepalive = 25;
        udp = true;
        dialer-proxy = "udp-up";
      }
    ];
    # "lan": DIRECT, пока отвечает домашний роутер (192.168.1.1 — он же DNS
    # в misc/wg.conf), иначе — wg-home. Проверка раз в 30 с (та же схема, что
    # у группы "dl" выше): после входа/выхода из дома переключение не
    # мгновенное, а в пределах интервала. Риск: в гостевой сети с тем же
    # диапазоном 192.168.1.0/24 роутер ответит и даст ложный DIRECT — для
    # редкой разовой сети это не страшно, трафик в эту подсеть просто не
    # дойдёт до домашней.
    extraGroups = [
      # Апстрим для wg-home-proxy: только наши узлы с ru-edge, у которых UDP
      # заведомо работает (edge-xhttp/edge-vision — vless, edge-ss —
      # shadowsocks-2022, у которого на входе портала network = "tcp,udp").
      # Узлы приходят из proxy-provider'а "ruedge"
      # (modules/nixos/mihomo-subscriptions.nix), поэтому use+filter, а не
      # proxies: в proxies группы можно перечислять только узлы из секции
      # proxies и другие группы, но не узлы подписок. По той же причине группа
      # вообще нужна — dialer-proxy нельзя указать прямо на узел подписки.
      #
      # Тип fallback, а не url-test: для дайлера WG важна не скорость, а
      # предсказуемость. fallback держит ПЕРВЫЙ живой узел, а порядок членов
      # при use+filter задаёт подписка (filter порядок не задаёт!) — sub-gen
      # отдаёт edge-xhttp раньше остальных, а UDP измерен именно у него.
      # url-test брал самый быстрый, и 21.10 это был edge-ss, чей UDP никто
      # не проверял. Если поменяется порядок узлов в sub-gen, поменяется и
      # выбор здесь — это компромисс за отсутствие ручного порядка.
      #
      # edge-hy2 сознательно не включён: Hysteria2 — ровно тот протокол, где
      # сервер объявляет поддержку UDP отдельным заголовком, и для нашего
      # входа это не проверено (пароль hy2 = UUID клиента, он в sops).
      # lazy = false: проверять и в простое, иначе первый запрос после паузы
      # может уйти в уже мёртвый узел, а для WG это сразу мёртвый туннель.
      {
        name = "udp-up";
        type = "fallback";
        # Заглушка первым членом — см. комментарий у "udp-up-stub" в
        # localProxies: без явного члена группа пуста до загрузки провайдера и
        # отдаёт DIRECT под именем COMPATIBLE.
        proxies = [ "udp-up-stub" ];
        use = [ "ruedge" ];
        filter = "^edge-(xhttp|vision|ss)$";
        url = "https://www.gstatic.com/generate_204";
        interval = 60;
        timeout = 5000;
        lazy = false;
      }
      {
        name = "lan";
        type = "fallback";
        # Порядок = приоритет: дома DIRECT, вне дома прямой WG, а если UDP до
        # дома не проходит вовсе — WG внутри прокси. Третий узел попал сюда
        # только после того, как у него появилась своя пара ключей: с общим
        # ключом два узла в одной health-check-группе ломали бы друг другу
        # сессию (см. комментарий у wg-home-proxy выше).
        proxies = [ "DIRECT" "wg-home" "wg-home-proxy" ];
        url = "http://192.168.1.1/";
        interval = 30;
        timeout = 5000;
      }
      # Select поверх fallback — та же схема, что у "proxy"/"auto": по
      # умолчанию автоматика ("lan"), но в панели можно закрепить DIRECT,
      # wg-home или wg-home-proxy руками (store-selected сохранит выбор
      # между рестартами).
      {
        name = "home";
        type = "select";
        proxies = [ "lan" "DIRECT" "wg-home" "wg-home-proxy" ];
      }
    ];
    # Имена *.lan (их раздаёт домашний роутер — он же DNS в misc/wg.conf)
    # спрашиваем у 192.168.1.1. Суффикс "#home" — detour: запрос уходит не
    # напрямую, а через группу "home", т.е. дома DIRECT, вне дома внутри
    # WG-туннеля. Без своего резолвера mihomo спрашивал бы системный
    # (/etc/resolv.conf = DNS текущей сети), который про .lan не знает.
    #
    # Важно: как только секция dns появилась, внутренний резолвер mihomo
    # отвечает за все его соединения, поэтому для всего остального явно
    # оставлен "system" — тот же системный резолвер, что и раньше, никаких
    # навязанных публичных серверов. listen не задан: DNS-порт mihomo не
    # открывает, резолвер нужен только ему самому.
    #
    # Отсюда и граница применимости: это работает для программ, которые
    # ходят через mihomo (http(s)_proxy, socks, proxychains, VM на
    # virbr0) — имя им разрешает сам mihomo. Системный `ping foo.lan` или
    # `ssh foo.lan` вне дома так работать не начнёт: у ноутбука нет TUN, и
    # мимо прокси трафик в домашнюю сеть не попадает. Дома они работают и
    # так — DHCP выдаёт роутер первым DNS.
    dns = {
      enable = true;
      ipv6 = false;
      nameserver = [ "system" ];
      nameserver-policy = { "+.lan" = "192.168.1.1#home"; };
    };
    # Домашняя подсеть и имена *.lan идут через "home" (lan-автоматика либо
    # ручной выбор); всё остальное — прежний MATCH,proxy (mihomo.nix
    # дописывает его последним).
    extraRules = [
      "DOMAIN-SUFFIX,lan,home"
      "IP-CIDR,192.168.1.0/24,home,no-resolve"
    ];
  };
  services.xray.enable = false;
  services.xray.settingsFile = "/home/nix/.nix/xray/client.json";
  services.openvpn = {
	restartAfterSleep = false;
	servers = {
    	thm = {
    		config = '' config /home/nix/.nix/misc/thm.ovpn '';
    		autoStart = false;
    	};
	};
  };
  # WireGuard road-warrior клиент к домашнему роутеру — был здесь как
  # networking.wg-quick.interfaces.home-lan (конфиг ~/.nix/misc/wg.conf,
  # вне репозитория). Заменён узлом "wg-home" в mihomo (services.mihomoBalancer
  # ниже): та же identity (ключ взят из misc/wg.conf), но через mihomo, с
  # авто-выбором DIRECT/туннель (группа "home"). Сам wg.conf оставлен на
  # диске как запись пары ключей, wg-quick больше не запускается.
  services.dbus.packages = [ pkgs.nautilus ];

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  programs.ssh.extraConfig = ''
    # nix-daemon runs as root and does its own ssh connection for distributed
    # builds — root has no ~/.ssh/config of its own, so this system-wide
    # config (not modules/home/misc.nix's home-manager "server" block, which
    # only applies to user nix's interactive shell) is what it reads. Same
    # key/user as the interactive block, just promoted to system level.
    Host server
      Hostname 192.168.1.148
      Port 22
      User nix
      IdentityFile /home/nix/.nix/ssh/server
  '';
  programs.fish.enable = true;
  # Kept in the repo for backup, but Niri is the WM actually used day to
  # day and duplicated its autostart. To bring Hyprland back: flip this to
  # true and uncomment modules/home/hyprland.nix in hosts/laptop/home.nix.
  programs.hyprland.enable = false;
  # programs.hyprland (when enabled) used to set this as a side effect,
  # satisfying home-manager's requirement (useUserPackages) that portal/
  # desktop-entry paths get linked for xdg.portal. Set it explicitly now
  # that Hyprland's module isn't around to do it implicitly.
  environment.pathsToLink = [ "/share/applications" "/share/xdg-desktop-portal" ];
  programs.wshowkeys.enable = true;
  programs.noisetorch.enable = true;
  programs.virt-manager.enable = true;
  # isNormalUser/shell come from modules/nixos/common.nix; this just adds
  # this host's groups on top (list-type options merge across modules).
  users.users.nix.extraGroups = [
     		 "video"
     		 "render"
     		 "input"
     		 "networkmanager"
     		 "pipewire"
     		 "libvirtd"
     		 "docker"
     		 "adbusers"
     		 "wireshark"
     		 "plugdev"
     		 "systemd-journal"
     		 "lp"
     		 "vboxusers"
  ];

  # security.doas/sudo come from modules/nixos/common.nix.
  security.pam.services = {
  	  gtklock.text = lib.readFile "${pkgs.gtklock}/etc/pam.d/gtklock";
  	  doas.fprintAuth = false;
  	  login.fprintAuth = false;
  };
  security.wrappers = {
    dumpcap = {
		owner = "root";
		group = "root";
		source = "${pkgs.wireshark}/bin/dumpcap";
		capabilities = "cap_net_admin,cap_net_raw=ep";
    };
  };
  services.fprintd.enable = true;
  services.fprintd.tod.enable = true;
  services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;
  services.openssh.settings = {
    enable = true;
    UseDns = true;
    PasswordAuthentication = false;
    PermitRootLogin = "no";
    KbdInteractiveAuthentication = false;
  };

  virtualisation.libvirtd = {
  enable = true;
    qemu = {
      runAsRoot = true;
      swtpm.enable = true;
	  vhostUserPackages = [ pkgs.virtiofsd ];
    };
  };
  virtualisation.docker.enable = true;
  # docker.service normally starts at boot and (since it wants
  # network-online.target) blocks multi-user.target on
  # NetworkManager-wait-online.service — ~7.6s together on this machine.
  # Nothing here actually needs docker running immediately at login, so
  # let docker.socket start it lazily on first use instead.
  virtualisation.docker.enableOnBoot = false;
  virtualisation.vmware.host.enable = false;
  virtualisation.virtualbox.host.enable = false;


  # nix-ld: provides the standard dynamic-linker path (/lib64/ld-linux-x86-64.so.2)
  # and a library search path so prebuilt, non-Nix-patched Linux binaries can
  # run at all -- NixOS has neither by default (see nix.dev/permalink/stub-ld).
  # Triggered by omniroute's vendored Playwright downloading its own
  # chrome-headless-shell into ~/.npm-global/.../node_modules (an ordinary
  # Ubuntu build, not autoPatchelf'd the way pkgs.playwright-driver.browsers
  # is) for its Cloudflare AI Playground provider; the same fix applies to
  # any other npm/pip/VS-Code-extension-fetched native binary hitting the
  # same "Could not start dynamically linked executable" error. The library
  # list below is the common Chrome-for-Testing/Chromium runtime dependency
  # set (X11, GTK, audio, accel) -- extend it if a *different* foreign binary
  # complains about a missing .so nix-ld doesn't already cover.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
  	glib
  	nss
  	nspr
  	atk
  	at-spi2-atk
  	at-spi2-core
  	cups
  	dbus
  	expat
  	libdrm
  	mesa
  	libGL
  	pango
  	cairo
  	gtk3
  	alsa-lib
  	freetype
  	fontconfig
  	libxkbcommon
  	systemd
  	libx11
  	libxcb
  	libxcomposite
  	libxdamage
  	libxext
  	libxfixes
  	libxrandr
  	libxshmfence
  	libxtst
  ];

  environment.sessionVariables = {
  	LIBVA_DRIVER_NAME = "iHD";
  };
  environment.systemPackages = with pkgs; [
     vim 
     wget
     doas
     bat
     eza
     htop
     terminus_font
     home-manager
     vial
     wineWow64Packages.stable
     winetricks
     wineWow64Packages.waylandFull
     git
     doas-sudo-shim
     inputs.hermes.packages.${pkgs.stdenv.hostPlatform.system}.default
     # CLI для deploy.nodes в flake.nix: deploy .#ru-edge | .#nl-exit | .
     inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
  # Одна запись — балансировщик mihomo (modules/nixos/mihomo.nix),
  # он сам выбирает живой туннель из Throne (2080) и xray (3080). Раньше
  # здесь был dynamic_chain по 2080 → 3080, но dynamic_chain не выбирает
  # один прокси, а цепляет *все живые подряд*: при запущенных обоих трафик
  # шёл двойным туннелем Throne → xray.
  environment.etc."proxychains.conf".text = ''
  strict_chain
  proxy_dns
  tcp_read_time_out 15000
  tcp_connect_time_out 8000
  [ProxyList]
  socks5 127.0.0.1 6080'';
  # Separate from the proxychains.conf above on purpose (same reasoning as
  # HTTPS_PROXY being scoped to just the `claude` fish function in
  # fish.nix, not a global sessionVariable): this one points only at the
  # ocproxy SOCKS5 port from the lab's openconnect VPN, and is wired only
  # into the `vmware` fish function below. Keeping it out of the shared
  # proxychains.conf means launching VMware Workstation Pro can never
  # accidentally get routed through the pentest-profile proxies (the
  # mihomo balancer on 6080), and vice versa. strict_chain (not dynamic_chain) is
  # deliberate too: if ocproxy isn't up, connecting to vCenter should fail
  # loudly instead of silently falling through to a direct connection.
  environment.etc."proxychains-vmware.conf".text = ''
  strict_chain
  proxy_dns
  tcp_read_time_out 15000
  tcp_connect_time_out 8000
  [ProxyList]
  socks5 127.0.0.1 5080'';

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
  	  nerd-fonts.jetbrains-mono
  	  nerd-fonts.ubuntu-sans
  	  nerd-fonts.symbols-only
  	  jetbrains-mono
	  liberation_ttf
	  corefonts
	  vista-fonts
	  noto-fonts
    ];
    fontconfig.defaultFonts = {
      
    };
  };

  # fonts.packages = [ pkgs.noto-fonts pkgs.jetbrains-mono ] ++ builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;
  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.05"; # Did you read the comment?

}

