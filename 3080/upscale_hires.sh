#!/bin/bash
# =============================================================================
# 2x 高清放大脚本 - 先放大再细修
# =============================================================================
# 流程：
#   Step 1: 放大2倍到目标分辨率
#   Step 2: img2img丰富细节
#
# 参数:
#   $1 输入图片
#   $2 输出图片(可选)
#   $3 strength(可选，默认0.3)
#   $4 steps(可选，默认20)
#
# 示例:
#   ./upscale_hires.sh input.png output.png 0.3 20

INPUT_FILE="$1"
OUTPUT_FILE="$2"
STRENGTH="${3:-0.3}"
STEPS="${4:-20}"

if [ -z "$INPUT_FILE" ]; then
  echo "Usage: $0 <input_image> [output] [strength] [steps]"
  echo "示例: $0 1.png 1_hires.png 0.3 20"
  exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: Input file not found: $INPUT_FILE"
  exit 1
fi

# 检测输入尺寸
IMG_SIZE=$(file "$INPUT_FILE" | grep -oP '\d+ x \d+' | head -1)
INPUT_WIDTH=$(echo $IMG_SIZE | cut -d' ' -f1)
INPUT_HEIGHT=$(echo $IMG_SIZE | cut -d' ' -f3)

if [ -z "$INPUT_WIDTH" ] || [ -z "$INPUT_HEIGHT" ]; then
  echo "Error: Cannot detect image size"
  exit 1
fi

# 目标尺寸 = 输入尺寸 × 2
TARGET_WIDTH=$((INPUT_WIDTH * 2))
TARGET_HEIGHT=$((INPUT_HEIGHT * 2))

echo "=============================================="
echo "2x 高清放大 - 先放大再细修"
echo "=============================================="
echo "Input:  ${INPUT_FILE} (${INPUT_WIDTH}x${INPUT_HEIGHT})"
echo "Output: ${TARGET_WIDTH}x${TARGET_HEIGHT}"
echo "Params: strength=$STRENGTH, steps=$STEPS"

# 默认输出文件名
if [ -z "$OUTPUT_FILE" ]; then
  BASE=$(basename "$INPUT_FILE" .png)
  BASE=$(basename "$BASE" .jpg)
  OUTPUT_FILE="${BASE}_hires_2x.png"
fi

SD_CLI="$HOME/stable-diffusion.cpp/bin/sd-cli"
MODEL_DIR="/opt/image"

# 临时文件
TEMP_UPSCALE="/tmp/upscale_temp_$$.png"

echo ""
echo ">>> Step 1/2: 放大到 ${TARGET_WIDTH}x${TARGET_HEIGHT} ..."

cd /opt
nohup $SD_CLI \
  --diffusion-model $MODEL_DIR/z_image_turbo-Q8_0.gguf \
  --vae $MODEL_DIR/ae.safetensors \
  --llm $MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf \
  -p "high quality, detailed, masterpiece, best quality, ultra clear" \
  -n "blurry, low quality, deformed, bad anatomy, worst quality, blur" \
  --cfg-scale 1.0 \
  --diffusion-fa \
  --cache-mode easycache \
  --scheduler karras \
  --vae-tiling \
  -i "$INPUT_FILE" \
  --strength 0.1 \
  -H "$TARGET_HEIGHT" \
  -W "$TARGET_WIDTH" \
  --steps 8 \
  -o "$TEMP_UPSCALE" > /dev/null 2>&1 &

PID=$!
while kill -0 $PID 2>/dev/null; do
  sleep 5
done
wait $PID

if [ $? -ne 0 ] || [ ! -f "$TEMP_UPSCALE" ]; then
  echo "Error: Step 1 failed"
  exit 1
fi

echo ">>> Step 2/2: img2img 细修细节 ..."

nohup $SD_CLI \
  --diffusion-model $MODEL_DIR/z_image_turbo-Q8_0.gguf \
  --vae $MODEL_DIR/ae.safetensors \
  --llm $MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf \
  -p "high quality, detailed, masterpiece, best quality, ultra clear, sharp, crisp" \
  -n "blurry, low quality, deformed, bad anatomy, worst quality, blur, haze" \
  --cfg-scale 1.0 \
  --diffusion-fa \
  --cache-mode easycache \
  --scheduler karras \
  --vae-tiling \
  -i "$TEMP_UPSCALE" \
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

# 清理临时文件
rm -f "$TEMP_UPSCALE"

if [ $? -ne 0 ] || [ ! -f "$OUTPUT_FILE" ]; then
  echo "Error: Step 2 failed"
  exit 1
fi

echo ""
echo "=============================================="
echo "Done: $OUTPUT_FILE"
echo "=============================================="
