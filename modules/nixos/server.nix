{ lib, pkgs, ... }:
{
  # Общее для любого headless-хоста: то, что верно независимо от железа.
  # Железо, загрузчик, GPU, гипервизор и монтирование дисков — в
  # hosts/<name>/default.nix.
  #
  # Дополняет, а не заменяет modules/nixos/common.nix (кеши, локаль, doas,
  # базовая учётка nix) — оба подключаются к хосту.

  # SSH — единственный способ попасть на эту машину, поэтому он не опция.
  #
  # Тонкость, на которой уже споткнулся hosts/laptop/default.nix: `enable`
  # НЕ является полем services.openssh.settings. settings — freeform-набор,
  # который дословно рендерится в sshd_config, поэтому `settings.enable = true`
  # не включает сервис (он остаётся выключенным), а превращается в мусорную
  # строку конфига. Включать нужно именно services.openssh.enable уровнем выше.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      # Держать соединение живым и не копить зависшие сессии: если ноутбук
      # закрыли/ушёл в сон посреди длинной задачи, сервер это заметит сам.
      ClientAliveInterval = 60;
      ClientAliveCountMax = 5;
    };
    # UseDns = false по умолчанию; обратный DNS для домашней сети обычно не
    # настроен, и его ожидание добавляет паузу к каждому входу.
  };

  # В отличие от ноутбука (networking.firewall.enable = false — сознательный
  # выбор для машины, которая ходит по чужим сетям) здесь фаервол включён.
  # Порты, кроме 22, открываются точечно в hosts/<name>/default.nix.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 7860 ];
  };

  # Машина должна возвращаться в сеть сама, без клавиатуры.
  #
  # Emergency/rescue mode — это интерактивное приглашение на локальной консоли.
  # Если systemd свалится в него (например, из-за сбойного fsck на HDD или
  # исчезнувшего раздела в fstab), headless-хост просто пропадёт из сети до
  # тех пор, пока к нему не подойдут физически или через BMC. Выключение
  # обоих режимов заставляет загрузку идти дальше, а не ждать ответа.
  systemd.enableEmergencyMode = false;

  # Короткий таймаут меню загрузчика: без монитора его всё равно никто не
  # читает, а 5 секунд добавляются к каждой перезагрузке.
  boot.loader.timeout = lib.mkDefault 3;

  # Журнал переживает перезагрузку — на сервере, который работает без
  # присмотра, разбираться приходится постфактум. Потолок, чтобы журнал не
  # съел диск за месяцы аптайма.
  services.journald.extraConfig = ''
    Storage=persistent
    SystemMaxUse=2G
  '';

  # /tmp чистится при загрузке, а не копится. Важнее, чем на десктопе:
  # пайплайн отчётов и импорт .ova оставляют там многогигабайтные файлы.
  boot.tmp.cleanOnBoot = true;

  # Время — из сети. Без этого SSH-ключи, TLS и логи расходятся с реальностью
  # после долгого простоя (на этой машине ещё и RTC делится с Windows, см.
  # time.hardwareClockInLocalTime в hosts/server/default.nix).
  services.timesyncd.enable = true;

  # Оболочка пользователя nix задана как pkgs.fish в modules/nixos/common.nix.
  # Без включения программы на уровне системы fish не получит своих
  # completions/vendor-путей и не будет корректно зарегистрирован как shell.
  programs.fish.enable = true;

  # Минимум, который должен быть под рукой сразу после входа по SSH, ещё до
  # того, как заработает home-manager.
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    htop
    tmux
    doas-sudo-shim # sudo здесь нет (common.nix), но nixos-rebuild --sudo его зовёт
  ];

  # Графики нет — экономим и место, и время сборки.
  services.xserver.enable = false;
  fonts.enableDefaultPackages = lib.mkDefault false;
  documentation.doc.enable = false;
}
