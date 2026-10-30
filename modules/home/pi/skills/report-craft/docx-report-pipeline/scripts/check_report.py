#!/usr/bin/env python3
"""check_report.py — механическая приёмка отчёта перед сдачей.

Запуск:  check_report.py <путь к docx>
Проверяет: титул заполнен, оглавления/источников нет, «—» только в цитатах,
каждый рисунок подписан и зацитирован (диапазоны «рис. 5–7» и перечисления
«рис. 22, 23 и 24» understood), каждая таблица подписана и зацитирована,
нет заглушек, вложения совпадают со скриншотами рядом с docx.
"""
import sys, os, re, zipfile, hashlib, glob, subprocess, tempfile

doc = sys.argv[1]
z = zipfile.ZipFile(doc)
xml = z.read("word/document.xml").decode("utf8", "ignore")
text = re.sub(r"<[^>]+>", "", xml.replace("</w:p>", "\n"))

fails = []
def check(ok, msg):
    print(("  OK   " if ok else "  ОШИБКА ") + msg)
    if not ok:
        fails.append(msg)

# 1. плейсхолдеры и заглушки
# плейсхолдер — квадратные скобки со «словесным» содержимым; технические
# скобки вида [nop,nop,TS val …] (вывод tcpdump) не считаем заглушкой
ph = re.findall(r"\[(?:[А-ЯЁ][а-яёA-Za-z][а-яёA-Za-z .№()\-]{1,38}|@@FILL|Вписать|TODO)\]", text)
check(not ph, f"плейсхолдеры/заглушки: {ph[:5]}")

# 2. оглавление и список источников отсутствуют
check("TOC" not in xml, "оглавление отсутствует")
check(not re.search(r"Список использованн", text, re.I), "списка источников нет")

# 3. длинное тире только в цитатах заданий (считаем, не запрещаем вслепую)
dashes = len(re.findall(r"—", text))
print(f"  INFO  длинное тире «—»: {dashes} (допустимо только внутри цитат методички)")

# 4. рисунки: подписи и ссылки
caps = [int(n) for n in re.findall(r"Рисунок (\d+)\.", text)]
check(len(caps) == len(set(caps)) and caps == list(range(1, len(caps) + 1)),
      f"нумерация рисунков сплошная: {len(caps)} подписей")
flat = re.sub(r"\s+", " ", text)
cited = set()
for m in re.finditer(r"рис(?:унок)?\.?\s*([0-9]+(?:\s*[–-]\s*[0-9]+)?(?:\s*,\s*[0-9]+)*(?:\s+и\s+[0-9]+)?)", flat, re.I):
    for part in re.split(r",|\s+и\s+", m.group(1)):
        part = part.strip()
        if "–" in part or "-" in part:
            a, b = re.split(r"[–-]", part)
            cited.update(range(int(a), int(b) + 1))
        elif part.isdigit():
            cited.add(int(part))
uncited = [n for n in range(1, len(caps) + 1) if n not in cited]
check(not uncited, f"все рисунки зацитированы; без ссылки: {uncited}")

# 5. таблицы: подписи и ссылки
tcaps = [int(n) for n in re.findall(r"Таблица (\d+)\.", text)]
if tcaps:
    check(tcaps == list(range(1, len(tcaps) + 1)), f"нумерация таблиц сплошная: {len(tcaps)}")
    tcited = set(int(n) for n in re.findall(r"[Тт]аблиц[а-я]*\s+(\d+)", flat))
    for m in re.finditer(r"[Тт]аблиц[а-я]*\s+([0-9]+)\s*[–-]\s*([0-9]+)", flat):
        tcited.update(range(int(m.group(1)), int(m.group(2)) + 1))
    tmiss = [n for n in range(1, len(tcaps) + 1) if n not in tcited]
    check(not tmiss, f"все таблицы зацитированы; без ссылки: {tmiss}")
else:
    print("  INFO  подписанных таблиц нет")

# 6. вложения совпадают со скриншотами
# каталог кадров берём из генератора (const SHOTS = "..."), иначе screenshots/
gen = os.path.join(os.path.dirname(doc), "_report_tools", "generate_report.js")
shotdir = os.path.join(os.path.dirname(doc), "screenshots")
if os.path.exists(gen):
    m = re.search(r'const SHOTS\s*=\s*"([^"]+)"', open(gen, encoding="utf8").read())
    if m:
        # путь в генераторе может быть записан escape-последовательностями \u043b…
        cands = [m.group(1)]
        try:
            cands.append(m.group(1).encode("utf-8").decode("unicode_escape"))
        except Exception:
            pass
        for c in cands:
            if os.path.isdir(c):
                shotdir = c
                break
shots = {hashlib.sha256(open(f, "rb").read()).hexdigest()
         for f in glob.glob(os.path.join(shotdir, "*.png"))}
media = {hashlib.sha256(z.read(n)).hexdigest() for n in z.namelist()
         if n.startswith("word/media/") and not n.endswith("/")}
check(media <= shots, f"вложения ({len(media)}) совпадают с каталогом кадров {os.path.basename(shotdir)} ({len(shots)}); "
                      f"лишних: {len(media - shots)}")

# 7. таблицы не рвутся через страницу (cantSplit у всех строк)
rows = len(re.findall(r"<w:tr[ >]", xml))
cant = len(re.findall(r"<w:cantSplit/>", xml))
check(rows == cant, f"строки таблиц не разрываются: cantSplit {cant} из {rows}")

# 8. объём
try:
    with tempfile.TemporaryDirectory() as td:
        subprocess.run(["soffice", "--headless", "--convert-to", "pdf", "--outdir", td, doc],
                       check=True, capture_output=True)
        pdf = glob.glob(td + "/*.pdf")[0]
        pages = int(re.search(r"Pages:\s+(\d+)", subprocess.run(
            ["pdfinfo", pdf], capture_output=True, text=True).stdout).group(1))
    print(f"  INFO  страниц: {pages}, рисунков: {len(caps)}, таблиц: {len(tcaps)}")
except Exception as e:
    print("  INFO  рендер в PDF не удался:", e)

print("\nИТОГ:", "OK" if not fails else f"{len(fails)} проблем")
sys.exit(0 if not fails else 1)
