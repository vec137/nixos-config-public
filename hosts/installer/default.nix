{ modulesPath, pkgs, lib, ... }:
{
  # Собственный установочный образ для server.
  #
  # Зачем он, если есть официальный minimal ISO: на плате Tyan S8030 (ASPEED-BMC
  # + дискретная RTX 4070) официальный образ показывает графическое меню GRUB,
  # но при выборе любого пункта уходит в чёрный экран — каждый menuentry там
  # делает `terminal_output console`, а текстовую консоль UEFI на этой плате
  # не видно ни в iKVM, ни на живом VGA-мониторе. Разбор — в
  # docs/install-server.md.
  #
  # Этот образ делает видео ненужным вовсе: ключ уже в authorizedKeys, консоль
  # продублирована в последовательный порт (SOL через BMC), modesetting
  # выключен. Загрузился вслепую — зашёл по ssh.
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # nomodeset  — запрещает ядру перехватывать видео своими DRM-драйверами
  #              (ast, nouveau); именно этот перехват уводит картинку.
  # console=   — ПОСЛЕДНИЙ в списке становится основным: вывод systemd и getty
  #              идут в ttyS0, то есть в SOL. tty0 оставлен первым, чтобы при
  #              живом видео сообщения дублировались и на экран.
  boot.kernelParams = [
    "nomodeset"
    "console=tty0"
    "console=ttyS0,115200n8"
  ];

  # Меню в текстовом режиме с самого начала — не переключается на лету, а
  # значит не ломается ровно там, где ломался официальный образ. Таймаут
  # короткий: смотреть на это меню всё равно, скорее всего, будет некому.
  isoImage.forceTextMode = true;
  boot.loader.timeout = lib.mkForce 5;

  # Ключ ssh/server, тот же, что прописан в hosts/server/default.nix. Публичная
  # половина — её не жалко держать в git. Кладётся и root, и nixos: на
  # установочном образе root нужен для nixos-install, а nixos — это учётка,
  # под которой ISO логинится на консоли.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAypF7YGdE7HjrhUdZB/WSsrvTH4Qaylm4zN6PR3QpE+ server"
  ];
  users.users.nixos.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAypF7YGdE7HjrhUdZB/WSsrvTH4Qaylm4zN6PR3QpE+ server"
  ];

  # Образ и так включает sshd, но PermitRootLogin по умолчанию "yes" при
  # пустом пароле означает «вход невозможен». С ключом — возможен, и пароль
  # root задавать на консоли больше не нужно (а её может быть и не видно).
  services.openssh.settings.PermitRootLogin = "prohibit-password";

  # Проводной интерфейс поднимает NetworkManager, который на установочном
  # образе включён и сам делает DHCP — networking.useDHCP здесь задавать
  # нельзя, модуль NM выставляет его в false и получается конфликт.
  networking.hostName = "installer";

  # Инструменты, которые всё равно понадобятся по ходу установки.
  environment.systemPackages = with pkgs; [
    pciutils
    usbutils
    ethtool
    tmux
    rsync
    git
  ];

  # Сжатие послабее: образ собирается на X390, а не на сервере, и уровень 6
  # по умолчанию тут стоит нескольких лишних минут. На размер влияет слабо.
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";
  isoImage.volumeID = "nixos-installer-server";
}
