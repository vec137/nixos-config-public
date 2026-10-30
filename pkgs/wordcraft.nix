# WordCraft — открытый текстовый процессор (чистая комната по спецификациям
# MS Word), репозиторий — в meta.homepage.
#
# Почему бинарный пакет, а не сборка из исходников:
#   * апстрим НЕ содержит ни flake.nix, ни nix/ — есть только CI-джоб «nix
#     flake check», который тихо скипается, когда flake.nix отсутствует. То
#     есть готового выражения upstream нет;
#   * из исходников это огромное Rust-пространство (egui/wgpu/vello, ~1000
#     крейтов, две git-зависимости craft-libs на разных rev) — минут 30+
#     компиляции на каждой пересборке; релизные ассеты апстрима (AppImage,
#     .deb/.rpm, tar.gz) закрывают задачу без компиляции вообще;
#   * rust-version у workspace = 1.95, ровно та версия rustc, что сейчас в
#     закреплённом nixpkgs, так что исходная сборка возможна — но это
#     отдельная работа (cargoHash + два fetchgit на craft-libs), не здесь.
#
# Что берём из релиза: wordcraft-<ver>-linux-<arch>.tar.gz — это FHS-дерево
# (bin/wordcraft, bin/wordcraft-cli, share/{applications,icons,metainfo,mime,doc})
# из packaging/linux/package.sh. Бинарники собраны на Ubuntu 22.04 (glibc
# 2.35), динамят только libc/libm/libgcc, а всё остальное (wayland, X11,
# xkbcommon, vulkan/GL, dbus) грузится dlopen() по имени — поэтому нужен
# autoPatchelfHook: он ставит интерпретатор из nixpkgs (на NixOS нет
# /lib64/ld-linux-x86-64.so.2, если не включён nix-ld) и rpath по DT_NEEDED.
#
# Хэши брать из SHA256SUMS.txt соответствующего релиза (это апстримовый
# checksum-файл, он же сверяется с digest'ом ассета из GitHub API):
#   curl -fsSL https://github.com/storytold/wordcraft/releases/download/v<ver>/SHA256SUMS.txt
# hex → SRI:  nix hash convert --hash-algo sha256 --to sri <hex>
# При обновлении: поменять version, подставить lib.fakeHash и взять
# настоящий из ошибки; для новых архитектур — хэш из SHA256SUMS.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  dbus,
  libgcc,
  libglvnd,
  libx11,
  libxcursor,
  libxi,
  libxkbcommon,
  libxcb,
  vulkan-loader,
  wayland,
}:

let
  version = "0.8.0";

  # x86_64 / aarch64 / riscv64 — имена апстримных ассетов совпадают с
  # parsed.cpu.name.
  arch = stdenv.hostPlatform.parsed.cpu.name;

  hashes = {
    "x86_64-linux" = "sha256-Ds4Hzz2RuSPf2A+QMQ4EmDveZvAnnGtg3c6JWW3eDd8=";
    "aarch64-linux" = "sha256-qGLeIlbkPJh9yOoAm6Uqwl2zQJH9ZJtmYTOTGsaOAsw=";
    "riscv64-linux" = "sha256-/U1fyW/addKEDyvVo6Qfjl9PMPMGoF0/SYbplaAY3ms=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "wordcraft";
  inherit version;

  src = fetchurl {
    url = "https://github.com/storytold/wordcraft/releases/download/v${version}/wordcraft-${version}-linux-${arch}.tar.gz";
    hash =
      hashes.${stdenv.hostPlatform.system}
        or (throw "wordcraft: нет прекомпилированного релиза для ${stdenv.hostPlatform.system}");
  };

  sourceRoot = "wordcraft-${finalAttrs.version}-linux-${arch}";

  # Только фиксинг уже собранных бинарников; ничего не компилируем.
  dontBuild = true;

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];

  # Библиотеки, чьи soname бинарь грузит dlopen() в рантайме: wgpu →
  # libvulkan.so.1 (загрузчик vulkan-loader), libEGL/libGL — диспетчеры
  # libglvnd, а сами драйверы лежат в /run/opengl-driver (в closure их
  # тащить не нужно: mesa сюда — это +1 ГБ вместо +270 МБ). winit →
  # libwayland-*/libxkbcommon(-x11)/libXi/libX11/libXcursor/libxcb,
  # AccessKit → libdbus-1.
  runtimeDeps = [
    dbus
    libglvnd
    libx11
    libxcursor
    libxi
    libxkbcommon
    libxcb
    vulkan-loader
    wayland
  ];

  # libgcc_s.so.1 — единственная из DT_NEEDED, которую не тащит ни одна из
  # runtimeDeps.
  buildInputs = finalAttrs.runtimeDeps ++ [ libgcc ];

  installPhase = ''
    runHook preInstall

    install -d "$out/bin" "$out/share"
    cp -R bin/* "$out/bin/"
    cp -R share/* "$out/share/"

    runHook postInstall
  '';

  # autoPatchelf прописывает интерпретатор и rpath только по DT_NEEDED (тут
  # это libc/libm/libgcc). Остальные библиотеки бинарь грузит dlopen() уже в
  # рантайме — их в DT_NEEDED нет, и rpath под конец fixup всё равно
  # перезаписывает autoPatchelf (он висит на postFixupHooks), поэтому даём
  # их через LD_LIBRARY_PATH: он опрашивается раньше rpath.
  postFixup = ''
    for b in wordcraft wordcraft-cli; do
      wrapProgram "$out/bin/$b" \
        --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib:${lib.makeLibraryPath finalAttrs.runtimeDeps}" \
        --prefix XDG_DATA_DIRS : /run/opengl-driver/share
    done
  '';

  # wordcraft-cli — headless-интерфейс того же движка (конвертация, MCP,
  # управление по control-каналу); GUI-библиотеки ему не нужны, но он
  # патчится и оборачивается так же, поэтому остаётся в $out/bin рядом.
  #
  # Проверка после сборки (самостоятельно, в postFixup не делаем — на cross
  # запуск хостового бинаря упал бы):
  #   ldd result/bin/wordcraft | grep -c 'not found'   → 0
  #   result/bin/wordcraft --version                  → «wordcraft 0.8.0 (rev)»
  #   result/bin/wordcraft-cli --help

  meta = {
    description = "Writing and document design; clean-room reimplementation of Microsoft Word in Rust";
    homepage = "https://github.com/storytold/wordcraft";
    changelog = "https://github.com/storytold/wordcraft/releases/tag/v${finalAttrs.version}";
    downloadPage = "https://github.com/storytold/wordcraft/releases";
    # Двойная лицензия «MIT OR Apache-2.0» (LICENSE-MIT + LICENSE-APACHE в
    # релизном дереве в share/doc/wordcraft); для meta берём ASL2.0, как
    # принято для dual MIT/Apache в nixpkgs.
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "riscv64-linux"
    ];
    mainProgram = "wordcraft";
  };
})
