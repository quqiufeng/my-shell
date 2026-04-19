#!/bin/bash
# =============================================================================
# HiRes 高清处理脚本
# =============================================================================
# 流程：
#   1. 用 sd-cli 做 img2img 优化（同分辨率）
#   2. 用 ESRGAN 放大到目标分辨率
# =============================================================================

set -e

# 参数
INPUT_IMAGE="$1"
PROMPT="${2:-masterpiece, best quality, ultra-detailed}"
OUTPUT_IMAGE="${3:-output_hires.png}"
STRENGTH="${4:-0.4}"
STEPS="${5:-10}"

# 模型路径
MODEL_DIR="/opt/image/model"
DIFFUSION_MODEL="$MODEL_DIR/z_image_turbo-Q5_K_M.gguf"
VAE="$MODEL_DIR/ae.safetensors"
LLM="$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
ESRGAN_MODEL="/opt/image/2x_ESRGAN.gguf"

# 检查输入
if [ ! -f "$INPUT_IMAGE" ]; then
    echo "错误：输入图片不存在: $INPUT_IMAGE"
    exit 1
fi

# 获取输入图片尺寸
WIDTH=$(identify -format "%w" "$INPUT_IMAGE")
HEIGHT=$(identify -format "%h" "$INPUT_IMAGE")

echo "========================================"
echo "HiRes 高清处理"
echo "========================================"
echo "输入图片: $INPUT_IMAGE (${WIDTH}x${HEIGHT})"
echo "提示词: $PROMPT"
echo "强度: $STRENGTH"
echo "步数: $STEPS"
echo "输出: $OUTPUT_IMAGE"
echo ""

# 临时文件
TEMP_DIR=$(mktemp -d)
TEMP_OPTIMIZED="$TEMP_DIR/optimized.png"

echo "[1/2] 正在优化图片质量 (img2img)..."
cd ~/stable-diffusion.cpp

./bin/sd-cli \
    --diffusion-model "$DIFFUSION_MODEL" \
    --vae "$VAE" \
    --llm "$LLM" \
    -p "$PROMPT" \
    -i "$INPUT_IMAGE" \
    --strength "$STRENGTH" \
    --steps "$STEPS" \
    --cfg-scale 1.01 \
    --sampling-method euler \
    --diffusion-fa \
    --vae-tiling \
    --vae-tile-size 64x64 \
    -o "$TEMP_OPTIMIZED"

echo ""
echo "[2/2] 正在放大图片 (ESRGAN 2x)..."

./bin/sd-cli \
    -M upscale \
    --upscale-model "$ESRGAN_MODEL" \
    --upscale-repeats 1 \
    -i "$TEMP_OPTIMIZED" \
    -o "$OUTPUT_IMAGE"

# 清理临时文件
rm -rf "$TEMP_DIR"

echo ""
echo "========================================"
echo "完成！"
echo "输出: $OUTPUT_IMAGE"
echo "========================================"
