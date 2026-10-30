// Каркас генератора .docx (библиотека npm `docx`).
// Скопировать в начало generate_report.js и подставить свои SHOTS/размеры.
// Ключевые свойства: авто-нумерация рисунков и таблиц через токены {{файл}}/{{ключ}},
// падение сборки при разъезде нумерации, картинка склеена с подписью (keepNext),
// таблицы не рвутся через страницу (cantSplit + tableHeader + keepNext).

const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  ImageRun, Table, TableRow, TableCell, WidthType,
} = require("docx");
const fs = require("fs");

const FONT = "Times New Roman";
const SIZE = 28;            // 14pt (в docx размер в полутаках)
const SIZE_CAPTION = 22;    // 11pt
const LINE = 360;           // межстрочный 1,5
const INDENT_FIRST_LINE = 709; // 1,25 см в twip
const SHOTS = __dirname + "/screenshots";   // каталог кадров
const FIG_MAX_W = 620, FIG_MAX_H = 430;     // пределы встраивания, px

function bodyP(children, opts = {}) {
  return new Paragraph({
    children,
    alignment: opts.alignment || AlignmentType.JUSTIFIED,
    spacing: { line: LINE, lineRule: "auto", after: opts.after ?? 0 },
    indent: { firstLine: opts.noIndent ? 0 : INDENT_FIRST_LINE },
  });
}

// ---- авто-нумерация: номера считаются ЗАРАНЕЕ по порядку вызовов в этом файле,
// поэтому ссылка {{файл}} может стоять и до, и после самого рисунка ----
let figNo = 0, tblNo = 0;
const figKey = {}, tblKey = {};
fs.readFileSync(__filename, "utf8")
  .matchAll(/\.\.\.figure\("([^"]+)"/g)
  .forEach((m, i) => { figKey[m[1]] = i + 1; });
fs.readFileSync(__filename, "utf8")
  .matchAll(/tblCap\("([^"]+)"(?:,\s*"([^"]+)")?/g)
  .forEach((m, i) => { tblKey[m[2] || ("tbl" + (i + 1))] = i + 1; });

function resolveRefs(s) {
  return String(s).replace(/\{\{([\w.\-]+)\}\}/g, (_, k) => {
    const n = figKey[k] !== undefined ? figKey[k] : tblKey[k];
    if (!n) throw new Error("Неизвестный ключ перекрёстной ссылки: " + k);
    return String(n);
  });
}

function t(text, opts = {}) {
  return new TextRun({
    text: resolveRefs(text), font: FONT, size: opts.size || SIZE,
    bold: !!opts.bold, italics: !!opts.italics,
    underline: opts.underline ? {} : undefined, color: "000000",
  });
}
const para = (text, opts = {}) => bodyP([t(text, opts)], opts);
// Дословная цитата задания первоисточника — курсивом, без своих слов и правок.
const task = (text) => bodyP([t(text, { italics: true })], { after: 120 });
const qa = (label, question, answer) => [
  bodyP([t(label + " ", { bold: true, italics: true }), t(question, { italics: true })], { after: 60 }),
  bodyP([t(answer)], { after: 200 }),
];

function pngSize(buf) { return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) }; }

function figure(file, caption) {
  figNo += 1;
  if (figKey[file] !== figNo)
    throw new Error("Разошлась нумерация рисунков: " + file + " (ожидался " + figKey[file] + ", фактически " + figNo + ")");
  const data = fs.readFileSync(SHOTS + "/" + file);
  const { w, h } = pngSize(data);
  const sc = Math.min(FIG_MAX_W / w, FIG_MAX_H / h, 1);
  const width = Math.round(w * sc), height = Math.round(h * sc);
  return [
    new Paragraph({
      children: [new ImageRun({ type: "png", data, transformation: { width, height } })],
      alignment: AlignmentType.CENTER,
      spacing: { before: 200, after: 80 },
      indent: { firstLine: 0 },
      keepNext: true,          // подпись не уедет на следующую страницу
    }),
    new Paragraph({
      children: [t("Рисунок " + figNo + ". " + caption, { size: SIZE_CAPTION })],
      alignment: AlignmentType.CENTER,
      spacing: { after: 240 },
      indent: { firstLine: 0 },
    }),
  ];
}

function tblCap(title, key) {
  tblNo += 1;
  if (tblKey[key || ("tbl" + tblNo)] !== tblNo)
    throw new Error("Разошлась нумерация таблиц: " + (key || title));
  return [new Paragraph({
    children: [t("Таблица " + tblNo + ". " + title, { size: SIZE_CAPTION })],
    alignment: AlignmentType.LEFT,
    spacing: { before: 200, after: 60 },
    indent: { firstLine: 0 },
    keepNext: true,            // подпись таблицы не отрывается от неё
  })];
}

function dcell(width, text, o = {}) {
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    children: [new Paragraph({
      children: [t(String(text), { size: SIZE_CAPTION, bold: !!o.bold })],
      alignment: o.center === false ? AlignmentType.LEFT : AlignmentType.CENTER,
      spacing: { after: 0 },
      keepNext: !!o.keepNext,
    })],
  });
}

// rows[0] — шапка. Ширины подбираются так, чтобы подписи не переносились.
function gridTable(widths, rows) {
  const keep = (i) => ({ keepNext: i < rows.length - 1 });
  const mk = (cells, header, i) => new TableRow({
    cantSplit: true,
    ...(header ? { tableHeader: true } : {}),
    children: cells.map((c, j) => dcell(widths[j], c, {
      bold: header, center: false, ...(header ? { keepNext: true } : keep(i)),
    })),
  });
  return new Table({
    width: { size: widths.reduce((a, b) => a + b, 0), type: WidthType.DXA },
    columnWidths: widths,
    rows: [mk(rows[0], true, 0), ...rows.slice(1).map((r, i) => mk(r, false, i + 1))],
  });
}

function heading1(text, num) {
  return new Paragraph({
    children: [t(`${num ? num + ". " : ""}${text}`, { bold: true })],
    alignment: AlignmentType.CENTER,
    spacing: { line: LINE, lineRule: "auto", before: 240, after: 240 },
    pageBreakBefore: true,
    heading: HeadingLevel.HEADING_1,
  });
}
function heading2(text) {
  return new Paragraph({
    children: [t(text, { bold: true })],
    alignment: AlignmentType.LEFT,
    spacing: { line: LINE, lineRule: "auto", before: 240, after: 120 },
    indent: { firstLine: INDENT_FIRST_LINE },
    heading: HeadingLevel.HEADING_2,
  });
}

// Пример сборки документа:
//   const sec1 = [heading1("Раздел", "1"), task("…"), ...figure("a.png", "…"), ...qa("Вопрос.", "…", "…")];
//   new Document({ sections: [{ properties: {}, children: [...sec1] }] })
//   Packer.toBuffer(doc).then(b => fs.writeFileSync(process.argv[2], b));  // argv[2] — абсолютный путь!
module.exports = { para, task, qa, figure, tblCap, gridTable, heading1, heading2, bodyP, t };
