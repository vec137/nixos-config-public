{ pkgs, ... }:
{
  # Композиционный корень home-manager для forge — временной машины под
  # агентские задачи. Отличия от hosts/server/home.nix (откуда взята основа):
  #
  #   нет profiles/local-inference.nix — инференс остаётся на server,
  #     этот хост его не дублирует (и не должен: GPU здесь нет);
  #   profiles/lab-automation.nix подключён: на forge есть ~/Stuff/sut, и это
  #     ещё и тулка скиллов report-craft (soffice/poppler/imagemagick) — без
  #     неё их скрипты падали (см. docs/repo-notes.md); образы ВМ лаб при этом
  #     остаются на server, на forge `VBoxManage list vms` пуст;
  #   нет nixvim.nix — на временной машине редактировать нечего, хватает
  #     голого neovim (nixvim тянет плагины и языковые серверы, это десятки
  #     минут сборки на первый rebuild).
  #
  # Из modules/home/ подключено только то, что осмысленно без графики: см.
  # комментарий в hosts/server/home.nix — там же объяснено, почему
  # misc.nix/fish.nix импортировать целиком нельзя (графика и алиасы с
  # зашитым #laptop).
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/pi.nix
    ../../modules/home/omniroute-mcp.nix
    # Тулка для скиллов report-craft (soffice, pdftotext/pdftoppm, magick) и
    # для пайплайна лаб; nodejs здесь уже объявлен в omniroute-mcp.nix тем же
    # атрибутом — дубль безвреден, в профиль кладётся один и тот же store-путь.
    ../../modules/home/profiles/lab-automation.nix
    # yt-dlp + ffmpeg-headless — нужно fetch_content самого pi (разбор видео:
    # YouTube и локальные .mkv из дерева лаб). media.nix вместо него брать
    # нельзя: там GUI-приложения и ffmpeg-full с X11/GPU-обвязкой.
    ../../modules/home/profiles/media-headless.nix
  ];

  # common.nix задаёт EDITOR = "nvim", но сам neovim ставится модулем
  # nixvim.nix, которого здесь нет — без этой строки EDITOR указывал бы в
  # пустоту.
  home.packages = with pkgs; [
    neovim
  ];

  #############################################################################
  # pi (pi-coding-agent)
  #############################################################################

  # Общая часть — modules/home/pi.nix (включая скиллы и расширения самого
  # репозитория; присваивать programs.pi.skills здесь НЕ надо — listOf
  # затирает дефолт целиком, на этом уже терялись report-craft и
  # ctf-reverse-engineering, см. docs/repo-notes.md). Присваивание ниже —
  # добавка к тому, что подмешивает модуль, а не замена.
  programs.pi.enable = true;

  # Скиллы hermes переехали на forge вместе с ~/.hermes (копия с server).
  # Объявлены ровно те же четыре пути, что на server (hosts/server/home.nix),
  # а не весь ~/.hermes/skills: там есть security/ctf-reverse-engineering —
  # одноимённый скиллу репозитория, и pi выдал бы collision-диагностику
  # (dist/core/skills.js: skillMap по name, второй молча проигрывает).
  #
  # Сам hermes на forge не установлен (бинаря нет, ~/.hermes/bin пуст) — это
  # статичная копия: hermes-curator её не обновляет и не чистит, правки
  # вручную, и с server они сами не приезжают.
  programs.pi.skills = [
    "~/.hermes/skills/devops/nixos-system-administration"
    "~/.hermes/skills/nix-python-packaging"
    "~/.hermes/skills/security/godmode"
    "~/.hermes/skills/mlops/inference/strata"
  ];

  # Чего на этом хосте осознанно нет:
  #
  #   mcpServers.filebrowser — MCP-тулка живёт в ~/local-mcps на server; сам
  #     каталог на forge есть (переехал), и скилл filebrowser-mirror-sync
  #     работает без тулки через REST: .env на месте, зеркало отвечает.
  #   profiles/local-inference.nix и hermes как программа — см. шапку файла.
  #
  # Про модель: дефолтный провайдер pi (modules/home/pi.nix, strata) смотрит в
  # http://localhost:8080/v1, а на forge там ничего не слушает. Два рабочих
  # варианта, оба без правок конфигурации:
  #   1) прокинуть инференс с server: `strata-tunnel` (алиас ниже) — после
  #      этого localhost:8080 на forge это strata на server;
  #   2) `pi` с внешним провайдером через /login и /model.
  # Виртуалки, playwright и прочее от выбора модели не зависят.

  # Playwright-MCP — полноценный браузер для pi (скриншоты, JS-рендеринг,
  # клики), то же, что на server. Обёртка из nixpkgs сама подставляет
  # PLAYWRIGHT_BROWSERS_PATH с предсобранными браузерами, иначе playwright
  # полез бы докачивать их в ~/.cache, чего на NixOS не бывает.
  # --isolated: одноразовый профиль на запуск, чтобы куки и логин-сессии не
  # переживали перезагрузку и не доставались следующей задаче.
  programs.pi.mcp.mcpServers.playwright = {
    command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
    args = [ "--isolated" ];
    transport = "stdio";
    lifecycle = "eager";
    requestTimeoutMs = 120000;
  };

  #############################################################################
  # Оболочка
  #############################################################################

  programs.bat.enable = true;
  programs.eza.enable = true;

  programs.htop = {
    enable = true;
    settings = {
      show_cpu_usage = 1;
      show_cpu_frequency = 1;
      show_cpu_temperature = 1;
    };
  };

  # Та же личность в git, что на двух других хостах: репозиторий конфигурации
  # лежит и здесь, коммитить с этой машины придётся.
  programs.git = {
    enable = true;
    settings = {
      user.name = "vec137";
      user.email = "you@example.com";
      init.defaultBranch = "master";
      pull.rebase = "false";
    };
  };

  programs.fish = {
    enable = true;
    shellAliases = {
      # --sudo, а не --elevate=sudo: nixos-rebuild-ng в nixos-26.05 ещё не
      # знает флага --elevate. Реального sudo в системе нет
      # (security.sudo.enable = false), вызов идёт через doas-sudo-shim.
      rebuild-switch = "nixos-rebuild switch --flake /home/nix/.nix#forge --sudo";
      rebuild-boot = "nixos-rebuild boot --flake /home/nix/.nix#forge --sudo";
      rebuild-dry-activate = "nixos-rebuild dry-activate --flake /home/nix/.nix#forge --sudo";

      cat = "bat --style=plain --color=always";
      v = "nvim";
      ls = "eza --icons always";
      ll = "eza -lg --icons always";
      l = "eza -lg --icons always";
      la = "eza -lAg --icons always";

      dev-py = "nix develop /home/nix/.nix#python";
      dev-java = "nix develop /home/nix/.nix#java";
      dev-cpp = "nix develop /home/nix/.nix#cpp";

      # ---- виртуалки ----
      # virsh по умолчанию лезет в сессионный (qemu:///session) или системный
      # демон в зависимости от сборки; явный URI убирает двусмысленность: ВМ
      # этого хоста живут в системном libvirtd, под учёткой qemu-libvirtd.
      vms = "virsh -c qemu:///system list --all";
      vnets = "virsh -c qemu:///system net-list --all";
      # Кто сейчас держит аппаратную виртуализацию (скрипт объявлен в
      # hosts/forge/default.nix) — первое, что надо посмотреть, если
      # VirtualBox или VMware отказываются стартовать.
      hvs = "hv status";

      # Инференс с server на локальный порт: пока держится эта сессия,
      # localhost:8080 на forge — это strata/llama-server на server. -N — без
      # шелла, только туннель.
      strata-tunnel = "ssh -N -L 8080:127.0.0.1:8080 server";
    };

    shellInit = ''
      set fish_escape_delay_ms 1000;
      bind \b 'backward-kill-word';
      bind \e\[3\;5~ 'kill-word';
      bind \e\e 'fish_commandline_prepend doas';
    '';

    functions = {
      fish_greeting = {
        body = "";
        onEvent = "fish_greeting";
      };

      # HTTPS_PROXY намеренно не глобальная переменная сессии, а обёртка вокруг
      # одной команды: глобальную подхватывает любое приложение подряд (на
      # ноутбуке так через туннель молча ходил клиент Яндекс.Музыки). 6080 —
      # mixed-порт mihomo (modules/nixos/mihomo.nix). Работает, пока жив
      # mihomo и хоть один узел подписки; до шага sops (secretsReady в
      # hosts/forge/default.nix) mihomo на этом хосте не запущен вовсе, и
      # claude будет пытаться идти напрямую.
      # `command claude`, а не `claude` — иначе функция вызвала бы саму себя.
      claude = {
        body = ''
          set -lx HTTPS_PROXY http://127.0.0.1:6080
          command claude $argv
        '';
      };
    };

    plugins = [
      {
        name = "tide"; # на свежей системе один раз: tide configure
        src = pkgs.fishPlugins.tide.src;
      }
      {
        name = "grc";
        src = pkgs.fishPlugins.grc.src;
      }
    ];
  };

  # Агентские задачи здесь длинные (установка гостевой ОС, прогон стенда), и
  # обрыв SSH не должен их убивать. Запускать внутри tmux:
  #   tmux new -s vm       — начать
  #   Ctrl-a d             — отцепиться
  #   tmux attach -t vm    — вернуться
  programs.tmux = {
    enable = true;
    mouse = true;
    historyLimit = 50000;
    escapeTime = 10;

    # C-a вместо штатного C-b — как на server: в tmux здесь сидят по SSH,
    # поверх локального терминала, где C-b может быть занят внешним tmux.
    prefix = "C-a";
    keyMode = "vi";

    extraConfig = ''
      set -g focus-events on

      # set-clipboard on заставляет tmux отдавать скопированное через OSC 52 —
      # его принимает терминал на ТОМ конце SSH и кладёт текст в буфер обмена
      # ноутбука. Поэтому copy-selection-and-cancel, а не copy-pipe: своего
      # приёмника (wl-copy) на этой машине нет.
      set -g set-clipboard on
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-selection-and-cancel

      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5
    '';
  };

  #############################################################################
  # SSH-клиент
  #############################################################################

  # Своего ssh-конфига на forge не было вообще, и это не недосмотр, а побочный
  # эффект сборки «из частей»: matchBlocks ноутбука живут в
  # modules/home/misc.nix, который здесь не импортируется (тянет графику и
  # алиасы с зашитым #laptop), а hosts/server/home.nix, с которого взята
  # основа, ssh не настраивает — на server ходят, а не с него. В результате
  # ~/.ssh/config на forge не существовало, ни один identityFile не
  # подставлялся, и `ssh server` отвечал «Permission denied (publickey)»,
  # хотя нужный ключ лежал рядом.
  #
  # Приватные ключи ни в git, ни в /nix/store (он читаем всем) не попадают —
  # их копируют в ~/.nix/ssh/ руками, см. docs/install-forge.md. Здесь
  # объявлены только пути.
  programs.ssh = {
    enable = true;
    # Иначе home-manager допишет свой блок `Host *` со собственными
    # дефолтами; на ноутбуке он тоже выключен (modules/home/misc.nix).
    enableDefaultConfig = false;
    settings = {
      # Имя короткое, без домена и без адреса: записи зоны `lan` отдаёт
      # dnsmasq роутера из DHCP-аренды, а `search lan` приходит клиенту тем
      # же DHCP — резолвер сам превращает `server` в `server.lan`.
      #
      # Ключ — тот же ~/.nix/ssh/server, которым ходит ноутбук: в
      # authorizedKeys у server он один-единственный
      # (hosts/server/default.nix), а трогать конфигурацию server ради
      # временного хоста незачем. Цена решения в том, что forge получает ту
      # же личность, что ноутбук, — отозвать доступ только у forge нельзя,
      # только у обоих сразу.
      "server" = {
        hostname = "server";
        port = 22;
        user = "nix";
        identityFile = "~/.nix/ssh/server";
      };
      "github.com" = {
        identityFile = "~/.nix/ssh/github";
      };
    };
  };
}
