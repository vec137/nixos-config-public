{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# pi (pi-coding-agent) — декларативное описание ~/.pi/agent.
#
# Как pi раскладывает состояние (см. dist/config.js в пакете, функции
# getAgentDir/getSettingsPath/...): весь каталог ~/.pi/agent — это dir, в
# который pi пишет сам: settings.json (перезаписывает при /settings, /model,
# /theme, при `pi install`), auth.json (креды), sessions/, npm/ (node_modules
# пакетов расширений), bin/, web-search-cache/, mcp-auth/ (токены OAuth от
# pi-mcp-extension). Поэтому каталог целиком под Nix забирать нельзя —
# правильно описывать только то, что pi читает, а сам не пишет.
#
# Разделение по типам:
#
#   1. Читается pi, не пишется им → symlink прямо из /nix/store:
#        models.json, mcp.json (pi-mcp-extension читает его, пишет только
#        токены в ~/.pi/agent/mcp-auth/, самого mcp.json не касается;
#        models.json в dist вообще нигде не пишется — только getModelsPath),
#        и AGENTS.md — глобальный контекст pi (см. ниже).
#
#   2. Пишется pi → settings.json остаётся обычным файлом в $HOME, а Nix
#        вливает в него свои ключи через jq-слияние при активации
#        (см. home.activation.piSettings). Ключи, которые pi ведёт сам
#        (lastChangelogVersion и т.п.), при этом сохраняются. Тот же приём,
#        что и в obsidian-mcp.nix: не владеть чужим mutable-состоянием
#        целиком, а идемпотентно приводить его к желаемому. То же касается
#        web-search.json (конфиг pi-web-access): расширение само дописывает
#        его при /provider и /websearch (saveConfig в index.ts), поэтому он
#        тоже сливается, а не симлинкуется (см. programs.pi.webSearch).
#
#   3. Ресурсы (extensions/skills/prompts/themes) вообще не обязаны лежать в
#        ~/.pi/agent: settings.json принимает абсолютные пути и `~`
#        (docs/settings.md, секция Resources). Поэтому они живут в этом
#        репозитории (modules/home/pi/), а в ~/.pi/agent их копий нет вовсе.
#        ВАЖНО: каталоги ~/.pi/agent/extensions/ и ~/.pi/agent/skills/
#        pi сканирует автоматически, и список `skills`/`extensions` в
#        settings.json не заменяет автопоиск, а добавляется к нему — копия
#        того же расширения в двух местах грузится дважды (проверено:
#        `pi --help` показывает флаг расширения два раза). Локальные копии
#        при переезде на Nix убраны в ~/.pi/agent/.pre-nix/.
#        ВАЖНО-2: пути репозитория подмешивает сам модуль (см. finalSettings),
#        а не `default` опций `skills`/`extensions`: `types.listOf` — не attrs,
#        и присваивание в хосте затирает дефолт целиком (на этом и потерялись
#        report-craft с ctf-reverse-engineering, см. docs/repo-notes.md).
#
#   4. Секреты не в Nix: auth.json (пустой, /login пишет), ~/.pi/agent/npm/
#        (ставится npm'ом при старте), креды filebrowser-MCP в
#        ~/local-mcps/filebrowser-mcp/.env. В models.json поле apiKey — это
#        либо имя переменной окружения, либо литерал; сейчас там литерал
#        "strata", который ничего не значит (strata/llama-server ключ не
#        проверяет). Если появится настоящий ключ — гнать его через sops в
#        /run/secrets и в models.json указывать имя env-переменной.
#
# Версии: сам pi приезжает из nixpkgs (на данный момент 0.75.4), апгрейд —
# только через flake.lock. Обёртка пакета ставит PI_SKIP_VERSION_CHECK=1 и
# PI_TELEMETRY=0, поэтому `pi update --self` апгрейдить не будет; расширение
# pi-web-access при старте ворчит «requires Pi 0.86.0 or newer» — на 0.75.4
# оно деградирует до eager-инструментов, это ожидаемо. Пакеты расширений в
# `packages` специально пинуются точными версиями (@1.5.1): без пина их
# молча обновляет `pi update --extensions`, с пином pi их пропускает.
#
# Почему это модуль с опциями (`programs.pi.*`), а не плоский файл: содержимое
# ~/.pi/agent различается между хостами (на ноутбуке нет ни hermes, ни
# ~/local-mcps, ни локального инференса на 8080), а таскивать два почти
# одинаковых модуля — значит их рассинхронить (см. историю fish.nix/misc.nix
# в docs/repo-notes.md). Хосты теперь импортируют этот файл и переопределяют
# только различающиеся опции. Грабля на будущее: имя `programs.pi` может
# однажды приехать из upstream home-manager — тогда коллизия решается через
# disabledModules, как с noctalia.
# ---------------------------------------------------------------------------

let
  cfg = config.programs.pi;

  # ~/.pi/agent/models.json
  defaultModels = {
    "$schema" = "https://pi.dev/schemas/models.schema.json";
    providers.strata = {
      # Одинаковый адрес на обоих хостах намеренно (просьба пользователя):
      # на сервере на 8080 висит strata/llama-server, на ноутбуке локально
      # там пока ничего нет — локальный инференс в этом репозитории
      # сервер-only (profiles/local-inference.nix в hosts/laptop/home.nix не
      # импортируется). Ноутбуку либо свой сервер на 8080, либо
      # http://192.168.1.148:8080/v1 (LAN-адрес сервера), либо свой
      # провайдер.
      baseUrl = "http://localhost:8080/v1";
      api = "openai-completions";
      apiKey = "strata";
      models = [
        {
          id = "qwen3.8-flash-next-iq3_s";
          contextWindow = 262144;
          maxTokens = 16384;
          input = [ "text" "image" ];
          reasoning = true;
          thinkingLevelMap = {
            off = "none";
            minimal = null;
            xhigh = "max";
          };
        }
      ];
    };
  };

  # ~/.pi/agent/mcp.json — читает pi-mcp-extension. Общий для всех хостов
  # только блок settings; сами серверы у каждого хоста свои (см.
  # hosts/server/home.nix) — их пути живут в домашней папке конкретного
  # хоста и в репозиторий не приезжают.
  defaultMcpSettings = {
    toolPrefix = "mcp";
    requestTimeoutMs = 60000;
    maxRetries = 3;
  };

  # ~/.pi/agent/settings.json (верхний слой слияния — объявленное здесь побеждает)
  defaultSettings = {
    defaultProvider = "strata";
    defaultModel = "qwen3.8-flash-next-iq3_s";
    defaultThinkingLevel = "medium";
    theme = "dark";
    hideThinkingBlock = true;

    # 24576 вместо дефолтных 16384: контекст strata 262144, и при
    # компакции должно оставаться место под ответ + системный промпт.
    compaction = {
      reserveTokens = 24576;
    };

    enableInstallTelemetry = false;
  };

  # packages/skills/extensions — не часть `settings`: их список собирается из
  # отдельных опций, чтобы хост мог снять/добавить одну строку, не переписывая
  # весь settings.json.
  #
  # Пути ресурсов репозитория (modules/home/pi/{skills,extensions}) подмешиваются
  # здесь, а не лежат в `default` опций. Причина: `types.listOf` — не attrs, и
  # обычное присваивание в хосте вытесняет дефолт ЦЕЛИКОМ, а не дописывает к нему
  # (в отличие от attrs вроде programs.pi.mcp.mcpServers, которые сливаются).
  # Именно так с сервера пропали report-craft и ctf-reverse-engineering:
  # hosts/server/home.nix объявил programs.pi.skills = [ hermes-пути ], и дефолт
  # "${./pi/skills}" перестал попадать в settings.json; на ноутбуке присваивания
  # нет — там они грузились. Проверка: `jq .skills ~/.pi/agent/settings.json`.
  finalSettings = cfg.settings // {
    packages = cfg.packages;
    skills = lib.unique ([ "${./pi/skills}" ] ++ cfg.skills);
    extensions = lib.unique ([ "${./pi/extensions}" ] ++ cfg.extensions);
  };

  # ~/.pi/agent/web-search.json — конфиг pi-web-access (web_search/fetch_content).
  # Дефолт один на обоих хостах: оба живут за нашей цензурой и оба крутят
  # mihomo на mixed-порту 127.0.0.1:6080 (services.mihomoBalancer, общий
  # modules/nixos/mihomo.nix). Без прокси расширение бессильно: у него нет
  # ключей, провайдер по умолчанию — Exa zero-config (mcp.exa.ai), а прямой
  # TLS к mcp.exa.ai с нашей сети даёт cloudflare-заглушку (проверено curl:
  # напрямую 403 с HTML-заглушкой, через 6080 — валидный MCP-хендшейк).
  # При этом расширение принципиально игнорирует env-прокси (HTTP_PROXY и
  # т.п. — см. README, секция Proxy), единственный путь — явный `proxy` в
  # этом файле; он действует только на инструменты расширения, на модельные
  # запросы pi не влияет. curl для проксирования есть на обоих хостах
  # (curlFull в modules/home/common.nix).
  #
  # Файл mutable: saveConfig пишет в него provider/workflow — поэтому он в
  # той же категории 2, что settings.json, и сливается тем же скриптом.
  # Пустой attrs (`{}`) означает «не трогать файл» — хост может снять
  # объявление mkForce'ом пустого attrs.
  defaultWebSearch = {
    proxy = "http://127.0.0.1:6080";
  };

  modelsJson = pkgs.writeText "pi-models.json" (builtins.toJSON cfg.models);
  mcpJson = pkgs.writeText "pi-mcp.json" (builtins.toJSON {
    settings = cfg.mcp.settings;
    mcpServers = cfg.mcp.mcpServers;
  });
  settingsJson = pkgs.writeText "pi-settings.json" (builtins.toJSON finalSettings);
  webSearchJson = pkgs.writeText "pi-web-search.json" (builtins.toJSON cfg.webSearch);

  # Слияние объявленных ключей в живой settings.json: объявленное (.[0])
  # перекрывает живое (.[1]) рекурсивно по объектам, живые ключи, которых
  # нет в объявлении (lastChangelogVersion и всё, что pi допишет сам),
  # сохраняются.
  #
  # Обычное `jq -s '.[0] * .[1]'` для этого не годится: оператор * у jq для
  # массивов сливает их поэлементно, а не заменяет целиком, и короткий
  # живой массив (packages/skills, которые pi сам же и переписывает при
  # `pi install`) перекрывал объявленный. Поэтому своё рекурсивное слияние:
  # объект+объект -> рекурсия, всё остальное (в т.ч. массивы) -> значение
  # из объявления.
  # $1 — объявленный JSON (из store), $2 — живой файл.
  mergeJsonFile = pkgs.writeShellScript "pi-merge-json" ''
    set -eu
    declared="$1"
    target="$2"
    mkdir -p "$(dirname "$target")"
    if [ ! -e "$target" ] || [ -L "$target" ]; then
      rm -f "$target"
      cp "$declared" "$target"
    else
      tmp="$(mktemp "$target.XXXXXX")"
      ${pkgs.jq}/bin/jq -s '
        def dm($d;$l):
          reduce ($d|keys_unsorted[]) as $k ($l;
            .[$k] = (if ($l|has($k)) and (($d[$k]|type)=="object") and (($l[$k]|type)=="object")
                     then dm($d[$k];$l[$k])
                     else $d[$k] end));
        dm(.[0]; .[1])' "$declared" "$target" > "$tmp"
      chmod 644 "$tmp"
      mv "$tmp" "$target"
    fi
  '';
