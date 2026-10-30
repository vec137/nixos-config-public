#!/usr/bin/env python3
"""Дамп текста .docx (абзацы + таблицы) в stdout.

Использование: extract_docx_text.py ФАЙЛ.docx [--tables-first]
Нужен, чтобы сравнивать отчёт с методичкой/заданием и искать расхождения
вопрос↔ответ не глазами по Word'у, а диффом по тексту.
"""
import re
import sys
import zipfile


def cells_of(x):
    """Таблицы → строки «ячейка | ячейка»."""
    out = []
    for tbl in re.findall(r"<w:tbl>.*?</w:tbl>", x, re.S):
        for row in re.findall(r"<w:tr[ >].*?</w:tr>", tbl, re.S):
            cs = [re.sub(r"<[^>]+>", "", c) for c in re.findall(r"<w:tc[ >].*?</w:tc>", row, re.S)]
            out.append(" | ".join(c.strip() for c in cs))
    return out


def main(path):
    z = zipfile.ZipFile(path)
    x = z.read("word/document.xml").decode("utf8", "ignore")
    tables = cells_of(x)
    x = re.sub(r"</w:p>", "\n", x)
    x = re.sub(r"<w:tab[^>]*/>", "\t", x)
    text = re.sub(r"<[^>]+>", "", x)
    text = text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    text = text.replace("&quot;", '"').replace("&#8217;", "'")
    lines = [l.strip() for l in text.split("\n")]
    lines = [l for l in lines if l]
    if "--tables-first" in sys.argv:
        print("### ТАБЛИЦЫ")
        print("\n".join(tables))
        print("### АБЗАЦЫ")
    print("\n".join(lines))


if __name__ == "__main__":
    main(sys.argv[1])
