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
# 重要备注: FLUX.1-dev 兼容性问题
# =============================================================================
# 经测试 (2025-04-17, stable-diffusion.cpp master-572-1b4e9be-2-ga564fdf):
# - FLUX.1-dev (12B) 的 GGUF 版本在 stable-diffusion.cpp 上加载成功,
#   但生成输出为空白图 (32KB~63KB), 无论使用 leejet 还是 unsloth 的 GGUF
#   转换版本, 也无论是否开启 Flash Attention。
# - 测试环境: RTX 3080 10GB 和 RTX 4090D 24GB 均出现同样问题,
#   排除显存不足原因。
# - 目前稳定可用的替代方案: FLUX.2-klein-4b (4B 参数),
#   在 stable-diffusion.cpp 上兼容性良好, 可正常出图。
# - 若需使用 FLUX.1-dev, 建议改用 ComfyUI 或 diffusers 原生框架。
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

# 4090D 24GB 显存优化参数
# 使用 FLUX.2-klein-4b (4B), 在 stable-diffusion.cpp 上兼容性最佳
/opt/stable-diffusion.cpp/bin/sd-cli \
  --diffusion-model $MODEL_DIR/flux-2-klein-4b-Q8_0.gguf \
  --vae $MODEL_DIR/ae_flux32.safetensors \
  --llm $MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf \
  -p "$PROMPT" \
  --prediction flux2_flow \
  --guidance 4.0 \
  --diffusion-fa \
  --sampling-method euler \
  --scheduler simple \
  -H $HEIGHT -W $WIDTH \
  --steps 30 \
  -s $RANDOM \
  -o "$OUTPUT_DIR/$OUTPUT" > /dev/null 2>&1

echo "Image saved to: $OUTPUT_DIR/$OUTPUT"
