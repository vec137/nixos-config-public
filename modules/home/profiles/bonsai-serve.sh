# Лаунчер Bonsai 2 27B (prism-ml/Ternary-Bonsai-2-27B-gguf) — собирается в
# команду `bonsai-serve` через writeShellApplication в local-inference.nix.
# llama-server здесь — из форка PrismML (llama-cpp-prism), а не штатный.
#
#   bonsai-serve                  — сервер на :8080 (тот же порт, что у qwen:
#                                   hermes переключается без правки конфига)
#   bonsai-serve <флаги>          — дописать/переопределить флаги llama-server
#   bonsai-serve calibrate        — один раз: KV-bias для q4_0-кэша (см. ниже)
#
# Переменные окружения:
#   BONSAI_QUANT=PTQ1_0|PQ2_0     PTQ1_0 (5.95 ГБ) — по умолчанию, оставляет
#                                 больше VRAM под контекст; PQ2_0 (7.21 ГБ) —
#                                 по замерам PrismML быстрее на новых GPU (на
#                                 4070 не проверено), но контекста меньше
#   BONSAI_CTX=N                  зафиксировать контекст (по умолчанию — авто)
#   BONSAI_KV=q4_0|q8_0|f16       тип KV-кэша (по умолчанию q4_0)
#   BONSAI_EFFORT=medium|low|xhigh  глубина размышлений; дефолт модели — xhigh
#                                 (думает очень долго). "high" НЕ существует —
#                                 шаблон отвечает HTTP 500
#   BONSAI_VISION=1               подгрузить mmproj (картинки), −0.63 ГБ VRAM
#   PORT=8080

QUANT="${BONSAI_QUANT:-PTQ1_0}"
DIR="${BONSAI_DIR:-$HOME/models/bonsai2-27b}"
REPO="prism-ml/Ternary-Bonsai-2-27B-gguf"
MODEL="$DIR/Ternary-Bonsai-2-27B-$QUANT.gguf"
MMPROJ="$DIR/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf"
# KV-bias калибруется под конкретный файл модели, поэтому в имени квант.
KV_BIAS="$DIR/Ternary-Bonsai-2-27B-$QUANT-kv-bias.gguf"
KV="${BONSAI_KV:-q4_0}"
PORT="${PORT:-8080}"

# HF_TOKEN нужен не для доступа (репозиторий публичный), а ради рейт-лимита.
# Через прокси: прямые долгие соединения с HF на этом сервере обрываются
# посреди файла (при первой загрузке оба файла встали на 3 и 6 ГБ). Но и через
# прокси сервера (раньше 4080, теперь mihomo на 6080) выходит ~1 МБ/с — это запасной путь. Быстрее скачать на ноутбуке через
# балансировщик и пролить по LAN (~6 МБ/с; как это сделать с докачкой и
# проверкой sha256 — см. CLAUDE.md репозитория, раздел server).
fetch() {
  HF_TOKEN="$(cat /run/secrets/hf-token)" HTTPS_PROXY=http://127.0.0.1:6080 \
    hf download "$REPO" "$1" --local-dir "$DIR"
}

[ -f "$MODEL" ] || fetch "$(basename "$MODEL")"

# Проверка и для сервера, и для калибровки: обоим нужна свободная VRAM. При
# занятой карте --fit не падает, а молча выгружает слои на CPU — всё медленно.
if curl -s --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null; then
  echo "Порт $PORT уже занят — скорее всего, qwen (~/serve.sh). Обе модели в 12 ГБ VRAM" >&2
  echo "одновременно не помещаются; останови его: pkill -f 'llama-server.*--port $PORT'" >&2
  exit 1
fi

if [ "${1:-}" = calibrate ]; then
  # Калибровка KV-bias. Зачем: q4_0 — симметричный квантователь без нулевой
  # точки, и если у канала K есть постоянное смещение, часть 4 бит уходит на
  # его кодирование. Bias вычитается из K перед записью в кэш; на результат
  # внимания это не влияет (softmax инвариантен к сдвигу всей строки), а
  # точность квантования растёт. Считается один раз на модель, ~минуты.
  #
  # Корпус модель генерирует сама (скрипт из исходников форка), внешние данные
  # не нужны. Калибровать надо с тем же -ctk q4_0, что и при работе: форк
  # вращает квантованный K-кэш (Хадамар), и bias, снятый в другом базисе,
  # загрузчик отвергнет.
  corpus="$(mktemp --suffix=.txt)"
  trap 'rm -f "$corpus"' EXIT
  bash "$CALIB_CORPUS_SCRIPT" -s "$(command -v llama-server)" -m "$MODEL" -o "$corpus" -g 99 -p 8901
  llama-kv-mean-center -m "$MODEL" -f "$corpus" -o "$KV_BIAS" -ngl 99 -fa on -ctk q4_0
  echo "Готово: $KV_BIAS — bonsai-serve подхватит его сам."
  exit 0
fi

args=(
  -m "$MODEL"
  -ngl 99 -fa on
  # Один слот. Иначе контекст делится между параллельными запросами, а нам
  # нужен один длинный.
  -np 1
  --cache-type-k "$KV" --cache-type-v "$KV"
  # Модель целиком в VRAM, mmap только держал бы лишнюю копию в page cache.
  --load-mode none
  -b 2048 -ub 1024
  --jinja --reasoning-format none
  # Сэмплинг — из карточки модели, режим размышлений.
  --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.05
  # Кэш промптов в RAM (по умолчанию 8 ГиБ; 24 ГиБ — рекомендация из
  # KNOWN_ISSUES модели для одного пользователя). Пока работает Bonsai, qwen
  # остановлен, и RAM свободна. Полный слот на 262k в q4_0 ≈ 4.5 ГиБ.
  --cache-ram 24576
  --slot-save-path "$HOME/.cache/llama-slots/bonsai2"
  --host 0.0.0.0 --port "$PORT"
)

if [ -n "${BONSAI_CTX:-}" ]; then
  args+=(-c "$BONSAI_CTX" --fit off)
else
  # Главный трюк ради большого контекста. -c не задан, поэтому --fit сам
  # начинает с полного обученного контекста модели (262144) и, если тот не
  # влезает, пропорционально урезает его ровно до свободной VRAM, оставив
  # запас --fit-target МиБ. Слои на CPU он выгружает, только если не влезает
  # даже --fit-ctx — а этого здесь не будет. 512 МиБ запаса хватает:
  # сервер headless, VRAM больше никто не занимает.
  args+=(--fit on --fit-target 512 --fit-ctx 32768)
fi

if [ -f "$KV_BIAS" ] && [ "$KV" = q4_0 ]; then
  args+=(--kv-mean-center "$KV_BIAS")
fi

if [ -n "${BONSAI_EFFORT:-}" ]; then
  args+=(--chat-template-kwargs "{\"reasoning_effort\":\"$BONSAI_EFFORT\"}")
fi

if [ "${BONSAI_VISION:-0}" = 1 ]; then
  [ -f "$MMPROJ" ] || fetch "$(basename "$MMPROJ")"
  args+=(--mmproj "$MMPROJ")
fi

mkdir -p "$HOME/.cache/llama-slots/bonsai2"
exec llama-server "${args[@]}" "$@"
