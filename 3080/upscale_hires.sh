#!/bin/bash
# =============================================================================
# 2x 高清放大脚本 (Kohya Hires. fix 方式)
# =============================================================================

INPUT_FILE="$1"
OUTPUT_FILE="$2"
STRENGTH="${3:-0.25}"
STEPS="${4:-12}"

if [ -z "$INPUT_FILE" ]; then
  echo "Usage: ./upscale_hires.sh <input_image> [output] [strength] [steps]"
  exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: Input file not found: $INPUT_FILE"
  exit 1
fi

IMG_SIZE=$(file "$INPUT_FILE" | grep -oP '\d+ x \d+' | head -1)
INPUT_WIDTH=$(echo $IMG_SIZE | cut -d' ' -f1)
INPUT_HEIGHT=$(echo $IMG_SIZE | cut -d' ' -f3)

if [ -z "$INPUT_WIDTH" ] || [ -z "$INPUT_HEIGHT" ]; then
  echo "Error: Cannot detect image size"
  exit 1
fi

TARGET_WIDTH=$((INPUT_WIDTH * 2))
TARGET_HEIGHT=$((INPUT_HEIGHT * 2))

echo "=============================================="
echo "Kohya Hires. fix - 2x img2img"
echo "=============================================="
echo "Input:  ${INPUT_FILE} (${INPUT_WIDTH}x${INPUT_HEIGHT})"
echo "Output: ${TARGET_WIDTH}x${TARGET_HEIGHT}"
echo "Params: strength=$STRENGTH, steps=$STEPS"

if [ -z "$OUTPUT_FILE" ]; then
  BASE=$(basename "$INPUT_FILE" .png)
  BASE=$(basename "$BASE" .jpg)
  OUTPUT_FILE="${BASE}_hires_2x.png"
fi

SD_CLI="$HOME/stable-diffusion.cpp/bin/sd-cli"
MODEL_DIR="/opt/image"

echo ""
echo ">>> Step 1/2: img2img 放大 (到目标分辨率)..."

cd /opt
nohup $SD_CLI \
  --diffusion-model $MODEL_DIR/z_image_turbo-Q8_0.gguf \
  --vae $MODEL_DIR/ae.safetensors \
  --llm $MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf \
  -p "high quality, detailed, masterpiece, best quality, ultra clear, high resolution" \
  -n "blurry, low quality, deformed, bad anatomy, worst quality, blur, haze" \
  --cfg-scale 1.0 \
  --diffusion-fa \
  --cache-mode easycache \
  --scheduler karras \
  --vae-tiling \
  -i "$INPUT_FILE" \
  --strength "$STRENGTH" \
  -H "$TARGET_HEIGHT" \
  -W "$TARGET_WIDTH" \
  --steps "$STEPS" \
  -o "$OUTPUT_FILE" > /dev/null 2>&1 &

PID=$!

while kill -0 $PID 2>/dev/null; do
  sleep 5
done

wait $PID
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  echo "Error: img2img failed with code $EXIT_CODE"
  exit 1
fi

if [ ! -f "$OUTPUT_FILE" ]; then
  echo "Error: img2img output file not found: $OUTPUT_FILE"
  exit 1
fi

echo ""
echo "=============================================="
echo "Done: $OUTPUT_FILE"
echo "=============================================="
