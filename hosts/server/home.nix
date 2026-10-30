{ pkgs, inputs, ... }:
{
  # Композиционный корень home-manager для сервера.
  #
  # Из modules/home/ берётся только common.nix (CLI-инструменты, EDITOR/PAGER/
  # NH_FLAKE). Осознанно НЕ подключены:
  #   desktop.nix, niri.nix, noctalia.nix, misc.nix — графическая сессия,
  #     Wayland, порталы; на headless-хосте это мёртвый вес и лишние сборки.
  #     То немногое из misc.nix, что осмысленно и без графики (git, tmux,
  #     htop, eza/bat), продублировано ниже — импортировать файл целиком
  #     нельзя, он тянет librewolf, spicetify, kdeconnect и порталы;
  #   fish.nix — там зашиты алиасы `nixos-rebuild ... #laptop`, которые на этом
  #     хосте пересобирали бы чужую конфигурацию. Нужный минимум продублирован
  #     ниже с правильным #server. Если fish.nix когда-нибудь параметризуют по
  #     имени хоста, его можно будет импортировать и отсюда;
  #   profiles/{media,messengers,office,virtualization}.nix — GUI-приложения.
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/profiles/lab-automation.nix
    ../../modules/home/profiles/local-inference.nix
    ../../modules/home/nixvim.nix
    ../../modules/home/omniroute-mcp.nix
    ../../modules/home/pi.nix

    # Модуль самого hermes-agent (inputs.hermes в flake.nix). В nixpkgs и в
    # home-manager его нет вовсе — он приезжает из флейка проекта.
    #
    # Взят home-manager-вариант, а не inputs.hermes.nixosModules.default, и это
    # осознанно: hermes — агент одного человека. Его состояние (учётные данные,
    # память, сессии, cron-задачи) принадлежит пользователю, а не машине, и
    # правильное место для него — ~/.hermes и юниты systemd --user, а не
    # системный сервис с отдельной учёткой. NixOS-вариант пригодился бы для
    # мультипользовательской машины или для запуска в OCI-контейнере.
    inputs.hermes.homeManagerModules.default
    inputs.nixvim.homeModules.nixvim
  ];

  # common.nix задаёт EDITOR = "nvim", но сам neovim ставится на ноутбуке
  # модулем nixvim.nix, которого здесь нет — без этой строки EDITOR указывал бы
  # в пустоту. Взят голый neovim, а не modules/home/nixvim.nix: тот тянет
  # плагины и языковые серверы, которые на сервере редактировать нечего.
  home.packages = with pkgs; [
    neovim
  ];

  #############################################################################
  # Hermes — агент, который и будет пользоваться SearXNG
  #############################################################################

  # programs. и services. у этого модуля разделены намеренно: первое — «поставь
  # мне команду `hermes`», второе — «держи демона». Здесь нужно и то, и другое.
  programs.hermes-agent.enable = true;
  # desktop.enable не включается: это Electron-приложение с ярлыком в меню, на
  # машине без графической сессии ему нечего показывать.

  services.hermes-agent = {
    enable = true;

    # "dashboard" = бэкенд + веб-панель на том же порту; "serve" — то же самое
    # без интерфейса. Порт 127.0.0.1:9119 (значения по умолчанию, наружу не
    # торчит и в фаерволе дырки не требует). Открывать с ноутбука туннелем
    # поверх уже имеющегося SSH — ровно как llama-server на 8080:
    #   ssh -N -L 9119:127.0.0.1:9119 server
    # и затем http://127.0.0.1:9119 в браузере.
    #
    # Привязка именно к петле важна не только ради безопасности: любой другой
    # адрес включает в панели шлюз аутентификации, и без настроенных учётных
    # данных к ней уже не подключиться.
    backend.mode = "dashboard";

    # Переменные окружения, которые модуль при активации пишет в ~/.hermes/.env.
    # ВАЖНО: сюда — только не-секреты, файл собирается из /nix/store, который
    # читается всеми. Для ключей есть environmentFiles, принимающий рантайм-путь
    # от sops-nix, например:
    #   environmentFiles = [ config.sops.secrets."hermes-env".path ];
    environment = {
      # Адрес локального SearXNG (services.searx в hosts/server/default.nix).
      #
      # Тонкость, ради которой web.backend НЕ задаётся здесь в Nix: hermes
      # выбирает бэкенд веб-поиска автоматически по тому, какие переменные
      # окружения выставлены, и SEARXNG_URL — один из признаков в этой
      # таблице. Поэтому одной строки достаточно, чтобы поиск пошёл через
      # свой инстанс. А раз в config.yaml ничего не записано, `hermes tools`
      # остаётся волен переключить бэкенд позже: Nix-ключи в config.yaml
      # сливаются поверх файла и побеждают, то есть объявленное здесь стало бы
      # неотключаемым из интерфейса.
      SEARXNG_URL = "http://127.0.0.1:8888";
    };
  };

  #############################################################################
  # pi (pi-coding-agent)
  #
  # Общая часть — в modules/home/pi.nix; здесь только то, что лежит на диске
  # именно этого хоста.
  #############################################################################

  programs.pi.enable = true;

  # Скиллы hermes: их ведёт ~/.hermes (не этот репозиторий), поэтому ссылка на
  # живые каталоги, а не копия в git. В дефолт модуля они не вынесены
  # намеренно: на хосте без hermes (ноутбук) pi на каждый несуществующий путь
  # печатает диагностику "skill path does not exist".
  #
  # Свои скиллы репозитория (report-craft, ctf-reverse-engineering) здесь не
  # перечислять: их подмешивает modules/home/pi.nix. До этой правки они лежали в
  # `default` опции programs.pi.skills, и это присваивание их затирало — на
  # сервере report-craft не грузились (2026-10-25).
  programs.pi.skills = [
    "~/.hermes/skills/devops/nixos-system-administration"
    "~/.hermes/skills/nix-python-packaging"
    "~/.hermes/skills/security/godmode"
    "~/.hermes/skills/mlops/inference/strata"
  ];

  # filebrowser-MCP — отдельный проект на этом хосте (свой git, свой venv,
  # креды в его .env); Nix объявляет только ссылку на него, как obsidian-mcp.nix
  # на ноутбуке. На ноутбуке ~/local-mcps нет, поэтому серверов там и нет —
  # pi-mcp-extension при пустом списке молча выходит, а при команде, которой
  # нет на диске, ругается на каждом старте.
  programs.pi.mcp.mcpServers.filebrowser = {
    command = "/home/nix/local-mcps/filebrowser-mcp/run.sh";
    transport = "stdio";
    lifecycle = "eager";
    requestTimeoutMs = 120000;
  };

  # Playwright-MCP для pi: полноценный браузер (скриншоты, JS-рендеринг,
  # консольные логи, клики) — то, чего pi-web-access не умеет. На ноутбуке
  # браузерные MCP объявлены в modules/home/browser-mcp.nix и настроены на
  # Claude Code; здесь тот же playwright-mcp, но для pi и через его mcp.json.
  #
  # env не нужен: обёртка playwright-mcp из nixpkgs сама экспортирует
  # PLAYWRIGHT_BROWSERS_PATH=<store>-playwright-browsers (chromium, firefox,
  # webkit, ffmpeg — предсобранные бинари playwright, патченные под NixOS)
  # и PLAYWRIGHT_MCP_BROWSER=chromium. Без этого playwright полез бы в
  # ~/.cache/ms-playwright за докачкой браузеров, чего на NixOS не бывает.
  # Проверено на этом хосте: chromium из этого бандла стартует headless и
  # рендерит страницу (mcp 0.0.69, driver 1.59.1).
  #
  # --isolated: одноразовый профиль на каждый запуск. Без него playwright
  # держит профиль в ~/.cache/ms-playwright-mcp, и всё, что там появится
  # (куки, логин-сессии), переживало бы перезагрузку и доставалось каждой
  # последующей сессии — на headless-хосте это только балласт.
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

  # Для алиасов ниже: cat -> bat, ls/ll/la -> eza. Оба модуля ставят пакет и
  # добавляют интеграцию с fish.
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

  # Репозиторий конфигурации лежит и на этой машине, коммитить с неё придётся
  # (тот же ~/.nix), поэтому личность в git нужна та же, что на ноутбуке.
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
      # --sudo, а не --elevate=sudo: nixos-rebuild-ng в nixos-26.05 ещё не знает
      # флага --elevate (та же причина, что в modules/home/fish.nix).
      # Реального sudo в системе нет (security.sudo.enable = false в
      # modules/nixos/common.nix) — вызов проходит через doas-sudo-shim.
      rebuild-switch = "nixos-rebuild switch --flake /home/nix/.nix#server --sudo";
      rebuild-boot = "nixos-rebuild boot --flake /home/nix/.nix#server --sudo";
      rebuild-dry-activate = "nixos-rebuild dry-activate --flake /home/nix/.nix#server --sudo";

      # Те же, что в modules/home/fish.nix — чтобы руки в SSH-сессии работали
      # так же, как в локальном терминале.
      cat = "bat --style=plain --color=always";
      v = "nvim";
      ls = "eza --icons always";
      ll = "eza -lg --icons always";
      l = "eza -lg --icons always";
      la = "eza -lAg --icons always";

      # Общие dev-shell'ы курсовых работ (devShells в flake.nix) — от хоста не
      # зависят, работают и отсюда.
      dev-py = "nix develop /home/nix/.nix#python";
      dev-java = "nix develop /home/nix/.nix#java";
      dev-cpp = "nix develop /home/nix/.nix#cpp";
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

      # HTTPS_PROXY сознательно не глобальная переменная сессии, а обёртка
      # вокруг одной команды — та же история, что на ноутбуке: глобальную
      # подхватывает любое приложение подряд. 6080 — mixed-порт mihomo
      # (modules/nixos/mihomo.nix), он выбирает между xray@ (3080) и
      # подпиской, поэтому обёртка работает, пока жив mihomo и хоть один
      # апстрим.
      # `command claude`, а не `claude` — иначе функция рекурсивно вызвала бы
      # саму себя.
      claude = {
        body = ''
          set -lx HTTPS_PROXY http://127.0.0.1:6080
          command claude $argv
        '';
      };

      # Та же схема, что у claude выше: секрет не в глобальной переменной
      # сессии, а подставляется только вокруг конкретной команды. llama.cpp
      # сам понимает флаг -hf/--hf-repo (скачивание GGUF прямо с HuggingFace)
      # и сам же берёт токен из HF_TOKEN, если он есть в окружении — нужен
      # он не для публичных моделей, а для gated-репозиториев и для более
      # высокого рейт-лимита. /run/secrets/hf-token — расшифрованный sops-nix
      # секрет (hosts/server/default.nix), owner=nix, поэтому cat читает его
      # без doas.
      llama-server = {
        body = ''
          set -lx HF_TOKEN (cat /run/secrets/hf-token)
          command llama-server $argv
        '';
      };
      llama-cli = {
        body = ''
          set -lx HF_TOKEN (cat /run/secrets/hf-token)
          command llama-cli $argv
        '';
      };
    };

    plugins = [
      {
        name = "tide";  # run tide configure on fresh system
        src = pkgs.fishPlugins.tide.src;
      }
      {
        name = "grc";
        src = pkgs.fishPlugins.grc.src;
      }
    ];
  };

  # Длинные задачи (прогон лабы целиком, импорт .ova, инференс) должны
  # переживать обрыв SSH. Запускать их внутри tmux, а не голой командой:
  #   tmux new -s lab      — начать
  #   Ctrl-a d             — отцепиться, можно закрывать ноутбук
  #   tmux attach -t lab   — вернуться
  programs.tmux = {
    enable = true;
    mouse = true;
    historyLimit = 50000;
    escapeTime = 10;

    # Префикс C-a вместо штатного C-b — только на этом хосте. На ноутбуке
    # (modules/home/misc.nix) остаётся C-b, и расходиться им здесь нормально:
    # в tmux на сервере сидят через SSH, поверх локального терминала, а C-b
    # там может быть уже занят внешним tmux.
    #
    # Модуль сам добавляет `unbind C-b` и `bind C-a send-prefix`, так что C-a
    # в значении «в начало строки» никуда не делся — он доходит до приложения
    # двойным нажатием C-a C-a.
    prefix = "C-a";
    keyMode = "vi";

    extraConfig = ''
      set -g focus-events on

      # Аналог `y -> wl-copy` с ноутбука, только без Wayland. set-clipboard on
      # заставляет tmux отправлять скопированное escape-последовательностью
      # OSC 52 — её получает терминал на ТОМ конце SSH-сессии и кладёт текст в
      # буфер обмена ноутбука. Поэтому здесь copy-selection-and-cancel, а не
      # copy-pipe-and-cancel: внешней команды-приёмника на сервере нет.
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
}
