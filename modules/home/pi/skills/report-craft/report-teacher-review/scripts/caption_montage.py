#!/usr/bin/env python3
"""Монтажи кадров с подписями для визуальной приёмки «подпись ↔ содержимое кадра».

Вместо того чтобы скармливать модели 40 отдельных картинок, кадры склеиваются
в листы по N штук, каждый с номером и ожидаемой подписью. Модель смотрит лист
и отвечает только на «совпадает ли то, что на экране, с тем, что обещано в
подписи» — это ловит перепутанные местами кадры, чужие окна и следы автоматизации.

Использование:
  caption_montage.py --from-generator generate_report.js --shots КАТАЛОГ --out /tmp/mont
  caption_montage.py --dir КАТАЛОГ --out /tmp/mont [--per 12] [--width 420]

Номера на плитках соответствуют порядку figure() в генераторе, то есть номерам
рисунков в отчёте.
"""
import os
import re
import subprocess
import sys
import tempfile


def pairs_from_generator(path):
    src = open(path, encoding="utf8").read()
    return [(m.group(1), m.group(2)) for m in
            re.finditer(r'figure\("([^"]+)",\s*"([^"]+)"', src)]


def wrap(text, width=58, lines=2):
    """Подпись в 2 строки: длинное обрезается многоточием."""
    words, out, cur = text.split(), [], ""
    for w in words:
        if len(cur) + len(w) + 1 <= width:
            cur = (cur + " " + w).strip()
        else:
            out.append(cur); cur = w
            if len(out) == lines:
                break
    if len(out) < lines and cur:
        out.append(cur)
    s = "\n".join(out[:lines])
    if len(text) > len(s):
        s = s[: width * lines - 3].rstrip() + "…"
    return s


def tile(img, label, width, tmp):
    """Кадр + полоска с подписью снизу."""
    out = os.path.join(tmp, "tile%03d.png" % tile.n)
    tile.n += 1
    subprocess.run(["magick", img, "-resize", f"{width}x{width}>", out], check=True)
    lab = os.path.join(tmp, "lab%03d.png" % (tile.n))
    # pango:/caption: в этом билде ImageMagick не пишут файл — перенос делаем
    # вручную и рисуем -annotate с переводом строки внутри текста.
    subprocess.run(["magick", "-size", f"{width}x56", "xc:white", "-font", "DejaVu-Sans",
                    "-pointsize", "12", "-gravity", "northwest",
                    "-annotate", "+4+2", wrap(label), lab], check=True)
    subprocess.run(["magick", out, lab, "-append", out], check=True)
    return out


def main():
    a = sys.argv[1:]
    def opt(name, default=None):
        return a[a.index(name) + 1] if name in a else default
    per = int(opt("--per", 12))
    width = int(opt("--width", 420))
    outp = opt("--out", "/tmp/montage")
    items = []
    if "--from-generator" in a:
        gen = opt("--from-generator")
        shots = opt("--shots")
        for i, (f, cap) in enumerate(pairs_from_generator(gen), 1):
            p = os.path.join(shots, f)
            if os.path.exists(p):
                items.append((i, f, cap, p))
            else:
                print(f"НЕТ ФАЙЛА: {p}")
    else:
        d = opt("--dir")
        for i, f in enumerate(sorted(os.listdir(d)), 1):
            if f.lower().endswith((".png", ".jpg", ".jpeg")):
                items.append((i, f, "", os.path.join(d, f)))
    if not items:
        print("нет входных кадров")
        return 1
    tile.n = 0
    with tempfile.TemporaryDirectory() as tmp:
        sheets, batch = [], []
        for start in range(0, len(items), per):
            chunk = items[start:start + per]
            batch = [tile(p, f"{i}. {f} — {cap}", width, tmp) for i, f, cap, p in chunk]
            sheet = f"{outp}-{start // per + 1}.jpg"
            cols = 3
            subprocess.run(["montage"] + batch + ["-tile", f"{cols}x", "-geometry", "+6+6",
                          "-background", "gray90", sheet], check=True)
            sheets.append(sheet)
    for s in sheets:
        print(s)
    return 0


if __name__ == "__main__":
    sys.exit(main())
