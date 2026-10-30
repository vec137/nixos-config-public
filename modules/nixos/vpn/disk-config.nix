{ lib, ... }:
let
  s = import ./settings.nix;
in
{
  # Разметка для nixos-anywhere (disko форматирует диск ЦЕЛИКОМ).
  # GPT с разделом bios_boot (EF02) и ESP одновременно — GRUB встаёт и на
  # SeaBIOS, и на UEFI (см. boot.loader.grub в base.nix). Без swap-раздела:
  # своп — zram.
  #
  # Корень зашифрован LUKS2 (скрытность, угроза A: офлайн-изъятие/снапшот
  # выключенной ВМ/списанный диск). /boot НЕ шифруется — GRUB должен его
  # прочитать; там только ядро+initrd, секретов нет (initrd-секреты
  # доупаковываются на активации, но и это лежит на /boot — потому хост-ключ
  # initrd одноразово-незначимый, а не рабочий, см. base.nix).
  #
  # Имя устройства — обычно /dev/vda (virtio-blk), у части хостеров /dev/sda
  # (virtio-scsi). Проверить перед установкой (`lsblk` на Debian) и при
  # необходимости переопределить в hosts/<h>/default.nix.
  disko.devices.disk.main = {
    type = "disk";
    device = lib.mkDefault "/dev/vda";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";
        };
        esp = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "luks";
            name = s.luksName; # /dev/mapper/${luksName}
            # TRIM сквозь LUKS: на SSD/NVMe у хостера иначе диск не узнает о
            # свободных блоках и производительность/износ страдают. Это чуть
            # ослабляет сокрытие объёма использования — для нашей модели
            # (у хостера и так гипервизор) приемлемо.
            settings.allowDiscards = true;
            # Два НЕЗАВИСИМЫХ слота LUKS, оба заводятся при установке. Файлы
            # существуют только на инсталляторе (nixos-anywhere
            # --disk-encryption-keys <путь> <локальный-файл>, флаг повторяемый);
            # в store/git НЕ попадают, на сборку toplevel не влияют (нужны лишь
            # на этапе disko-create). Разделение развязывает ротацию: сменить
            # одно, не трогая другое.
            #
            #   Слот 0 (passwordFile) — ФРАЗА для break-glass. Её вводят руками
            #   в initrd (копипастой из KeePass), когда дом/Tang недоступны.
            passwordFile = "/tmp/luks.key";
            #   Слот 1 (additionalKeyFiles) — СЛУЧАЙНЫЙ ключ для Clevis/Tang.
            #   Именно его содержимое заворачивается в JWE (secrets/clevis/*.jwe)
            #   и подаётся cryptsetup при авто-разблокировке. Руками не вводится
            #   никогда, высокой энтропии. disko делает им `cryptsetup luksAddKey`.
            additionalKeyFiles = [ "/tmp/luks-clevis.key" ];
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
