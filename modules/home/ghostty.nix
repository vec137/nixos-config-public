{ config, lib, ... }:
let
  # Сюда noctalia кладёт сгенерированную палитру: её builtin-шаблон "ghostty"
  # (assets/templates/builtin.toml) объявлен как
  #   output_path = $XDG_CONFIG_HOME/ghostty/themes/noctalia
  #   post_hook   = ghostty/apply.sh      (прописать theme + reload)
  #   undo_hook   = ghostty/undo.sh       (убрать theme + удалить файл)
  # Сам шаблон нужно один раз включить в GUI noctalia (Settings → Themes →
  # Templates → Ghostty); декларативно это не задаётся — живой settings.toml
  # редактируется из GUI, а копия в репозитории (noctalia-full-config.toml)
  # только зеркалит его и сеет на новой машине (см. modules/home/noctalia.nix).
  noctaliaTheme = "${config.xdg.configHome}/ghostty/themes/noctalia";
in
{
  # Ghostty — кандидат на замену alacritty (сам alacritty пока остаётся, и
  # хоткей Mod+Return в niri по-прежнему на нём). Что он здесь даёт:
  #   - лигатуры (alacritty их принципиально не умеет);
  #   - полную реализацию kitty graphics protocol, то есть превью картинок
  #     в ranger/yazi/nvim (sixel'а у ghostty нет и не планируется).
  programs.ghostty = {
    enable = true;
    settings = {
      font-family = "JetBrainsMono Nerd Font";
      font-size = 10.5;

      # theme ссылается на файл themes/<имя> в конфиге ghostty, то есть на
      # noctaliaTheme выше. Строку держим здесь намеренно, а не отдаём
      # apply.sh: он сначала грепает конфиг на '^theme\s*=\s*noctalia$' и,
      # найдя её, ничего не пишет. Без неё hook пошёл бы дописывать строку
      # в ~/.config/ghostty/config — а это симлинк в /nix/store, запись
      # упала бы, под `set -e` hook умер бы до reload'а, и noctalia
      # показывала бы ошибку на каждой смене темы.
      theme = "noctalia";

      # Ровно та самая «совместимость», из-за которой про kitty говорят, что
      # с ней проблемы: ghostty тоже ставит свой TERM (xterm-ghostty), и на
      # удалённом хосте такого terminfo обычно нет. ssh-terminfo заставляет
      # shell-интеграцию самой доставить terminfo на хост при первом ssh
      # (кеш — `ghostty +ssh-cache`), ssh-env — фолбэк на xterm-256color,
      # если доставить не удалось. Перечислять остальные фичи не нужно:
      # неупомянутые остаются в дефолте (cursor,no-sudo,title,path).
      shell-integration-features = "ssh-env,ssh-terminfo";
    };
  };

  # Пока шаблон в noctalia не включён, файла темы нет — а ghostty на
  # несуществующую тему отвечает ошибкой и ненулевым кодом. Это ломает не
  # только запуск: модуль home-manager вешает на ~/.config/ghostty/config
  # onChange-проверку `ghostty +validate-config`, и падение проверки валит
  # всю активацию. Поэтому перед линковкой файлов создаём пустую заглушку.
  # Обычный файл, а не xdg.configFile: noctalia перезапишет его записью на
  # месте, а в симлинк на /nix/store записать бы не смогла.
  #
  # entryBetween [...] [...] — это DAG активации home-manager: запись должна
  # пройти после writeBoundary (до него активация обязана быть «чистой», чтобы
  # работал dry-run) и до onFilesChange, где и вызывается validate-config.
  home.activation.ghosttyNoctaliaThemeStub =
    lib.hm.dag.entryBetween [ "onFilesChange" ] [ "writeBoundary" ] ''
      if [ ! -e "${noctaliaTheme}" ]; then
        $DRY_RUN_CMD mkdir -p "${builtins.dirOf noctaliaTheme}"
        $DRY_RUN_CMD touch "${noctaliaTheme}"
      fi
    '';
}
