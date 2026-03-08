#!/bin/bash
# =============================================================================
# 2x 高清放大脚本 (ESRGAN + FLUX 细节重绘)
# =============================================================================
#
# 【原理】
# Step 1: ESRGAN 物理放大 (2x) - 快速拉伸尺寸
# Step 2: FLUX 细节重绘 - 利用 Transformer 架构补强纹理
#
# 【优势】
# - 显存错峰: 分步处理，3080 10GB 可轻松运行
# - 细节丰富: FLUX 重绘避免"塑料感"
# - 速度快: ESRGAN ~20秒 + FLUX ~2分钟
#
# 【用法】
#   ./upscale_hires.sh <input> [output] [strength] [steps]
#
# 【参数】
#   strength: 重绘幅度 (默认 0.2, 0.1-0.3 保真, 0.3-0.5 细节多)
#   steps: FLUX 步数 (默认 4, Schnell 4步最佳)
#
# =============================================================================

SD_CLI="$HOME/stable-diffusion.cpp/bin/sd-cli"

INPUT_FILE="$1"
OUTPUT_FILE="$2"
STRENGTH="${3:-0.2}"
STEPS="${4:-4}"

# 验证输入
if [ -z "$INPUT_FILE" ]; then
  echo "Usage: ./upscale_hires.sh <input_image> [output] [strength] [steps]"
  echo ""
  echo "参数:"
  echo "  input_image : 输入图片 (必需)"
  echo "  output      : 输出图片 (可选, 默认: <input>_hires.png)"
  echo "  strength    : 重绘幅度 (可选, 默认: 0.2)"
  echo "  steps       : 步数 (可选, 默认: 4)"
  echo ""
  echo "示例:"
  echo "  ./upscale_hires.sh image.png                    # 2x 放大"
  echo "  ./upscale_hires.sh image.png out.png 0.2 4   # 重绘0.2, 4步"
  exit 1
fi

# 检查输入文件
if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: Input file not found: $INPUT_FILE"
  exit 1
fi

# 获取输入图片尺寸
IMG_SIZE=$(file "$INPUT_FILE" | grep -oP '\d+ x \d+' | head -1)
INPUT_WIDTH=$(echo $IMG_SIZE | cut -d' ' -f1)
INPUT_HEIGHT=$(echo $IMG_SIZE | cut -d' ' -f3)

if [ -z "$INPUT_WIDTH" ] || [ -z "$INPUT_HEIGHT" ]; then
  echo "Error: Cannot detect image size"
  exit 1
fi

# 计算 目标尺寸 (固定2x)
TARGET_WIDTH=$((INPUT_WIDTH * 2))
TARGET_HEIGHT=$((INPUT_HEIGHT * 2))

# 默认输出文件名
if [ -z "$OUTPUT_FILE" ]; then
  BASE=$(basename "$INPUT_FILE" .png)
  OUTPUT_FILE="${BASE}_hires_2x.png"
fi

TEMP_FILE="/tmp/temp_upscaled_$$.png"

echo "=============================================="
echo "ESRGAN + FLUX 2x 放大"
echo "=============================================="
echo "Input:  ${INPUT_FILE} (${INPUT_WIDTH}x${INPUT_HEIGHT})"
echo "Output: ${TARGET_WIDTH}x${TARGET_HEIGHT}"
echo "Params: strength=$STRENGTH, steps=$STEPS"
echo ""

# Step 1: ESRGAN 2x 物理放大 (自动从输入尺寸放大2倍)
echo ">>> Step 1/2: ESRGAN 2x 物理放大..."
cd /opt

$SD_CLI \
  -M upscale \
  --diffusion-model /opt/image/flux1-schnell-Q4_K_S.gguf \
  --upscale-model /opt/image/2x_ESRGAN.gguf \
  -i "$INPUT_FILE" \
  --upscale-repeats 1 \
  -o "$TEMP_FILE"

if [ $? -ne 0 ]; then
  echo "Error: ESRGAN upscale failed"
  exit 1
fi

echo "    ESRGAN 完成: $TEMP_FILE"

echo ""
echo "=============================================="
echo "Done: $OUTPUT_FILE"
echo "=============================================="

mv "$TEMP_FILE" "$OUTPUT_FILE"

# =============================================================================
# 【遇到的问题及解决方案】
# =============================================================================
#
# 问题 1: FLUX img2img 重绘 OOM
#   现象: 3080 10GB 显存在 FLUX img2img 阶段报错 "out of memory"
#   原因: ESRGAN 输出 5120x2880 后再 img2img 显存需求太大
#   解决: 去掉 FLUX img2img 第二步，只用 ESRGAN 放大
#
# 问题 2: ESRGAN 放大到 5120x2880
#   现象: 指定 -W -H 参数时 ESRGAN 会先放大到指定尺寸的 2 倍
#   原因: ESRGAN 本身是 2x 模型，指定目标尺寸会导致内部计算 4x
#   解决: 不指定 -W -H 参数，让 ESRGAN 自动根据输入尺寸放大 2 倍
#
# 现状:
#   - 小图生成: 使用 img.sh (FLUX 模型，4 步)
#   - 放大: 只用 ESRGAN (约 20 秒)，不再使用 FLUX img2img 重绘
#   - 如需更好效果，可能需要更大显存 (16GB+)
#
# =============================================================================
