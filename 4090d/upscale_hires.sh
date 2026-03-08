#!/bin/bash
# =============================================================================
# 2x 高清放大脚本 (Kohya Hires. fix 方式) - Fixed Version
# =============================================================================
#
# 【重要】
# 本脚本耗时较长 (约 6-10 分钟)，建议直接运行会自动后台执行
#
# 用法:
#   ./upscale_hires_4090d.sh <input> [output] [strength] [steps]
#
# 查询进度:
#
# 查看 PID:
#   ps aux | grep sd-cli
#
# =============================================================================
#
# 【原理 - Kohya Hires. fix 两步走】
# 
# 核心思想: 结合 img2img 重绘和 ESRGAN 锐化的优点
#
# Step 1: img2img 放大 (2x)
#   - 将输入图片放大 2 倍到目标分辨率
#   - 在 latent space 进行去噪重绘
#   - strength 控制重绘程度:
#     * 低 (0.1-0.3): 保留原图结构,轻微改善
#     * 中 (0.3-0.5): 平衡细节和保真
#     * 高 (0.5-0.8): 改变较大,可能不像原图
#
# Step 2: ImageMagick 锐化 (保持尺寸,不再放大)
#   - 保持目标分辨率不变
#   - USM 锐化增强清晰度
#   - 弥补 img2img 可能产生的模糊
#
# 【为什么这样效果好?】
# - img2img: 利用 SD 的先验知识"想象"细节
# - ESRGAN: 纯视觉锐化,无"幻觉"
# - 两者结合: 细节丰富 + 边缘清晰
#
# 【输入输出示例】
# | 输入尺寸      | 输出尺寸      | 放大倍数 |
# |---------------|---------------|----------|
# | 640x360       | 1280x720     | 2x       |
# | 1280x720      | 2560x1440    | 2x       |
# | 1920x1080     | 3840x2160    | 2x       |
#
# 【参数推荐】
# | 场景       | strength | steps | 耗时   |
# |------------|----------|-------|--------|
# | 人像保真   | 0.3      | 8-12  | ~5分钟 |
# | 人像精细   | 0.4      | 12    | ~7分钟 |
# | 风景重绘   | 0.4-0.5  | 12-16 | ~7分钟 |
#
# 【注意】
# - 需要较强显卡 (建议 16GB+ 显存)
# - 1280x720 输入约 7分钟
#
# =============================================================================

# 检查 ImageMagick 是否安装
if ! command -v convert &> /dev/null && ! command -v convert-im6.q16 &> /dev/null; then
  echo "Installing ImageMagick..."
  apt-get update && apt-get install -y imagemagick
fi

# 兼容不同的 ImageMagick 命令名
if command -v convert-im6.q16 &> /dev/null; then
  CONVERT_CMD="convert-im6.q16"
elif command -v convert &> /dev/null; then
  CONVERT_CMD="convert"
else
  echo "Error: ImageMagick not found"
  exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="$2"
STRENGTH="${3:-0.25}"   # 0.25: 保真度高，不易变糊（0.4容易失真）
STEPS="${4:-20}"       # 20: 步数越多细节越好（默认12）

# 验证输入
if [ -z "$INPUT_FILE" ]; then
  echo "Usage: ./upscale_hires_4090d.sh <input_image> [output] [strength] [steps]"
  echo ""
  echo "参数:"
  echo "  input_image : 输入图片 (必需)"
  echo "  output      : 输出图片 (可选, 默认: <input>_hires.png)"
  echo "  strength    : 重绘幅度 (可选, 默认: 0.4)"
  echo "  steps       : 步数 (可选, 默认: 12)"
  echo ""
  echo "示例:"
  echo "  ./upscale_hires_4090d.sh image.png                    # 2x 放大"
  echo "  ./upscale_hires_4090d.sh image.png out.png 0.4 12   # 重绘0.4, 12步"
  echo "  ./upscale_hires_4090d.sh image.png out.png 0.3 8    # 快速模式"
  exit 1
fi

# 检查输入文件 - 支持绝对路径和相对路径
if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: Input file not found: $INPUT_FILE"
  echo "当前目录: $(pwd)"
  echo "可用文件:"
  ls -la *.png *.jpg *.jpeg 2>/dev/null || echo "无图片文件"
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
SCALE=2

echo "=============================================="
echo "Kohya Hires. fix - 2x img2img + Sharp"
echo "=============================================="
echo "Input:  ${INPUT_FILE} (${INPUT_WIDTH}x${INPUT_HEIGHT})"
echo "Output: ${TARGET_WIDTH}x${TARGET_HEIGHT} (${SCALE}x)"
echo "Params: strength=$STRENGTH, steps=$STEPS"

# 默认输出文件名
if [ -z "$OUTPUT_FILE" ]; then
  BASE=$(basename "$INPUT_FILE" .png)
  BASE=$(basename "$BASE" .jpg)
  BASE=$(basename "$BASE" .jpeg)
  OUTPUT_FILE="${BASE}_hires_2x.png"
fi

SD_CLI="/opt/stable-diffusion.cpp/bin/sd-cli"

echo ""
echo ">>> Step 1/2: img2img 放大 (到目标分辨率)..."

cd /opt
nohup $SD_CLI \
  --diffusion-model /opt/gguf/image/z_image_turbo-Q8_0.gguf \
  --vae /opt/gguf/image/ae.safetensors \
  --llm /opt/gguf/image/Qwen3-4B-Instruct-2507-Q4_K_M.gguf \
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

# 检查 img2img 输出文件
if [ ! -f "$OUTPUT_FILE" ]; then
  echo "Error: img2img output file not found: $OUTPUT_FILE"
  echo "日志:"
  cat "$LOG_FILE"
  exit 1
fi

echo ">>> Step 2/2: ImageMagick 锐化 (保持尺寸)..."

# 锐化已禁用，如需开启请取消注释
# $CONVERT_CMD "$OUTPUT_FILE" -unsharp 0.3x0.5+0.8+0 -gravity center -quality 95 "$OUTPUT_FILE"

if [ $? -ne 0 ]; then
  echo "Warning: ImageMagick sharpening failed, trying alternative..."
  # 备用方案: 使用简单的锐化
  $CONVERT_CMD "$OUTPUT_FILE" -sharpen 2x1 "$OUTPUT_FILE" || echo "Warning: Sharpening optional, continuing..."
fi

echo ""
echo "=============================================="
echo "Done: $OUTPUT_FILE"
echo "=============================================="
