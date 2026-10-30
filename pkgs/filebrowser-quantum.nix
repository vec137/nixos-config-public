# filebrowser-quantum, поднятый с 1.5.2-stable (версия в nixpkgs на момент
# правки) до 1.5.8-stable. Выражение почти дословно повторяет
# pkgs/by-name/fi/filebrowser-quantum/package.nix из nixpkgs; отличия:
#   * version/hash/vendorHash/npmDepsHash — под 1.5.8-stable;
#   * ldflags указывают на common/version: в 1.5.8 пакет версии переехал
#     (backend/version → backend/common/version), из-за чего флаги из nixpkgs
#     молча не применялись и сборка сообщала о себе как «untracked»;
#   * версия в ldflags настоящая, а не «testing».
#
# Зачем вообще своё выражение, а не overrideAttrs: фронтенд здесь — отдельный
# buildNpmPackage внутри этого же файла, и overrideAttrs внешней go-деривации
# не меняет ни его src, ни npmDepsHash. Подняв только backend, мы получили бы
# новый сервер со старым собранным фронтендом.
#
# Почему именно 1.5.8-stable (проверено сборкой и запуском, см. ниже):
#   1) В 1.5.2-stable СЛОМАНО скачивание публичных шар — любое, и файла, и
#      папки: HTTP 500 и в журнале
#      `open <path>: not a directory` / `openat <dir>: no such file or directory`.
#      Причина: шара хранит путь с хвостовым слешем («/folder/»), а список
#      файлов нормализован без него, после чего
#      scopedIndexRel() → strings.TrimPrefix("/folder", "/folder/") префикс не
#      срезает, и остаток «folder» ищется ВНУТРИ самой папки. Это регрессия от
#      бэкпорта GHSA-mgqf-5mf5-prfj (переход на OpenContained/os.OpenRoot).
#      В 1.5.8 OpenScopedPath сделан через GetRealPathScoped + os.Open, и
#      проблемы двойного префикса больше нет.
#   2) 1.5.2-stable (15.08.2026) не содержит двух более поздних правок
#      безопасности, а одна из них прямо про приманку: публичное metadata-API
#      отдавало содержимое файлов анонимным посетителям шары, игнорируя лимит
#      скачиваний (GHSA-55mw-cwg7-m8f5). Вторая — повторная регистрация TOTP
#      анонимом по одному паролю (GHSA-qx86-4v5r-26g5).
#   3) В 1.5.4-stable есть обход зависания многочанковых загрузок (#2734) и
#      возвращён `uploadChunkSizeMb: 0` как способ отключить чанки совсем.
# Все четыре GHSA из changelog 1.5.2-stable в 1.5.8-stable на месте —
# обновление не теряет правок безопасности.
#
# Требует Go >= 1.27 (backend/go.mod), поэтому overlay во flake.nix передаёт
# сюда buildGoModule, пересобранный на go_1_27. Он есть в стабильном nixpkgs,
# лезть в unstable не нужно.
#
# При обновлении: поменять version, затем по очереди подставить lib.fakeHash
# вместо hash / npmDepsHash / vendorHash и взять значения из ошибок сборки.
{
  lib,
  fetchFromGitHub,
  buildGoModule,
  buildNpmPackage,
}:

let
  version = "1.5.8-stable";

  src = fetchFromGitHub {
    owner = "gtsteffaniak";
    repo = "filebrowser";
    tag = "v${version}";
    hash = "sha256-+Wy8hh7w3eJIpq0+/UYvO5pCJK/zS5hySPjURjQh6Wg=";
  };

  frontend = buildNpmPackage {
    pname = "filebrowser-quantum-frontend";
    inherit version src;

    sourceRoot = "${src.name}/frontend";

    npmDepsHash = "sha256-qjWTPQZadlMupOWlsHjU5A+cUxfRt2z7bCT4mQXediQ=";

    buildPhase = ''
      runHook preBuild

      npm run build:docker

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r dist/* $out

      runHook postInstall
    '';
  };

in
buildGoModule {
  pname = "filebrowser-quantum";
  inherit version src;

  sourceRoot = "${src.name}/backend";

  vendorHash = "sha256-OAwl2bQUbrTIlYGocysBtR7DE+6L5gvxOXNoqU9q7IM=";

  preBuild = ''
    mkdir -p http/embed
    cp -r ${frontend}/* http/embed/
  '';

  postInstall = ''
    mv $out/bin/backend $out/bin/filebrowser-quantum
  '';

  ldflags = [
    "-w"
    "-s"
    "-X github.com/gtsteffaniak/filebrowser/backend/common/version.Version=${version}"
  ];

  meta = {
    description = "Access and manage your files from the web";
    homepage = "https://github.com/gtsteffaniak/filebrowser";
    changelog = "https://github.com/gtsteffaniak/filebrowser/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.asl20;
    mainProgram = "filebrowser-quantum";
  };
}
