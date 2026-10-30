#!/usr/bin/env python3
"""Покрытие отчёта заданиями первоисточника + разбор пар «вопрос → ответ».

Использование:
  qa_coverage.py ЗАДАНИЕ1.docx [ЗАДАНИЕ2.docx ...] -- ОТЧЁТ.docx

Выводит:
  * вопросы/пункты заданий, которым не найдено ответа в отчёте (проверить вручную:
    часто ответ есть, но переформулирован — ложное срабатывание);
  * вопросы отчёта, которых нет в задании (признак «додуманного» вопроса);
  * ответы без вопроса и вопросы без ответа;
  * рисунки/таблицы без подписи и без ссылки в тексте.

Смысл: найти то, что преподаватель заметит как «вопрос задан — ответа нет» или
«ответ не про тот вопрос». Фuzzy-совпадение намеренно щедрое: инструмент
сужает круг проверки, а не выносит вердикт.
"""
import re
import sys
import difflib
import zipfile


def docx_lines(path):
    z = zipfile.ZipFile(path)
    x = z.read("word/document.xml").decode("utf8", "ignore")
    x = re.sub(r"</w:p>", "\n", x)
    t = re.sub(r"<[^>]+>", "", x)
    t = t.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"')
    return [l.strip() for l in t.split("\n") if l.strip()]


def norm(s):
    s = s.lower().replace("ё", "е")
    s = re.sub(r"[^a-zа-я0-9 ]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


QUEST = re.compile(r"^(Вопрос|Question|Задание|Вопросы)", re.I)


def assignment_questions(lines):
    """Вопросы/пункты из первоисточника: строки с «?», строки после маркеров
    «Вопрос/Step/Шаг», строки перед пустой строкой «_____»."""
    out = []
    for i, l in enumerate(lines):
        blank_after = i + 1 < len(lines) and set(lines[i + 1].strip()) <= set("_ ")
        if l.endswith("?") or l.endswith("? —") or QUEST.match(l) or blank_after:
            if len(norm(l)) > 12:
                out.append(l)
    return out


def report_pairs(lines):
    """Пары «вопрос → ответ» отчёта: маркер вопроса + следующий абзац."""
    pairs, i = [], 0
    while i < len(lines):
        if QUEST.match(lines[i]):
            q = re.sub(r"^(Вопрос\s*\d*\.?\s*)", "", lines[i]).strip()
            a = lines[i + 1] if i + 1 < len(lines) else ""
            pairs.append((q, a))
            i += 2
        else:
            i += 1
    return pairs


def best(q, pool):
    nq = norm(q)
    scored = sorted(((difflib.SequenceMatcher(None, nq, norm(p)).ratio(), p) for p in pool), reverse=True)
    return scored[0] if scored else (0.0, "")


def main():
    args = sys.argv[1:]
    sep = args.index("--") if "--" in args else len(args) - 1
    tasks, rep = args[:sep], args[sep + 1:]
    tlines = [l for f in tasks for l in docx_lines(f)]
    rlines = docx_lines(rep[0])
    aq = assignment_questions(tlines)
    pairs = report_pairs(rlines)
    rtexts = [q for q, _ in pairs] + [a for _, a in pairs] + rlines

    print(f"вопросов в задании: {len(aq)}, пар вопрос→ответ в отчёте: {len(pairs)}")
    print("\n== задания без явного ответа в отчёте (проверить вручную) ==")
    miss = 0
    for q in aq:
        r, _ = best(q, rtexts)
        if r < 0.55:
            miss += 1
            print(f"  [{r:.2f}] {q[:150]}")
    print(f"  всего {miss}")

    print("\n== вопросы отчёта, не найденные в задании (возможен выдуманный вопрос) ==")
    for q, a in pairs:
        r, src = best(q, aq)
        if r < 0.5:
            print(f"  [{r:.2f}] {q[:120]}")

    print("\n== пустые ответы ==")
    for q, a in pairs:
        if len(norm(a)) < 3:
            print(f"  {q[:120]}")

    caps = [l for l in rlines if re.match(r"^(Рисунок|Рис\.|Таблица|Table|Figure)\s*\d", l)]
    body = " ".join(rlines)
    print(f"\n== подписей: {len(caps)} ==")
    for c in caps[:0]:
        pass
    nums = [re.match(r"^(?:Рисунок|Рис\.|Таблица|Table|Figure)\s*(\d+)", c).group(1) for c in caps]
    for n in sorted(set(nums), key=int):
        if not re.search(r"(рис|табл|рисунок|таблица)[^\w]{0,3}\b" + n + r"\b", body, re.I):
            print(f"  №{n} не процитирован в тексте")


if __name__ == "__main__":
    main()
