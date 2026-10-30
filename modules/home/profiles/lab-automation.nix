{ pkgs, ... }:
{
  # Хостовая часть пайплайна лабораторных работ (~/Stuff/sut/ЗОССС_ЛАБЫ).
  # Всё, что стоит внутри гостевых ВМ (xdotool, wmctrl, wireshark), сюда не
  # относится — оно живёт в самих образах .ova.
  #
  # Второй потребитель этого профиля — скиллы report-craft: их скрипты зовут
  # ровно те же soffice / pdftotext / pdftoppm / pdfinfo / magick / identify.
  # Поэтому он подключён и на forge (2026-10-28), где лаб пока нет, а скиллы
  # есть: без профиля они грузились, но шаг «собрать pdf» и приёмка вёрстки
  # падали (см. docs/repo-notes.md).
  #
  # Сверено со скриптами из _vm_tools/ и с шагами 8-9 порядка выполнения:
  #   up.sh / shot.sh — VBoxManage (из virtualisation.virtualbox.host,
  #                     уровень системы) + magick/identify
  #   cy.sh / cyx.sh  — ssh-клиент (базовая система)
  #   build.sh        — nodejs/npm, пакет `docx` ставится локально через
  #                     `npm install` в каталоге _report_tools/
  #   шаг 9           — soffice (docx -> pdf), pdftotext и pdftoppm
  home.packages = with pkgs; [
    # ImageMagick 7: shot.sh зовёт именно `magick`, а не `convert`.
    # В 6-й версии команды `magick` нет вовсе — пакет imagemagick в nixpkgs
    # это как раз 7.x, отдельный imagemagick6 брать не нужно.
    imagemagick

    # Генератор отчётов на библиотеке docx (npm). Ставится не декларативно,
    # а `npm install` в папке работы — так задумано в самом пайплайне.
    nodejs

    # LibreOffice нужен ровно ради headless-конвертации .docx -> .pdf на
    # шаге 9 (проверка номеров страниц в оглавлении). Вариант -still, а не
    # -fresh: ветка с длинной поддержкой, меньше риск, что очередное
    # обновление поменяет разбиение на страницы и собьёт выверенный ENTRIES.
    libreoffice-still

    # pdftotext -layout и pdftoppm — обе утилиты из одного пакета.
    poppler-utils

    # Забрать готовый .docx на ноутбук (или, наоборот, залить материалы).
    rsync

    # 7z: распаковка/пересборка образов и архивов раздатки. Нужен именно
    # p7zip, а не unzip: `unzip` не читает ISO/UDF и спотыкается о «zip bomb»
    # на вложенных архивах (ложная тревога инно-сетовского зипа), а инсталляторы
    # курсов лежат и в .zip, и в .iso. На server 7z приезжал недекларативно
    # (nix-shell), поэтому в профиле его не было, и на forge он просто
    # отсутствовал.
    p7zip

    # xorriso (`-as mkisofs`) — пересборка маленьких загрузочных/раздаточных
    # образов (gacd.iso, surg.iso, fgsetup.iso) и починка регистра имён в
    # перепаканных ISO. Тот же случай: на server им пользовались через
    # nix-shell, в профиле его не было.
    libisoburn
  ];
}
