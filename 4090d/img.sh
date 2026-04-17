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
# 模型配置
# =============================================================================
# 当前使用 Z-Image-Turbo, 经测试在 RTX 4090D 24GB 上可正常出大图。
# 所需模型文件:
#   - diffusion-model: z_image_turbo-Q8_0.gguf
#   - vae:             ae.safetensors
#   - llm:             Qwen3-4B-Instruct-2507-Q4_K_M.gguf
#
# =============================================================================
# 显存适配建议 (以 RTX 3080 10GB 为例)
# =============================================================================
# 模型权重占用估算:
#   - z_image_turbo-Q8_0.gguf / z-image-Q8_0.gguf : ~7.2GB  (24GB显存推荐)
#   - z-image-Q6_K.gguf                           : ~6.1GB  (很勉强, 易OOM)
#   - z-image-Q5_K_M.gguf                         : ~5.6GB  (10GB可用, 但2560x1440可能爆显存)
#   - z-image-Q5_K_S.gguf                         : ~5.3GB  (10GB可用)
#   - z-image-Q4_K_M.gguf                         : ~5.1GB  (10GB甜点选择, 推荐)
#   - z-image-Q4_K_S.gguf                         : ~4.8GB  (10GB速度快)
#   - z-image-Q3_K_M.gguf                         : ~4.6GB  (质量下降明显)
#   - z-image-Q2_K.gguf                           : ~4.0GB  (仅应急)
#
# 加上 LLM (2.5GB) + VAE (0.1GB) + CUDA 开销 (~1GB) + compute buffer:
#   - Q8_0:  权重 9.8GB -> 10GB 显卡基本跑不了大图
#   - Q5_K_M: 权重 8.2GB -> 10GB 显卡跑 1024x1024 可以, 2560x1440 较悬
#   - Q4_K_M: 权重 7.7GB -> 10GB 显卡配合 --vae-tiling 跑 2560x1140 较稳
#
# 10GB 显存推荐配置:
#   1. 优先使用 z-image-Q4_K_M.gguf (精度/速度/显存平衡最佳)
#   2. 若追求更高精度可尝试 z-image-Q5_K_M.gguf, 但建议分辨率不超过 1280x720
#   3. 大图需求可降到 1024x1024 或加 --offload-to-cpu
# =============================================================================

MODEL_DIR="/opt/image/model"

PROMPT="${1:-A beautiful landscape}"
OUTPUT_FILE="$2"
WIDTH="${3:-2560}"
HEIGHT="${4:-1140}"

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

# 使用 Z-Image-Turbo
/opt/stable-diffusion.cpp/bin/sd-cli \
  --diffusion-model $MODEL_DIR/z_image_turbo-Q8_0.gguf \
  --vae $MODEL_DIR/ae.safetensors \
  --llm $MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf \
  -p "$PROMPT" \
  -n "$NEGATIVE_PROMPT" \
  --cfg-scale 1.0 \
  --sampling-method euler \
  --diffusion-fa \
  --vae-tiling \
  -H $HEIGHT -W $WIDTH \
  --steps 20 \
  -s $RANDOM \
  -o "$OUTPUT_DIR/$OUTPUT"

echo "Image saved to: $OUTPUT_DIR/$OUTPUT"

# =============================================================================
# 提示词范例
# =============================================================================
#
# 1. 风景壁纸 (2560x1140)
#    ./img.sh "Swiss Alps, majestic mountain peaks, snow-capped mountains, crystal clear lake, green valleys, scenic landscape, dramatic clouds, golden sunlight, photorealistic, high detail, 8K quality" ~/alps.png 2560 1140
#
# 2. 写实肖像 (1024x1024 或 2560x1440)
#    PROMPT="a beautiful young lady in her early 20s, healthy natural skin with subtle texture, soft even skin tone, slight natural flush on cheeks, moist natural lips, clear bright eyes with natural catchlights, soft diffused window light from 45 degrees, shallow depth of field, shot on Canon EOS R5 with 85mm f/1.2 lens, RAW photo, professional beauty photography, 8K UHD, photorealistic"
#    NEGATIVE="oily skin, acne, blemishes, wrinkles, dark circles, redness, rosacea, sunburn, uneven skin tone, excessive pores, dry flaky skin, scars, freckles, moles, skin disease, artificial smooth skin, plastic skin, doll-like skin, overexposed, oversaturated"
#    ./img.sh "$PROMPT" ~/portrait.png 1024 1024
#
# =============================================================================
