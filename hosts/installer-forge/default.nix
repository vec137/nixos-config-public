{ config, lib, pkgs, modulesPath, forgeSystem, forgeDiskoScript, repoSource, ... }:

let
  # Сентинел из flake.nix (_module.args.disks у forge). Диск на момент сборки
  # образа неизвестен — и это правильно, иначе образ был бы одноразовым:
  # собрали «под /dev/sdb», переставили диск, и всё заново. Поэтому
  # сгенерированный disko-скрипт берётся как есть и в нём ровно одна подмена:
  # литерал диска → переменная окружения $DISK, которую подставит install-forge.
  #
  # Почему именно подмена, а не своя разметка на sgdisk: disko — единственный
  # источник истины для разметки (hosts/forge/disk-config.nix), и установленная
  # система монтирует разделы по partlabel (disk-nixos-root и т.п.). Любой
  # рукописный аналог пришлось бы синхронизировать вручную, а расхождение
  # вылезло бы уже при первой загрузке — «не найден корень».
  diskSentinel = "/dev/disk/by-id/CHANGE-ME-forge-disk";

  # Литерал «${DISK}» собран конкатенацией, а не написан в строке: внутри
  # ''…''-строки Nix съел бы ${...} как интерполяцию, а экранирование (''${)
  # рядом с шелловскими кавычками читается отвратительно.
  diskVar = "$" + "{DISK}";

  # Подстановка БЕЗ кавычек: в disko-скрипте литерал диска встречается и
  # внутри кавычек (`sgdisk --clear "<диск>"`), и без них (`device=<диск>`,
  # `for dev in <диск>;`). Голое ${DISK} корректно в обоих случаях, а вариант
  # с кавычками дал бы ""${DISK}"" там, где кавычки уже есть.
  diskoRuntime = pkgs.runCommand "disko-forge-runtime" { } ''
    substitute ${forgeDiskoScript} $out \
      --replace-fail '${diskSentinel}' '${diskVar}'
    chmod +x $out
  '';

  # Сам установщик. writeShellApplication, а не writeShellScriptBin: он
  # проверяет скрипт через shellcheck при сборке образа — ошибку в кавычках
  # лучше поймать здесь, чем на машине без сети.
  installForge = pkgs.writeShellApplication {
    name = "install-forge";
    runtimeInputs = with pkgs; [ util-linux coreutils gnugrep ];
    text = ''
      set -euo pipefail

      usage() {
        cat <<'EOF'
      install-forge — установка системы forge с этого образа.

        install-forge <диск> [файл-хостового-ключа]

      <диск>  — ЦЕЛЬ УСТАНОВКИ, будет стёрта полностью.
                Указывать путь из /dev/disk/by-id/ (устойчив к перестановке
                дисков), а не /dev/sda.
      ключ    — необязательно: ssh/forge_host_ed25519_key с ноутбука (на
                флешке). Нужен только для sops; без него система встанет и
                загрузится, но без туннеля (secretsReady в
                hosts/forge/default.nix).

      Что скрипт делает: размечает диск так же, как disko в конфигурации,
      ставит ВШИТУЮ в этот образ систему (ничего не скачивается), кладёт
      копию репозитория в /home/nix/.nix и спрашивает пароль для nix.

      Посмотреть диски:  lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,LABEL
                         ls -l /dev/disk/by-id/ | grep -v part
      EOF
      }

      if [ "$#" -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        usage
        exit 1
      fi

      if [ "$(id -u)" -ne 0 ]; then
        echo "нужен root: sudo install-forge $*" >&2
        exit 1
      fi

      DISK="$1"
      HOSTKEY="''${2:-}"

      if [ ! -b "$DISK" ]; then
        echo "ОШИБКА: $DISK — не блочное устройство" >&2
        exit 1
      fi

      # Диск, с которого загружен сам образ, затирать нельзя — это было бы
      # обрывом ветки под собой (и типичная ошибка: флешка часто /dev/sda).
      ISO_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
      echo "Загружено с: ''${ISO_SRC:-(неизвестно)}"

      echo
      echo "=============================================================="
      echo " ЦЕЛЬ УСТАНОВКИ: $DISK"
      echo "=============================================================="
      lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,LABEL,MOUNTPOINT "$DISK" || true
      echo
      echo "ВСЁ, ЧТО НА ЭТОМ ДИСКЕ, БУДЕТ УНИЧТОЖЕНО."
      echo "Если выше видны разделы с данными (ntfs, метки вроде HDD/WINDOWS) —"
      echo "это НЕ тот диск. Прервать: Ctrl-C."
      echo
      # Слово подтверждения ЛАТИНИЦЕЙ намеренно: раскладка на консоли
      # установщика — US, и кириллицу там просто не набрать.
      printf 'Чтобы продолжить, введите ERASE: '
      read -r answer
      if [ "$answer" != "ERASE" ]; then
        echo "отменено"
        exit 1
      fi

      echo "== разметка (disko) =="
      export DISK
      ${diskoRuntime}

      echo "== установка вшитой системы =="
      # --system: ставится готовое замыкание из store этого образа, то есть
      # сборка и сеть не нужны вовсе. --no-root-password: пароль root не
      # спрашиваем (вход root по SSH запрещён, на консоли хватает nix+doas).
      nixos-install --system ${forgeSystem} --no-root-password --no-channel-copy

      echo "== копия репозитория в /home/nix/.nix =="
      # Чтобы на машине было чем пересобираться. Это копия исходников флейка
      # (без .git — приватные ssh/, xray/, misc/ в неё и так не входят), так
      # что `nixos-rebuild --flake /home/nix/.nix#forge` работает сразу, а
      # полноценный git clone можно сделать потом, когда будет сеть.
      mkdir -p /mnt/home/nix
      cp -a /iso/nixcfg /mnt/home/nix/.nix
      chmod -R u+w /mnt/home/nix/.nix
      nixos-enter --root /mnt -c 'chown -R nix:users /home/nix' || true

      if [ -n "$HOSTKEY" ]; then
        if [ -r "$HOSTKEY" ]; then
          echo "== хостовый ключ =="
          install -d -m 0755 /mnt/etc/ssh
          install -m 0600 "$HOSTKEY" /mnt/etc/ssh/ssh_host_ed25519_key
          if [ -r "$HOSTKEY.pub" ]; then
            install -m 0644 "$HOSTKEY.pub" /mnt/etc/ssh/ssh_host_ed25519_key.pub
          fi
        else
          echo "ВНИМАНИЕ: $HOSTKEY не читается, ключ не установлен" >&2
        fi
      fi

      echo "== пароль пользователя nix =="
      # Без пароля первый doas на машине не пройдёт, а значит не выйдет и
      # пересобрать систему. Вход по SSH всё равно только по ключу.
      nixos-enter --root /mnt -c 'passwd nix'

      cat <<'EOF'

      Готово. Дальше:
        1. reboot, вынуть флешку;
        2. вход на консоли как nix (или по ssh, если сеть есть);
        3. проверить гипервизоры:  hv status
        4. когда понадобится туннель: на ноутбуке `sops updatekeys
           secrets/common.yaml`, положить хостовый ключ в /etc/ssh (если ещё
           не положен), поменять secretsReady на true в
           hosts/forge/default.nix и `rebuild-switch`.
      Подробности — docs/install-forge.md в /home/nix/.nix.
      EOF
    '';
  };
in
{
  # Самодостаточный установочный образ для forge.
  #
  # Чем отличается от hosts/installer/ (образ для основного сервера): тот —
  # обычный минимальный установщик, который ставит систему, собирая её на
  # месте или получая по сети. Здесь ни сети, ни SSH с ноутбука не
  # предполагается, поэтому в образ вшито ГОТОВОЕ замыкание системы forge
  # (isoImage.storeContents ниже) плюс скрипт install-forge. Загрузился с
  # флешки — ввёл одну команду — получил установленную систему.
  #
  # Цена: образ весит столько же, сколько система (единицы гигабайт), и
  # пересобирать его надо после каждой правки конфигурации forge. Для
  # одноразовой установки это ровно тот обмен, который нужен.
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  networking.hostName = "installer-forge";

  # Вшиваем в store образа само замыкание системы и disko-скрипт. Без этого
  # nixos-install --system не нашёл бы путей и полез бы в сеть.
  isoImage.storeContents = [ forgeSystem diskoRuntime ];

  # Исходники репозитория — обычными файлами на ISO (/iso/nixcfg после
  # загрузки): их копирует install-forge в /home/nix/.nix, чтобы машине было
  # чем пересобираться. Это источник флейка, то есть только git-отслеживаемые
  # файлы: приватные ssh/, xray/, misc/ в него не попадают по .gitignore.
  isoImage.contents = [
    {
      source = repoSource;
      target = "/nixcfg";
    }
  ];

  # Автологин root вместо штатного nixos: установщику всё равно нужен root, а
  # лишний `sudo -i` на консоли без SSH — лишний шаг.
  services.getty.autologinUser = lib.mkForce "root";

  # Шрифт консоли с кириллицей. Дефолтный (Lat2-Terminus16) её не содержит, и
  # вся русская подсказка/вывод install-forge выглядели бы на реальном мониторе
  # набором знаков вопроса — а на этой машине консоль единственный интерфейс.
  # Раскладка остаётся US (console.keyMap не меняем): кириллицу вводить нигде
  # не требуется, слово подтверждения в install-forge — латиницей.
  console.font = "latarcyrheb-sun16";

  # Короткая инструкция прямо на экране входа — чтобы не держать команды в
  # голове и не искать документацию на машине, где ещё нет системы.
  services.getty.helpLine = lib.mkForce ''

    Установочный образ forge. Система уже внутри образа, сеть не нужна.

      lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,LABEL   # найти диск
      ls -l /dev/disk/by-id/ | grep -v part          # его устойчивый путь
      install-forge /dev/disk/by-id/<диск>           # установка (диск будет стёрт!)

    install-forge --help — подробности. Документация: /iso/nixcfg/docs/install-forge.md
  '';

  environment.systemPackages = [
    installForge
  ] ++ (with pkgs; [
    pciutils
    usbutils
    ethtool
    tmux
    rsync
    git
    gptfdisk
    parted
    dosfstools
    e2fsprogs
  ]);

  # sshd с ключом ноутбука — на случай, если сеть всё-таки окажется: тогда
  # установку можно вести из удобного терминала, а не с консоли. Если сети
  # нет, это просто неиспользуемый сервис.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAypF7YGdE7HjrhUdZB/WSsrvTH4Qaylm4zN6PR3QpE+ server"
  ];
  users.users.nixos.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAypF7YGdE7HjrhUdZB/WSsrvTH4Qaylm4zN6PR3QpE+ server"
  ];
  services.openssh.settings.PermitRootLogin = "prohibit-password";

  # Сжатие: zstd уровня 3, как в hosts/installer. На многогигабайтном store
  # разница между 3 и 6 — это десятки минут сборки против процентов размера;
  # образ всё равно пишется на флешку, а не раздаётся по интернету.
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";
  isoImage.volumeID = "nixos-installer-forge";

  # Это установочная среда, а не система: версия здесь нужна лишь формально.
  system.stateVersion = "26.05";
}
