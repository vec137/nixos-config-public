# Disko-описание диска, на который ставится NixOS.
#
# ВАЖНО: disko при установке безусловно затирает каждый диск, который здесь
# описан. Диск передаётся аргументом из flake.nix (_module.args.disks), и путь
# указывается из /dev/disk/by-id/, а не /dev/sda — имена sda/sdb/nvme0n1
# присваиваются в порядке инициализации контроллеров и между загрузками могут
# поменяться местами. Посмотреть реальные пути на машине:
#   ls -l /dev/disk/by-id/ | grep -v part
{ disks ? [ ], ... }:
{
  disko.devices.disk.nixos = {
    type = "disk";
    device = builtins.elemAt disks 0;
    content = {
      type = "gpt";
      # priority задаёт порядок создания разделов: без него disko идёт по
      # именам в алфавитном порядке, и root с size = "100%" съел бы всё место
      # раньше, чем дойдёт очередь до swap.
      partitions = {
        # 1 МБ без файловой системы — служебный раздел для GRUB в legacy/BIOS
        # режиме (туда кладётся вторая стадия загрузчика; на MBR-дисках она
        # жила в зазоре после таблицы разделов, на GPT зазора нет).
        #
        # Зачем он на машине, которая, скорее всего, грузится по UEFI:
        # материнская плата старая и её режим заранее неизвестен, а стоит
        # раздел 1 МБ и не требует ничего, кроме себя. Если окажется, что
        # UEFI нет — достаточно поменять boot.loader.grub в
        # hosts/forge/default.nix, переразметка не нужна.
        boot = {
          priority = 1;
          size = "1M";
          type = "EF02";
        };
        ESP = {
          priority = 2;
          # 1 ГБ с запасом: systemd-boot держал бы в ESP сами ядра, GRUB —
          # только себя, но место под несколько поколений всё равно полезно.
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        swap = {
          priority = 3;
          # Страховка от OOM, а не рабочий уровень памяти: на хосте с ВМ уход
          # гостя в swap означает не «медленнее», а фактическую остановку.
          # zram сознательно не включается — он отнимает ту самую RAM, под
          # которую нарезаются виртуалки.
          size = "16G";
          content = {
            type = "swap";
            discardPolicy = "both";
          };
        };
        root = {
          priority = 4;
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "defaults" ];
          };
        };
      };
    };
  };

  # Образы виртуалок живут в /var/lib/libvirt/images, то есть на этом же
  # корне. Если под них поставят отдельный диск — его НЕ надо вносить сюда
  # (disko его затрёт при следующей установке), а подключать обычной записью
  # fileSystems в hosts/forge/default.nix с обязательным nofail:
  #
  #   fileSystems."/var/lib/libvirt/images" = {
  #     device = "/dev/disk/by-uuid/XXXXXXXX-...";
  #     fsType = "ext4";
  #     options = [ "nofail" "x-systemd.device-timeout=10s" ];
  #   };
  #
  # Без nofail отвалившийся диск уронил бы загрузку в emergency mode, а он на
  # headless-хостах выключен (modules/nixos/server.nix) — машина просто не
  # появится в сети.
}
