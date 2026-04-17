#!/bin/bash

# =============================================================================
# 图像生成脚本 - 基于 stable-diffusion.cpp
# =============================================================================
#
# 用法:
#   ./img.sh [提示词] [输出文件] [宽度] [高度]
#
# 示例:
#   ./img.sh "A beautiful landscape"
#   ./img.sh "A sunset" /opt/sunset.png 2560 1440
#
# =============================================================================
# 模型配置说明
# =============================================================================
# 当前默认使用 FLUX.1-dev (12B), 经测试在 RTX 4090D 24GB 上可正常出图。
# 所需模型文件:
#   - diffusion-model: flux1-dev-q4_k.gguf
#   - vae:             ae.safetensors
#   - clip_l:          clip_l.safetensors
#   - t5xxl:           t5-v1_1-xxl-encoder-Q5_K_M.gguf
#
# 若 VRAM 不足或追求速度, 可切换到 FLUX.2-klein-4b (4B) 配置:
#   - diffusion-model: flux-2-klein-4b-Q8_0.gguf
#   - vae:             ae_flux32.safetensors
#   - llm:             Qwen3-4B-Instruct-2507-Q4_K_M.gguf
# =============================================================================

MODEL_DIR="/opt/image/model"

PROMPT="${1:-A beautiful landscape}"
OUTPUT_FILE="$2"
WIDTH="${3:-1920}"
HEIGHT="${4:-1080}"

OUTPUT_DIR="$HOME"

if [[ "$OUTPUT_FILE" == *"/"* ]]; then
  OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
  OUTPUT="$(basename "$OUTPUT_FILE")"
elif [ -n "$OUTPUT_FILE" ]; then
  OUTPUT="$OUTPUT_FILE"
else
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  MD5=$(echo "$PROMPT" | md5sum | cut -c1-8)
  OUTPUT="${TIMESTAMP}_${MD5}.png"
fi

echo "Generating image..."
echo "Prompt: $PROMPT"
echo "Size: ${WIDTH}x${HEIGHT}"
echo "Output: $OUTPUT_DIR/$OUTPUT"

# 使用 FLUX.1-dev (质量最高)
/opt/stable-diffusion.cpp/bin/sd-cli \
  --diffusion-model $MODEL_DIR/flux1-dev-q4_k.gguf \
  --vae $MODEL_DIR/ae.safetensors \
  --clip_l $MODEL_DIR/clip_l.safetensors \
  --t5xxl $MODEL_DIR/t5-v1_1-xxl-encoder-Q5_K_M.gguf \
  -p "$PROMPT" \
  --cfg-scale 1.0 \
  --sampling-method euler \
  --scheduler simple \
  --diffusion-fa \
  -H $HEIGHT -W $WIDTH \
  --steps 30 \
  -s $RANDOM \
  -o "$OUTPUT_DIR/$OUTPUT" > /dev/null 2>&1

echo "Image saved to: $OUTPUT_DIR/$OUTPUT"
