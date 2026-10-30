{ pkgs, ... }:
let
  # Локальный инференс: llama.cpp с поддержкой CUDA под RTX 4070.
  #
  # Берётся из pkgs-unstable, а не из базового стабильного nixpkgs,
  # намеренно. llama.cpp движется очень быстро, и рабочая конфигурация с этой
  # машины (см. ~/Stuff/server/CLAUDE.md) опирается на флаги, которых в
  # стабильной ветке может ещё не быть:
  #   --spec-type draft-mtp / --spec-draft-n-max   (MTP как спекулятивное декодирование)
  #   --load-mode none                              (пришёл на смену --no-mmap/--mlock)
  #   --n-cpu-moe                                   (частичная выгрузка экспертов MoE на CPU)
  # Это тот самый случай, под который в flake.nix заведён overlay-bleeding:
  # сначала pkgs-unstable, и только потом — переопределение конкретного пакета.
  #
  # Собирается с CUDA. Кеш cuda-maintainers.cachix.org подключён в
  # hosts/server/default.nix; если по какой-то ревизии случится промах,
  # локальная сборка CUDA-стека занимает часы — тогда проще временно
  # закомментировать эту строку и взять готовый бинарник с GitHub Releases
  # llama.cpp (для него уже включён programs.nix-ld, см. тот же default.nix,
  # без него непропатченный ELF на NixOS вообще не запустится).
  llama-cpp-cuda = (pkgs.pkgs-unstable.llama-cpp.override {
      cudaSupport = true;
      # tools/ui (веб-морда) собирается через npm, и пакет по умолчанию тянет
      # для этого nodejs_latest — на момент правки это nodejs_26, самая
      # свежая и потому наименее востребованная ветка: у неё почти нет
      # потребителей в остальном nixpkgs, кеш cache.nixos.org промахивается,
      # и сборка идёт с нуля (замечено: ~50 минут на сам nodejs), а тесты
      # именно этой веб-морде не нужны вообще — нам нужен просто рабочий
      # `node` для одного `npm run build`. Подменяем на обычный `nodejs`
      # (алиас на nodejs_24, LTS) — тот собирает почти весь остальной
      # nixpkgs и почти наверняка уже лежит в кеше готовым бинарником.
      nodejs_latest = pkgs.pkgs-unstable.nodejs;
    }).overrideAttrs (old: {
      # По умолчанию nixpkgs собирает ядра ggml-cuda сразу под девять
      # архитектур (75;80;86;89;90;100;103;120;121) — nvcc компилирует одни и
      # те же тяжёлые .cu-файлы по разу на каждую, и это основная часть времени
      # сборки. Кеш cuda-maintainers по этой ревизии всё равно промахивается
      # (проверено: деривация попадает в список «will be built»), то есть
      # собирать придётся локально в любом случае, и сужать список — чистый
      # выигрыш, примерно втрое.
      #
      # Оставлены ровно те, что имеют отношение к этой машине:
      #   89 — Ada, стоящая сейчас RTX 4070
      #   86 — Ampere, на случай RTX 3080
      #   75 — Turing, на случай RTX 2080 Ti
      # Если появится карта другого поколения — дописать её compute capability
      # сюда, иначе llama.cpp её не увидит и молча уйдёт считать на CPU.
      #
      # Флаг именно дописывается в конец: CMake при повторном -D с тем же
      # именем берёт последнее значение, поэтому наш переопределяет штатный.
      cmakeFlags = old.cmakeFlags ++ [ "-DCMAKE_CUDA_ARCHITECTURES:STRING=75;86;89" ];
    });

  # Форк llama.cpp от PrismML — только ради Bonsai 2 (тернарная квантизация
  # Qwen3.8-27B, https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf).
  # Её GGUF записаны в собственных типах PTQ1_0/PQ2_0, которых в апстримном
  # llama.cpp нет: штатный llama-server такой файл просто не откроет.
  #
  # Берём уже настроенный llama-cpp-cuda (CUDA, nodejs, три архитектуры) и
  # подменяем в нём только исходники. Работает потому, что пакет в nixpkgs
  # написан через finalAttrs: npmDeps и прочее вычисляются от *итогового*
  # src, и подмена src протекает внутрь сама.
  #
  # В home.packages этот пакет НЕ кладётся: бинарники у него называются так же
  # (llama-server, llama-cli, …), и home-manager отказался бы собирать профиль
  # из-за двух файлов на одном пути. Вместо этого лаунчер ниже обращается к
  # нему по полному пути в /nix/store.
  llama-cpp-prism = llama-cpp-cuda.overrideAttrs (old: {
    pname = "llama-cpp-prism";
    version = "prism-b10743";
    src = pkgs.fetchFromGitHub {
      owner = "PrismML-Eng";
      repo = "llama.cpp";
      rev = "adfffbe41b2cabcd51fff326ab045662265062bb"; # тег prism-b10743-adfffbe
      hash = "sha256-SNBAC+dNTwQxpGmKyG7i/8eqCNg6985DXtqGbzWgwFA=";
    };
    # llama-cpp 0.6.0 в nixpkgs (приехал с обновлением flake.lock) черри-пикает
    # апстримный коммит 07ccce23 — одну строку в tests/test-llama-archs.cpp.
    # Дерево форка отстаёт от апстрима, ханк не попадает в контекст, и сборка
    # падает в patchPhase («1 out of 1 hunk FAILED»). Патч чинит апстримный
    # тест, а не библиотеку, поэтому здесь список патчей просто обнуляется —
    # унаследованные от апстрима патчи к чужому дереву вообще не применимы.
    patches = [ ];
    # Та же версия 0.6.0 впервые включила doCheck (до неё в nixpkgs стояло
    # doCheck = false, то есть тесты у форка никогда и не собирались). Вернуть
    # их нельзя: без 07ccce23 тот самый test-llama-archs падает — при
    # GGML_BACKEND_DL=ON, который nixpkgs включает, бэкенды нужно
    # инициализировать явно, а в форке этой строки тоже нет. Гонять апстримный
    # набор тестов по чужому дереву смысла мало: он проверяет апстрим, а
    # ломаться будет у нас. Заодно LLAMA_BUILD_TESTS уходит в FALSE и сборка
    # становится заметно короче. Если когда-нибудь понадобится вернуть —
    # нужен свой postPatch, дописывающий llama_backend_init() после
    # common_init() в tests/test-llama-archs.cpp.
    doCheck = false;
    # Зависимости веб-морды (tools/ui) — свои, не апстримные. До 0.6.0
    # package-lock.json форка совпадал с апстримным байт в байт и здесь стоял
    # `inherit (llama-cpp-cuda) npmDeps;`, но в 0.6.0 апстрим поднял
    # tailwind-variants 3.2.2 → 3.3.1, и `npm ci` в офлайн-сборке больше не
    # нашёл бы нужный тарбол. Хеш считается по lock-файлу:
    #   nix run nixpkgs#prefetch-npm-deps -- tools/ui/package-lock.json
    # (сам npmDeps пакет собирает из finalAttrs.src/patches, то есть из наших).
    npmDepsHash = "sha256-2Q7XhaLAArmviOLdQsNbYTfdyDE5pW9lR26cRHEVl9k=";
    # Номер сборки в nixpkgs захардкожен в let (номер апстрима) и через
    # overrideAttrs не меняется; дописываем свой -D — CMake берёт последний.
    # Иначе `--version` врал бы, что это апстримная сборка.
    cmakeFlags = old.cmakeFlags ++ [
      "-DLLAMA_BUILD_NUMBER:STRING=10743"
      "-DLLAMA_BUILD_COMMIT:STRING=adfffbe"
    ];
    meta = old.meta // { homepage = "https://github.com/PrismML-Eng/llama.cpp"; };
  });

  # Лаунчер Bonsai 2 — аналог ~/serve.sh для qwen, но под контролем Nix.
  # writeShellApplication кладёт runtimeInputs в PATH скрипта (поэтому внутри
  # `llama-server` — именно форк, а не llama-cpp-cuda из профиля), включает
  # `set -euo pipefail` и прогоняет текст через shellcheck на этапе сборки.
  # Сам скрипт лежит рядом в bonsai-serve.sh; спереди дописывается путь к
  # генератору калибровочного корпуса из исходников форка (он не
  # устанавливается в bin/, но в store лежит вместе с src).
  bonsai-serve = pkgs.writeShellApplication {
    name = "bonsai-serve";
    runtimeInputs = [
      llama-cpp-prism
      pkgs.python314Packages.huggingface-hub
      pkgs.curl
      pkgs.jq
      pkgs.gzip
    ];
    text = ''
      CALIB_CORPUS_SCRIPT=${llama-cpp-prism.src}/tools/kv-mean-center/make-calib-corpus.sh
    '' + builtins.readFile ./bonsai-serve.sh;
  };
in
{
  home.packages = [
    llama-cpp-cuda
    bonsai-serve
    pkgs.nvtopPackages.full
    pkgs.python314Packages.huggingface-hub
  ];

  # Модели лежат вне nix-store: это гигабайты изменяемых данных, скачиваемых
  # вручную с HuggingFace, которым в store делать нечего.
  home.file."models/.keep".text = "";
}
