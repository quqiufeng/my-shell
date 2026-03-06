#!/bin/bash
# =============================================================================
# 图像放大脚本 (基于 ESRGAN 超分辨率)
# =============================================================================
#
# 【放大原理】
# ESRGAN (Enhanced Super-Resolution GAN) 是一种深度学习超分辨率算法
# - 核心: 生成器-判别器对抗训练
# - 特点: 能同时恢复细节和提升分辨率，不同于传统插值放大
# - 模型: 2x 表示放大2倍，4x 表示放大4倍
#
# 【性能对比 - 实测数据 (3080 10GB)】
# +----------------------------+-----------+--------+--------+
# | 方法                       | 输入      | 输出   | 耗时   |
# +----------------------------+-----------+--------+--------+
# | 直接生成 (2560x1440)       | -         | 2560x1440 | ~217秒 |
# | 2x ESRGAN (1280→2560)     | 1280x720  | 2560x1440 | ~16秒  |
# | 2x ESRGAN (640→1280)      | 640x360   | 1280x720 | ~4.5秒 |
# | 4x UltraSharp (640→2560)  | 640x360   | 2560x1440 | ~5秒   |
# +----------------------------+-----------+--------+--------+
# 结论: 小图+放大 比直接生成快 6x+
#
# 【模型选择建议】
# +------------------+----------------------------------+--------+
# | 模型             | 特点                             | 推荐   |
# +------------------+----------------------------------+--------+
# | 2x ESRGAN       | 细节保留好，适合人像、产品       | ★★★★★ |
# | 4x UltraSharp   | 速度快，可能过度锐化             | ★★★★☆ |
# +------------------+----------------------------------+--------+
#
# 【小图尺寸计算公式】
# target_width = 2560, target_height = 1440
#
# 方案A: 使用 2x 放大模型
#   small_width = target_width / 2 = 1280
#   small_height = target_height / 2 = 720
#   生成 1280x720 然后 2x 放大 → 2560x1440
#
# 方案B: 使用 4x 放大模型
#   small_width = target_width / 4 = 640
#   small_height = target_height / 4 = 360
#   生成 640x360 然后 4x 放大 → 2560x1440
#
# 【推荐配置 - 最佳平衡】
# | 目标分辨率 | 小图尺寸   | 放大模型 | 总耗时 |
# |------------|------------|----------|--------|
# | 2560x1440  | 1280x720   | 2x ESRGAN | ~20秒 |
# | 1920x1080  | 960x540    | 2x ESRGAN | ~10秒 |
# | 3840x2160  | 960x540    | 4x UltraSharp | ~12秒 |
#
# =============================================================================

# 参数解析
# 用法: ./upscale.sh <input> [output] [scale]
#   scale: 2 (2x放大) 或 4 (4x放大), 默认 2
INPUT_FILE="$1"
OUTPUT_FILE="$2"
SCALE="${3:-2}"

# 验证输入文件
if [ -z "$INPUT_FILE" ]; then
  echo "Usage: ./upscale.sh <input_image> [output_image] [scale]"
  echo ""
  echo "参数说明:"
  echo "  input_image  : 输入图片路径"
  echo "  output_image : 输出图片路径 (可选, 默认: <input>_upscaled.png)"
  echo "  scale        : 放大倍数, 2 或 4 (可选, 默认: 2)"
  echo ""
  echo "示例:"
  echo "  ./upscale.sh image.png              # 2x 放大"
  echo "  ./upscale.sh image.png out.png      # 2x 放大, 指定输出"
  echo "  ./upscale.sh image.png out.png 4     # 4x 放大"
  echo ""
  echo "小图尺寸计算:"
  echo "  目标 2560x1440 + 2x放大 → 生成 1280x720"
  echo "  目标 2560x1440 + 4x放大 → 生成 640x360"
  exit 1
fi

# 验证 scale 参数
if [ "$SCALE" != "2" ] && [ "$SCALE" != "4" ]; then
  echo "Error: scale must be 2 or 4"
  exit 1
fi

# 模型选择
SD_CLI="/opt/stable-diffusion.cpp/bin/sd-cli"
if [ "$SCALE" = "2" ]; then
  UPSCALE_MODEL="/opt/image/2x_ESRGAN.gguf"
  MODEL_NAME="ESRGAN"
else
  UPSCALE_MODEL="/opt/image/4x_UltraSharp.gguf"
  MODEL_NAME="UltraSharp"
fi

# 默认输出文件名: <base>_<model>_<scale>x.png
if [ -z "$OUTPUT_FILE" ]; then
  BASE=$(basename "$INPUT_FILE" .png)
  OUTPUT_FILE="${BASE}_${MODEL_NAME}_${SCALE}x.png"
fi

# 执行放大
$SD_CLI --mode upscale \
  --upscale-model "$UPSCALE_MODEL" \
  -i "$INPUT_FILE" \
  -o "$OUTPUT_FILE"

echo "$OUTPUT_FILE"
