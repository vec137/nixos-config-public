#!/usr/bin/env python3
"""Проверка PDF: подпись рисунка не должна висеть в начале страницы без рисунка над ней.

Механика: pdftotext -bbox даёт координаты строк текста; pdftotex не видит картинки,
поэтому полоска над подписью проверяется попиксельно (pdftoppm -r 72 => 1pt = 1px).
Если полоска над подписью «Рисунок N.» абсолютно белая – рисунок оторван от подписи.
"""
import re
import subprocess
import sys
import os
import tempfile


def page_lines(pdf, p):
    out = subprocess.run(["pdftotext", "-bbox", "-f", str(p), "-l", str(p), pdf, "-"],
                         capture_output=True, text=True).stdout
    words = re.findall(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)</word>', out)
    rows = {}
    for xmin, ymin, xmax, ymax, txt in words:
        key = round(float(ymin), 1)
        rows.setdefault(key, []).append((float(xmin), float(ymin), float(ymax), txt))
    lines = []
    for key in sorted(rows):
        ws = sorted(rows[key])
        lines.append({"y": key, "ybot": max(w[2] for w in ws), "text": " ".join(w[3] for w in ws)})
    return lines


def band_blank(png, y0, y1, width):
    y0 = max(0, int(y0))
    h = int(y1 - y0)
    if h <= 0:
        return True
    out = subprocess.run(["magick", png, "-crop", f"{width}x{h}+0+{y0}", "+repage",
                          "-fuzz", "5%", "-format", "%[standard-deviation]", "info:"],
                         capture_output=True, text=True).stdout.strip()
    try:
        return float(out) < 0.005
    except ValueError:
        return False


def main(pdf):
    info = subprocess.run(["pdfinfo", pdf], capture_output=True, text=True).stdout
    pages = int(info.split("Pages:")[1].split()[0])
    bad = []
    with tempfile.TemporaryDirectory() as td:
        subprocess.run(["pdftoppm", "-r", "72", "-png", pdf, os.path.join(td, "pg")], check=True)
        for p in range(1, pages + 1):
            png = os.path.join(td, f"pg-{p:02d}.png") if p < 100 else os.path.join(td, f"pg-{p}.png")
            if not os.path.exists(png):
                png = os.path.join(td, f"pg-{p:02d}.png")
            geo = subprocess.run(["magick", "identify", "-format", "%w %h", png],
                                 capture_output=True, text=True).stdout.split()
            w = int(geo[0])
            lines = page_lines(pdf, p)
            for i, ln in enumerate(lines):
                if not re.match(r"^Рисунок \d", ln["text"]):
                    continue
                top = 57 if i == 0 else max(57, lines[i - 1]["ybot"] + 2)
                if band_blank(png, top, ln["y"] - 1, w):
                    bad.append((p, ln["text"][:70]))
    if bad:
        for p, txt in bad:
            print(f" стр. {p}: подпись без рисунка над ней | {txt}")
        print(f"ИТОГ: {len(bad)} замечаний")
        return 1
    print(f"ИТОГ: OK ({pages} стр., каждая подпись стоит под своим рисунком)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
