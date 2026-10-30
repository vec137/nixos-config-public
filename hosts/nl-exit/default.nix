{ lib, ... }:
let
  # Сеть NL (waicore): в панели адрес выдан с маской /32, шлюз 172.31.1.1 вне
  # этой «подсети» — как на ru-edge, см. подробный комментарий в
  # hosts/ru-edge/default.nix. Шлюз надо объявлять on-link, иначе ядро не
  # поставит маршрут. Статика нужна в stage 2 И в initrd (иначе break-glass
  # SSH и Clevis недоступны). Если у хостера есть DHCP, статика ему не мешает.
  wan = {
    matchConfig.Type = "ether";
    address = [ "203.0.113.20/32" ];
    routes = [
      {
        Gateway = "172.31.1.1";
        GatewayOnLink = true;
      }
    ];
    dns = [
      "1.1.1.1"
      "9.9.9.9"
    ];
    networkConfig.DHCP = lib.mkForce "no";
  };
in
{
  # NL-VPS (waicore, 2 ГБ RAM, 15 ГБ): xray bridge — сам держит обратный
  # туннель к ru-edge и выпускает через себя зарубежный трафик. Входящих
  # портов нет, кроме SSH.
  imports = [
    ../../modules/nixos/vpn/base.nix
    ../../modules/nixos/vpn/bridge.nix
  ];

  # Нейтральное системное имя (см. hosts/ru-edge/default.nix). Clevis-JWE →
  # secrets/clevis/cloud02.jwe.
  networking.hostName = "cloud02";

  networking.useDHCP = false;
  systemd.network.networks."10-wan" = wan;
  boot.initrd.systemd.network.networks."10-wan" = wan;

  # disko.devices.disk.main.device = "/dev/sda";
}
