{ inputs, ... }:
{
  # home-manager itself now ships a generic programs.noctalia module
  # upstream that collides with inputs.noctalia.homeModules.default below
  # ("already declared"). Its version expects a plain pkgs.noctalia
  # package, which doesn't exist in our nixpkgs - noctalia is deliberately
  # built from its own flake input instead, pinned to noctalia's own
  # nixpkgs revision so it hits noctalia.cachix.org (see flake.nix). Drop
  # home-manager's stock module so its module wins without a conflict.
  #
  # As of the 2026-10-01 flake update (home-manager 7b4c5ec4 -> c8ecc29e),
  # home-manager refactored this from a single file
  # (modules/programs/noctalia.nix) into a directory
  # (modules/programs/noctalia/default.nix) -- it now auto-discovers both
  # files and directories under modules/programs/* (modules/modules.nix).
  # disabledModules matches by path, so the entry has to drop the ".nix"
  # to keep matching; a future bump could rename/relocate it again.
  disabledModules = [ "programs/noctalia" ];

  imports = [
    inputs.nixvim.homeModules.nixvim
    inputs.niri.homeModules.niri
    inputs.noctalia.homeModules.default

    ../../modules/home/common.nix
    ../../modules/home/desktop.nix
    ../../modules/home/misc.nix
    ../../modules/home/fish.nix
    ../../modules/home/nixvim.nix
    ../../modules/home/noctalia.nix
    ../../modules/home/ghostty.nix
    ../../modules/home/niri.nix
    ../../modules/home/obsidian-mcp.nix
    ../../modules/home/browser-mcp.nix
    ../../modules/home/omniroute-mcp.nix
    ../../modules/home/pi.nix
    # ../../modules/home/stylix.nix
    # ../../modules/home/hyprland.nix  # not loaded by default — see that file for how to re-enable

    ../../modules/home/profiles/security-tools.nix
    ../../modules/home/profiles/virtualization.nix
    ../../modules/home/profiles/media.nix
    ../../modules/home/profiles/messengers.nix
    ../../modules/home/profiles/office.nix
  ];

  #############################################################################
  # pi (pi-coding-agent) — общая часть в modules/home/pi.nix
  #############################################################################

  programs.pi.enable = true;

  # Ничего серверного сюда не переносится намеренно:
  #   - скиллы ~/.hermes/skills/* объявлены в hosts/server/home.nix — hermes на
  #     этом хосте не ставится, а на несуществующий путь pi каждый старт
  #     печатает диагностику "skill path does not exist";
  #   - MCP-сервер filebrowser там же: ~/local-mcps на ноутбуке нет, а на
  #     команду, которой нет на диске, pi-mcp-extension ругается при каждом
  #     запуске (при пустом списке серверов он выходит молча).
  #   Из своих здесь только wordcraft: он приезжает через profiles/office.nix.

  # WordCraft отдаёт MCP-сервер сам, отдельным бинарём: `wordcraft-cli mcp`
  # (stdio, тот же движок, что и GUI; 16 инструментов — list_commands,
  # execute, batch, new_document/open_document/save_document, type_text,
  # inspect_document, render_page, screenshot/click/key…). Отдельного
  # проекта/venv, как с filebrowser/obsidian, не требует.
  #
  # --automation-read-root/--automation-write-root confine'ят файлы, которые
  # читают и пишут команды агента (open, save, export, insert picture,
  # mail-merge данные); с --connect они запрещены — там доступ к файлам у
  # самого приложения, а не у моста.
  #
  # Мост к живому окну приложения (--connect HOST:PORT): включает в MCP
  # ui-инструменты (screenshot/click/key/ui_inspect) и работу с открытым в
  # окне документом. Работает, только если приложение запущено с
  # control-портом: `wordcraft --control 7981 <файл>` (или
  # WORDCRAFT_CONTROL_PORT=7981 в окружении запуска). Ключ доступа мост
  # берёт сам из ~/.config/wordcraft/control-key.local-7981 (перечитывает
  # при каждом переподключении, см. docs/control-protocol.md). Если
  # приложение не запущено — mcp-мост при старте падает, pi-mcp-extension
  # ретраит (maxRetries) и tools недоступны; это ожидаемо, поднимать окно —
  # задача пользователя/сессии, не юнита.
  programs.pi.mcp.mcpServers.wordcraft = {
    command = "wordcraft-cli";
    args = [
      "mcp"
      "--connect"
      "127.0.0.1:7981"
    ];
    transport = "stdio";
    lifecycle = "eager";
  };

  # Любое окно wordcraft, запущенное из shell-сессии (home-manager
  # sessionVariables — интерактивные шеллы), само поднимает control-сервер
  # на 7981, и mcp-мост подключается к нему без `--control` в командной
  # строке. Если порт уже занят другим окном, приложение пишет в лог
  # "control server failed to bind … Address already in use" и работает
  # дальше без control-сервера — проверено, не падает; первое окно держит
  # порт, мост подключается к нему. В окно, запущенное не из shell
  # (файловый менеджер, DE-ланчер), переменная не приезжает — там нужен
  # явный --control.
  home.sessionVariables.WORDCRAFT_CONTROL_PORT = "7981";
  #
  # Адрес модели оставлен общим для обоих хостов (http://localhost:8080/v1 в
  # дефолте модуля) — по просьбе пользователя. Проверено: strata на сервере
  # слушает 127.0.0.1:8080, а не 0.0.0.0, так что по LAN он недоступен, и
  # локально на 8080 на ноутбуке сейчас никого нет (local-inference —
  # сервер-only). Чтобы localhost:8080 работал и на ноутбуке, не меняя конфиг,
  # нужен туннель (тот же приём, что с hermes-панелью на 9119):
  #   ssh -N -L 8080:127.0.0.1:8080 server
  # Без него pi на ноутбуке стартует и всё прочитает, но первый же запрос
  # упрётся в connection refused. Альтернатива — переопределить здесь
  # programs.pi.models.providers.strata.baseUrl на свой локальный движок.
}
