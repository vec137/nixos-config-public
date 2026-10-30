#!/usr/bin/env python3
"""audit_lab.py — преподавательская приёмка отчёта без ВМ.

Для лабы:  audit_lab.py <каталог лабы>   (например "Лабораторная работа 7")

Печатает:
  1) покрытие вопросов методички (rus/*.docx, кроме самого отчёта);
  2) сверку чисел/адресов/доменов отчёта с DATA.md (если есть);
  3) в /tmp/audit/Л<N>_qa.txt — пары вопрос -> ответ из отчёта (для чтения глазами).
"""
import sys, os, re, glob, zipfile, subprocess, tempfile

lab = sys.argv[1]
rus = os.path.join(lab, "rus")
doc = glob.glob(os.path.join(rus, "*Отчёт.docx"))
assert doc, f"нет отчёта в {rus}"
doc = doc[0]
n = re.search(r"(\d+)", os.path.basename(lab)).group(1)

def dtext(p):
    z = zipfile.ZipFile(p)
    d = z.read("word/document.xml").decode("utf8", "ignore")
    d = re.sub(r"<w:p [^>]*>|<w:p>", "\n", d)
    d = re.sub(r"<w:tab[^>]*/>", " ", d)
    d = re.sub(r"<[^>]+>", "", d)
    return re.sub(r"[ \t]+", " ", d)

rep = dtext(doc)
rep_l = re.sub(r"\s+", " ", rep).lower()

STOP = set("что какие какой как для чего этом данный который может быть если или поле кадра адрес данные вы этот также когда где зачем сколько назовите определите опишите укажите выберите сравните".split())
def kws(s):
    return [w for w in re.findall(r"[а-яёa-z]{5,}", s.lower()) if w not in STOP]

print(f"########## {lab}")
tot = miss = 0
for f in sorted(glob.glob(os.path.join(rus, "*.docx"))):
    if "Отчёт" in f:
        continue
    t = dtext(f)
    qs = [p.strip() for p in t.split("\n")
          if (p.strip().endswith("?") or re.match(r"^(Step|Шаг|Вопрос)", p.strip())) and len(p.strip()) > 25]
    tot += len(qs)
    for q in qs:
        k = kws(q)[:5]
        if len(k) < 2:
            continue
        if sum(1 for x in k if x in rep_l) < max(2, len(k) - 1):
            miss += 1
            print(f"  НЕ ПОКРЫТО [{os.path.basename(f)[:28]}]: {q[:130]}")
print(f"  вопросов в методичках: {tot}, без покрытия: {miss}")

# --- сверка с DATA.md ---
dm = os.path.join(rus, "DATA.md")
if os.path.exists(dm):
    data = open(dm, encoding="utf-8").read()
    data_l = data.lower()
    for name, pat in (("IP", r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"),
                      ("MAC", r"\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b"),
                      ("домены", r"\b[a-z0-9-]+\.(?:com|net|org|ru|io|dev|gg|cloud|edu)\b"),
                      ("hex-значения", r"\b0x[0-9a-f]{2,}\b")):
        vals = sorted(set(re.findall(pat, rep_l)))
        gone = [v for v in vals if v not in data_l]
        if gone:
            print(f"  НЕТ В DATA.md ({name}): {gone}")
    lines = [l.strip() for l in rep.split("\n") if re.search(r"\d{2,}", l)]
    bad = [l for l in lines if not any(x.rstrip(".,%") in data for x in re.findall(r"\d[\d.,%]{1,}", l))]
    print(f"  строк с числами: {len(lines)}, из них ни одно число не подтверждено DATA.md: {len(bad)}")
    for b in bad[:12]:
        print("     !", b[:120])
else:
    print("  DATA.md нет — числовая сверка по DATA невозможна")

# --- пары вопрос -> ответ ---
paras = [re.sub(r"\s+", " ", p).strip() for p in rep.split("\n")]
paras = [p for p in paras if p]
qa, i = [], 0
while i < len(paras):
    p = paras[i]
    if re.match(r"^(Вопрос\s*\d*\.?|Задание\s*\d*\.?)", p):
        q = p
        ans = []
        j = i + 1
        while j < len(paras) and not re.match(r"^(Вопрос\s*\d*\.?|Задание\s*\d*\.?|\d+\.\d+\s|Рисунок\s+\d+\.)", paras[j]):
            ans.append(paras[j]); j += 1
        qa.append((q, " ".join(ans)[:600]))
        i = j
    else:
        i += 1
os.makedirs("/tmp/audit", exist_ok=True)
out = f"/tmp/audit/Л{n}_qa.txt"
with open(out, "w", encoding="utf-8") as fh:
    for k, (q, a) in enumerate(qa, 1):
        fh.write(f"[{k}] {q}\n    ОТВЕТ: {a}\n\n")
print(f"  пар вопрос->ответ: {len(qa)} -> {out}")
