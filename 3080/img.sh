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
# 当前使用 Z-Image Q4_K_M, 适配 RTX 3080 10GB 显存。
# 所需模型文件:
#   - diffusion-model: z-image-Q4_K_M.gguf
#   - vae:             ae.safetensors
#   - llm:             Qwen3-4B-Instruct-2507-Q4_K_M.gguf
#
# =============================================================================
# 显存适配建议 (本机 RTX 3080 10GB)
# =============================================================================
# 模型权重占用估算:
#   - z-image-Q5_K_M.gguf : ~5.2GB (10GB可用, 但2560x1440可能爆显存)
#   - z-image-Q4_K_M.gguf : ~4.8GB (10GB甜点选择, 推荐)
#   - z-image-Q4_K_S.gguf : ~4.5GB (10GB速度快)
#
# 加上 LLM (~2.4GB) + VAE (~0.3GB) + CUDA 开销 (~1GB) + compute buffer:
#   - Q5_K_M: 权重 ~8.2GB -> 10GB 显卡跑 1024x1024 可以, 2560x1440 较悬
#   - Q4_K_M: 权重 ~7.7GB -> 10GB 显卡配合 --vae-tiling 跑 1280x720 较稳
#
# 10GB 显存推荐配置:
#   1. 优先使用 z-image-Q4_K_M.gguf (精度/速度/显存平衡最佳)
#   2. 若追求更高精度可尝试 z-image-Q5_K_M.gguf, 但建议分辨率不超过 1024x1024
#   3. 大图需求可降到 1024x1024 或加 --offload-to-cpu
#
# 分辨率上限说明:
#   - 1024x1024  = 1,048,576 像素 (最安全, 质量与速度平衡)
#   - 1280x720   = 921,600   像素 (安全, 风景壁纸推荐)
#   - 1280x1280  = 1,638,400 像素 (极限, 可能触发OOM)
#   - 1440x1440  = 2,073,600 像素 (不建议, 大概率OOM)
#   - 1920x1080  = 2,073,600 像素 (不建议, 大概率OOM)
#   - 2560x1440  = 3,686,400 像素 (必须加 --offload-to-cpu, 速度极慢)
#
# 显存占用公式 (估算):
#   显存 ≈ 模型权重 + (像素数 × 精度系数) + CUDA开销
#   其中精度系数: FP16约0.008, Q4约0.002
#   10GB显卡在Q4_K_M下, 像素数超过150万即进入危险区
# =============================================================================

MODEL_DIR="/opt/image/model"

PROMPT="${1:-A beautiful landscape}"
OUTPUT_FILE="$2"
WIDTH="${3:-1280}"
HEIGHT="${4:-720}"

# 负面提示词（可通过环境变量传入，默认为空）
NEGATIVE_PROMPT="${NEGATIVE_PROMPT:-}"

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

# 确保输出目录存在
mkdir -p "$OUTPUT_DIR"

echo "Generating image..."
echo "Prompt: $PROMPT"
echo "Negative: ${NEGATIVE_PROMPT:-(none)}"
echo "Size: ${WIDTH}x${HEIGHT}"
echo "Output: $OUTPUT_DIR/$OUTPUT"

# 使用 Z-Image Q4_K_M (10GB显存适配版)
/opt/stable-diffusion.cpp/bin/sd-cli \
  --diffusion-model "$MODEL_DIR/z-image-Q4_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  -p "$PROMPT" \
  -n "$NEGATIVE_PROMPT" \
  --cfg-scale 1.0 \
  --sampling-method euler \
  --diffusion-fa \
  --vae-tiling \
  -H "$HEIGHT" -W "$WIDTH" \
  --steps 20 \
  -s "$RANDOM" \
  -o "$OUTPUT_DIR/$OUTPUT"

echo "Image saved to: $OUTPUT_DIR/$OUTPUT"

# =============================================================================
# 提示词范例
# =============================================================================
#
# 1. 风景壁纸 (1280x720, 10GB显存安全分辨率)
#    ./img.sh "Swiss Alps, majestic mountain peaks, snow-capped mountains, crystal clear lake, green valleys, scenic landscape, dramatic clouds, golden sunlight, photorealistic, high detail, 8K quality" ~/alps.png 1280 720
#
# 2. 写实肖像 (1024x1024, 10GB显存推荐)
#    PROMPT="a beautiful young lady in her early 20s, healthy natural skin with subtle texture, soft even skin tone, slight natural flush on cheeks, moist natural lips, clear bright eyes with natural catchlights, soft diffused window light from 45 degrees, shallow depth of field, shot on Canon EOS R5 with 85mm f/1.2 lens, RAW photo, professional beauty photography, 8K UHD, photorealistic"
#    NEGATIVE="oily skin, acne, blemishes, wrinkles, dark circles, redness, rosacea, sunburn, uneven skin tone, excessive pores, dry flaky skin, scars, freckles, moles, skin disease, artificial smooth skin, plastic skin, doll-like skin, overexposed, oversaturated"
#    ./img.sh "$PROMPT" ~/portrait.png 1024 1024
#
# 注意: 10GB显存安全分辨率 1280x720, 绝对上限 1280x1280
#       若需 1920x1080 或更大请加 --offload-to-cpu 参数 (速度会显著下降)
#
# =============================================================================
