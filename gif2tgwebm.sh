#!/usr/bin/env bash

set -e

### НАСТРОЙКИ ПО УМОЛЧАНИЮ ###

SRC_DIR="gif"        # входные gif
OUT_DIR="webm"       # выходные webm

DEFAULT_MODE="sticker"   # sticker или emoji по умолчанию

MAX_DURATION="2.99"      # сек, телега требует <= 3
FPS="30"                 # до 30

# Лимиты размера
TARGET_SIZE_STICKER=$((256 * 1024))  # 256 KB
TARGET_SIZE_EMOJI=$((64 * 1024))     # 64 KB

# CRF‑диапазон по умолчанию (если явно не указать)
DEFAULT_CRF_START_STICKER=32
DEFAULT_CRF_START_EMOJI=36

CRF_STEP=2
CRF_MAX=50

################ ПАРСИНГ АРГУМЕНТОВ ################
# Использование:
#   ./gif2tgwebm.sh                 # MODE=sticker, CRF_START=32
#   ./gif2tgwebm.sh emoji           # MODE=emoji,  CRF_START=36
#   ./gif2tgwebm.sh sticker 28      # MODE=sticker, CRF_START=28
#   ./gif2tgwebm.sh emoji 40        # MODE=emoji,  CRF_START=40

MODE="${1:-$DEFAULT_MODE}"
USER_CRF_START="${2:-}"

# Настраиваем лимит и CRF по MODE
if [ "$MODE" = "sticker" ]; then
  TARGET_SIZE="$TARGET_SIZE_STICKER"
  CRF_START="${USER_CRF_START:-$DEFAULT_CRF_START_STICKER}"
  SCALE_FILTER="scale=512:512:force_original_aspect_ratio=decrease"
elif [ "$MODE" = "emoji" ]; then
  TARGET_SIZE="$TARGET_SIZE_EMOJI"
  CRF_START="${USER_CRF_START:-$DEFAULT_CRF_START_EMOJI}"
  SCALE_FILTER="scale=100:100"
else
  echo "Неизвестный MODE: $MODE (ожидается sticker или emoji)"
  exit 1
fi

echo "MODE=$MODE, CRF_START=$CRF_START, TARGET_SIZE=${TARGET_SIZE}B"

################ ПРОВЕРКИ ################

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg не найден. Установи его, например: brew install ffmpeg"
  exit 1
fi

if [ ! -d "$SRC_DIR" ]; then
  echo "Папка с gif не найдена: $SRC_DIR"
  exit 1
fi

mkdir -p "$OUT_DIR"

################ ОСНОВНОЙ ЦИКЛ ################

shopt -s nullglob

for f in "$SRC_DIR"/*.gif; do
  fname="$(basename "$f")"
  out="$OUT_DIR/${fname%.gif}.webm"

  if [ -f "$out" ]; then
    echo "Пропускаю (уже есть): $out"
    continue
  fi

  echo "Конвертирую: $f -> $out (режим: $MODE)"

  crf=$CRF_START

  while : ; do
    tmp_out="${out%.webm}_crf${crf}.webm"

    ffmpeg -y -i "$f" \
      -r "$FPS" -t "$MAX_DURATION" -an \
      -c:v libvpx-vp9 -pix_fmt yuva420p \
      -vf "$SCALE_FILTER" \
      -b:v 0 -crf "$crf" \
      "$tmp_out"

    # macOS stat, если будешь в Linux/WSL — замени на: size=$(stat -c%s "$tmp_out")
    size=$(stat -f%z "$tmp_out")

    if [ "$size" -le "$TARGET_SIZE" ]; then
      mv "$tmp_out" "$out"
      echo "  OK: $out (${size} байт, CRF=$crf)"
      break
    else
      echo "  >${TARGET_SIZE}B (${size} байт при CRF=$crf), пробую CRF=$((crf+CRF_STEP))"
      rm -f "$tmp_out"
      crf=$((crf + CRF_STEP))
      if [ "$crf" -gt "$CRF_MAX" ]; then
        echo "  Не уложился в лимит (последний CRF=$crf). Файл не сохранён."
        rm -f "$tmp_out" || true
        break
      fi
    fi
  done
done

echo "Готово."
