{ lib, ... }:
let
  # --- Сеть cloudrix: /32 + шлюз вне подсети, DHCP нет ----------------------
  # В панели адрес выдан с маской 255.255.255.255, а шлюз — 10.0.0.1, то есть
  # вне этой «подсети» и вообще в приватном диапазоне. Переключатель
  # «IP address add type» стоит на No automation: хостер ничего в ОС не
  # прописывает и DHCP-сервера не держит. Отсюда два следствия:
  #   * адрес задаётся только статикой;
  #   * шлюз объявляется on-link (GatewayOnLink), иначе ядро откажется
  #     ставить маршрут «via 10.0.0.1»: при маске /32 этот адрес недостижим.
  #
  # Один и тот же блок нужен ДВАЖДЫ — в stage 2 и в initrd. Без initrd-части
  # не работают ни break-glass SSH, ни Clevis: 2026-10-05 первая установка
  # загрузилась в промпт LUKS и оказалась недоступна по сети вообще (ping и
  # любой порт — «no route to host»), хотя сам initrd собран верно.
  # Установка при этом проходит и ни на что не жалуется: kexec-установщик
  # DHCP не запрашивает, а копирует адреса и маршруты у исходного Debian
  # (nixos-images, kexec-run.sh сохраняет `ip --json addr`/`route` и
  # доупаковывает их в initrd). То есть рабочая сеть во время установки
  # ничего не говорит о наличии DHCP у хостера — проверять надо панель.
  wan = {
    # Матчим по типу, а не по имени: у хостера интерфейс ens3, но привязка к
    # имени сломается, если udev назовёт его иначе. NIC здесь ровно один.
    matchConfig.Type = "ether";
    address = [ "203.0.113.10/32" ];
    routes = [
      {
        Gateway = "10.0.0.1";
        GatewayOnLink = true;
      }
    ];
    dns = [
      "77.88.8.8"
      "1.1.1.1"
    ];
    # base.nix ставит DHCP=yes — разумный дефолт для других хостеров. Здесь
    # его надо выключить: несуществующий DHCP-сервер заставит
    # systemd-networkd-wait-online впустую ждать таймаут, а в initrd это
    # прямо задержит разблокировку Clevis.
    networkConfig.DHCP = lib.mkForce "no";
  };
in
{
  # RU-VPS (cloudrix.ru, ~1 ГБ RAM): self-steal Reality на своём домене,
  # приманка FileBrowser, xray portal — российское напрямую, остальное через
  # обратный туннель на nl-exit. Origin для CDN serverspace.
  imports = [
    ../../modules/nixos/vpn/base.nix
    ../../modules/nixos/vpn/portal.nix
    ../../modules/nixos/vpn/tang-relay.nix
    ../../modules/nixos/vpn/subscription.nix
  ];

  # Нейтральное системное имя (скрытность, угроза B: беглый осмотр / не-root
  # шелл). Имя хоста во флейке, ssh-конфиге и sops остаётся ru-edge — меняется
  # ТОЛЬКО networking.hostName. ВНИМАНИЕ: от него зависит имя JWE-файла Clevis
  # (secrets/clevis/${hostName}.jwe → cloud01.jwe), см. base.nix.
  networking.hostName = "cloud01";

  networking.useDHCP = false;
  systemd.network.networks."10-wan" = wan;
  boot.initrd.systemd.network.networks."10-wan" = wan;

  # disko.devices.disk.main.device = "/dev/sda"; # если не virtio-blk
}
