# Disko-описание ТОЛЬКО для NVMe, на который ставится NixOS.
#
# ВАЖНО, про дуал-бут: disko при установке безусловно затирает каждый диск,
# который здесь описан. Поэтому SSD с Windows и HDD сюда НЕ ВНЕСЕНЫ и не
# должны вноситься никогда — иначе `disko --mode disko` молча снесёт Windows.
# HDD подключается позже обычной записью fileSystems (см. hosts/server/default.nix),
# без участия disko.
#
# Диск передаётся аргументом из flake.nix (_module.args.disks), а не хардкодится,
# чтобы устройство задавалось в одном месте. Указывать путь из /dev/disk/by-id/,
# а не /dev/nvme0n1: имена nvme0n1/nvme1n1 присваиваются в порядке инициализации
# контроллеров и между загрузками могут поменяться местами — на машине с двумя
# NVMe/SSD это ровно тот случай, когда ошибка стоит раздела Windows.
# Посмотреть реальные пути: `ls -l /dev/disk/by-id/ | grep -v part`.
{ disks ? [ ], ... }:
{
  disko.devices.disk.nixos = {
    type = "disk";
    device = builtins.elemAt disks 0;
    content = {
      type = "gpt";
      # priority задаёт порядок создания разделов. Без него disko идёт по именам
      # в алфавитном порядке (ESP, root, swap) и раздел root с size = "100%"
      # съел бы всё место до того, как дойдёт очередь до swap.
      partitions = {
        ESP = {
          priority = 1;
          # Свой отдельный ESP на этом диске, не общий с Windows (у неё свой
          # на её SSD). Так обновление Windows не может затереть загрузчик
          # NixOS, и наоборот. 1 ГБ — с запасом на несколько поколений ядра:
          # systemd-boot держит в ESP сами ядра и initrd.
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
          priority = 2;
          # Небольшой, как страховка от OOM, а не как рабочий уровень памяти:
          # при инференсе уход модели в swap означает не «медленнее», а полную
          # остановку. Отсюда же отсутствие zram (в отличие от ноутбука) —
          # он бы отъедал ту самую RAM, под которую подбираются --n-cpu-moe.
          size = "16G";
          content = {
            type = "swap";
            discardPolicy = "both";
          };
        };
        root = {
          priority = 3;
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
}