in
{
  options.programs.pi = with lib; {
    enable = mkEnableOption "pi-coding-agent: декларативная конфигурация ~/.pi/agent";

    package = mkPackageOption pkgs "pi-coding-agent" { };

    models = mkOption {
      type = types.raw;
      default = defaultModels;
      description = ''
        Содержимое ~/.pi/agent/models.json (провайдеры и модели).
        Пишется симлинком из store: pi этот файл не меняет никогда.
      '';
    };

    mcp = {
      settings = mkOption {
        type = types.raw;
        default = defaultMcpSettings;
        description = "Блок settings в ~/.pi/agent/mcp.json (читает pi-mcp-extension).";
      };
      mcpServers = mkOption {
        type = types.attrsOf types.raw;
        default = { };
        example = literalExpression ''
          filebrowser = {
            command = "/home/nix/local-mcps/filebrowser-mcp/run.sh";
            transport = "stdio";
            lifecycle = "eager";
          };
        '';
        description = ''
          MCP-серверы этого хоста. По умолчанию пусто: pi-mcp-extension при
          отсутствии серверов молча выходит, ничего не ругаясь. Пустой
          запуск команды, которой на хосте нет, наоборот даёт ошибку на
          каждом старте — поэтому серверы объявляет тот хост, у которого
          они лежат на диске.
        '';
      };
    };

    packages = mkOption {
      type = types.listOf types.str;
      default = [
        "npm:pi-mcp-extension@1.5.1"
        "npm:pi-web-access@0.42.0"
      ];
      description = ''
        Пакеты расширений/скиллов, которые грузит pi. Точные пины версии
        обязательны: непинутые обновляет `pi update --extensions`,
        запиненные pi пропускает.
      '';
    };

    skills = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = literalExpression ''
        [ "~/.hermes/skills/devops/nixos-system-administration" ]
      '';
      description = ''
        Пути со скиллами (абсолютные или `~`) — только хостские дополнения.
        Каталог репозитория modules/home/pi/skills (свои скиллы: report-craft,
        ctf-reverse-engineering) подмешивается самим модулем и в дефолт этой
        опции не вынесен, иначе любое присваивание в хосте его затирает.

        Списки добавляются к автопоиску ~/.pi/agent/skills/ и
        ~/.agents/skills/, а не заменяют его — дубль того же скилла в двух
        местах грузится дважды. Несуществующий путь pi помечает диагностикой
        "skill path does not exist" на каждый старт, поэтому скиллы hermes
        объявлены только в hosts/server/home.nix (на ноутбуке hermes нет).
      '';
    };

    extensions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Пути с расширениями (файлы .ts или каталоги) — только хостские
        дополнения; modules/home/pi/extensions подмешивает модуль. См.
        замечания про автопоиск и про затирание дефолта присваиванием в `skills`.
      '';
    };

    webSearch = mkOption {
      type = types.raw;
      default = defaultWebSearch;
      example = literalExpression ''{}'';
      description = ''
        Содержимое ~/.pi/agent/web-search.json (конфиг расширения
        pi-web-access: proxy, provider, searchRouting, fetchRouting, ...).
        Сливается с живым файлом, а не перезаписывает: расширение само
        дописывает в него provider/workflow (saveConfig). Пустой attrs
        файл не трогает.
      '';
    };

    settings = mkOption {
      type = types.raw;
      default = defaultSettings;
      description = ''
        Плоские ключи ~/.pi/agent/settings.json, кроме packages/skills/
        extensions (у них свои опции выше — они подмешиваются в итоговый
        JSON). Сливается с живым файлом, а не перезаписывает его.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.file.".pi/agent/models.json" = {
      source = modelsJson;
      force = true;
    };

    home.file.".pi/agent/mcp.json" = {
      source = mcpJson;
      force = true;
    };

    # Глобальный контекст pi: pi читает AGENTS.md (или CLAUDE.md) из agentDir
    # на любом cwd, плюс по одному AGENTS.md/CLAUDE.md с каждого каталога от
    # cwd вверх до / (dist/core/resource-loader.js: loadProjectContextFiles,
    # кандидаты AGENTS.md, AGENTS.MD, CLAUDE.md, CLAUDE.MD — берётся первый
    # найденный). Отсюда правило «всегда работать в git worktree», которое
    # должно действовать во всех репозиториях, а не только в этом.
    #
    # Побочный эффект того же механизма: worktree этого репозитория несёт в
    # своём чекауте его AGENTS.md, так что репозиторные правила доходят до
    # сессии и внутри worktree, и из любого каталога внутри него.
    home.file.".pi/agent/AGENTS.md" = {
      source = ./pi/AGENTS.md;
      force = true;
    };

    home.activation.piSettings = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${mergeJsonFile} ${settingsJson} "''${HOME}/.pi/agent/settings.json"
      ${lib.optionalString (cfg.webSearch != {}) ''
      $DRY_RUN_CMD ${mergeJsonFile} ${webSearchJson} "''${HOME}/.pi/agent/web-search.json"
      ''}
    '';
  };
}
