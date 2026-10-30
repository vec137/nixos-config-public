---
name: filebrowser-mirror-sync
description: Push/pull files to a FileBrowser (Quantum) file server over its REST API with mandatory sha256 verification — text and binary uploads, downloads, deletes, directory listings, and the API quirks that make naive uploads fail (PUT returns 404, metadata size lies, login rate limit, paths with spaces). Use whenever a working tree must be mirrored to a remote copy ("залей на зеркало", "обнови на filebrowser", "синхронизируй с облаком"), whenever a .docx/.pdf/.png must be uploaded or downloaded from FileBrowser, or whenever files landed in the wrong folder after a bulk upload.
---

# Зеркало на FileBrowser: загрузка с верификацией

Главное свойство такого «зеркала»: это **отдельная копия, а не примонтированный
диск**. Правки на зеркале сами не переносятся и наоборот — после каждого
изменения рабочего файла его надо залить явно.

## Тулка или REST

- Текстовые файлы можно тулкой MCP (`upload_file`).
- **Бинарные (docx, pdf, png, zip) — только через REST**: MCP-тулка передаёт
  текст и испортит файл.

## Креды

`.env` (chmod 600): `FB_URL`, `FB_USER`, `FB_PASSWORD`, `FB_SOURCE` (имя источника,
обычно `files`). Скрипт ищет `.env` рядом с собой, затем файл из переменной
`FB_ENV`, затем типовое место хоста — так что кредиты не надо экспортировать вручную.

## Команды (`scripts/fb_sync.sh`)

```bash
./fb_sync.sh login
./fb_sync.sh up   "Локальный/Отчёт.docx" "/Проект/Отчеты/Отчёт.docx"
./fb_sync.sh ver  "Локальный/Отчёт.docx" "/Проект/Отчеты/Отчёт.docx"
./fb_sync.sh down "/Проект/Отчеты/Отчёт.pdf" /tmp/check.pdf
./fb_sync.sh del  "/Проект/Отчеты/старый.pdf"
./fb_sync.sh ls   "/Проект/Отчеты"
./fb_sync.sh sync "/Проект/Отчеты" "/Проект/Отчеты"   # дерево целиком + листинг в конце
```

`up` сам делает загрузку и сверку sha256 скачанным обратно — это единственный
надёжный способ подтвердить, что файл лёг.

## Грабли Quantum/FileBrowser (все стоят в скрипте)

| Что пробуют | Что происходит | Как правильно |
|---|---|---|
| `PUT /api/resources/<path>` | **404** | `POST /api/resources?path=<enc>&source=<FB_SOURCE>&override=true` с `--data-binary @файл` |
| `GET /api/resources/download?path=…` | 404/пусто | параметр называется **`file=`**, не `path=` |
| `GET /api/resources/<path>?content=1` (листинг) | **404** | `GET /api/resources?path=<enc>&source=…&content=1`; в ответе у файлов поле `name`, а не `path` |
| `DELETE /api/resources/<path>` | 404 | `DELETE /api/resources?path=<enc>&source=…` (query) |
| сверить по `size` из metadata | врёт: показывает старое значение после успешной загрузки | скачивать обратно и сравнивать `sha256sum` |
| логин в цикле | лимит **10 логинов/мин на IP**, дальше отказы | логин один раз, токен в кэш-файл, продление через `/api/renew` |
| URL-кодирование пути | русские имена и пробелы рвут запрос | `urllib.parse.quote(path, safe='')` |

## Массовая загрузка: два обязательных контроля

1. **Кавычки во всех подстановках.** Пути с пробелами (русские каталоги вида
   «Лабораторная работа 5») требуют кавычек вокруг каждого `$(basename …)` и
   `$(dirname …)`. Неэкранированный `dirname` уронил в цикл мусорное значение —
   42 файла ушли в чужой каталог. В `sync` это снято тем, что относительный путь
   считается параметром, а не вложенными подстановками.
2. **После массовой загрузки — листинг целевого каталога** (`ls`), сверка имён, а
   не только sha256 отдельных файлов: sha подтверждает содержимое, но не то, что
   файл лёг туда, куда нужно.

## Протокол «после каждой правки»

1. изменить рабочий файл (генератор → пересборка артефакта);
2. `up` артефакта и исходника по тому же относительному пути, что и локально;
3. `up` связанных файлов (PDF, TODO, конфиг, индексный файл проекта);
4. `ver`/листинг — и только потом докладывать пользователю «синхронизировано».

Если загрузка шла пакетом и часть файлов не сверилась — не перелогиниваться в
цикле: один `login`, затем повторить `up` только для сбоевших.
