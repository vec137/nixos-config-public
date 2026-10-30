# ПЛЕЙСХОЛДЕР — ЗАПОЛНИТЬ ПЕРЕД УСТАНОВКОЙ.
#
# Этот файл написан руками, чтобы конфигурация вообще собиралась до того, как
# машина существует. На самой машине (загрузившись с установочного образа,
# после disko и монтирования в /mnt) заменить его сгенерированным:
#
#   nixos-generate-config --no-filesystems --root /mnt
#   # затем скопировать /mnt/etc/nixos/hardware-configuration.nix сюда
#
# --no-filesystems обязателен: fileSystems и swapDevices целиком формирует
# disko из hosts/forge/disk-config.nix, и второй набор определений с ним
# конфликтует.
#
# Что генератор точно поправит: список модулей initrd под реальный контроллер
# дисков и строку kvm-intel/kvm-amd под реальный CPU. Последнее важно: без
# правильного модуля не заведётся ни libvirt, ни вложенная виртуализация.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Набор «на все случаи» для обычной десктопной платы: SATA (ahci), USB и
  # NVMe. Лишние модули в initrd безвредны, не хватающего — фатально.
  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "ehci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sr_mod"
    "nvme"
  ];
  boot.initrd.kernelModules = [ ];

  # ЗАПОЛНИТЬ: "kvm-intel" или "kvm-amd" по факту. Оставлены оба намеренно —
  # отсутствующий модуль просто не загрузится (в журнале будет одна строка
  # про не найденный модуль), а забытый означал бы машину без аппаратной
  # виртуализации, то есть без смысла.
  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # fileSystems и swapDevices НЕ описываются здесь — их формирует disko.

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # Микрокод обоих вендоров: ставится тот, что подойдёт, второй не мешает.
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;
}
