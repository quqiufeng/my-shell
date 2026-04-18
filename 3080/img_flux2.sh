#!/bin/bash

# =============================================================================
# FLUX.2-klein-base-9B 图像生成脚本 - 基于 stable-diffusion.cpp
# =============================================================================
#
# 重要提示：VAE 和 LLM 必须与 FLUX.2 模型严格匹配，否则无法出图或出空白图
#
# =============================================================================
# 模型下载地址及对应关系
# =============================================================================
#
# 1. 扩散模型 (Diffusion Model) - 必须下载
#    下载地址: https://huggingface.co/leejet/FLUX.2-klein-base-9B-GGUF/tree/main
#    推荐文件: flux-2-klein-base-9b-Q4_0.gguf (5.62GB)
#    说明: 这是 leejet 官方为 stable-diffusion.cpp 打包的模型
#
# 2. VAE (变分自编码器) - 必须严格匹配 FLUX.2
#    下载地址: https://huggingface.co/Comfy-Org/flux2-dev/tree/main/split_files/vae
#    推荐文件: flux2-vae.safetensors (321MB)
#    ⚠️ 重要: 必须使用 FLUX.2 专用 VAE，不能用标准 ae.safetensors 或 sdxl_vae.safetensors
#    ⚠️ 错误 VAE 会导致: tensor shape mismatch 或空白图片
#
# 3. LLM 文本编码器 - 必须严格匹配模型版本
#    下载地址: https://huggingface.co/unsloth/Qwen3-8B-GGUF/tree/main
#    推荐文件: Qwen3-8B-Q4_K_M.gguf (5.03GB)
#    ⚠️ 重要: FLUX.2-klein-9B 必须使用 Qwen3-8B，不能用 Qwen3-4B
#    ⚠️ 错误 LLM 会导致: ggml_mul_mat 维度不匹配崩溃
#
# =============================================================================
# 文件对应关系总结
# =============================================================================
#
# FLUX.2-klein-9B 模型套件:
#   ├─ 扩散模型: flux-2-klein-base-9b-Q4_0.gguf
#   ├─ VAE:      flux2-vae.safetensors
#   └─ LLM:      Qwen3-8B-Q4_K_M.gguf
#
# 全部放到: /opt/image/model/ 目录
#
# =============================================================================
# 用法
# =============================================================================
#
#   ./img_flux2.sh [提示词] [输出文件] [宽度] [高度]
#
# 示例:
#   ./img_flux2.sh "A beautiful landscape"
#   ./img_flux2.sh "A sunset" /mnt/e/app/sunset.png 1280 720
#
# FLUX.2 推荐参数:
#   - 尺寸: 1024x1024 (官方推荐最佳)
#   - CFG Scale: 1.0-4.0 (base 模型可用 4.0)
#   - Steps: 4-20 (4步快速, 20步高质量)
#   - 采样器: euler
#
# =============================================================================
# 示例提示词
# =============================================================================
#
# 1. 写实风景
#    PROMPT="masterpiece, best quality, a serene mountain landscape at golden hour, snow-capped peaks reflected in a crystal clear alpine lake, pine forest, dramatic clouds, warm sunlight, photorealistic, 8k uhd"
#    ./img_flux2.sh "$PROMPT" /mnt/e/app/flux2_landscape.png 1280 720
#
# 2. 人物肖像
#    PROMPT="masterpiece, best quality, portrait of a young woman, soft natural lighting, detailed skin texture, bokeh background, professional photography, 85mm lens"
#    ./img_flux2.sh "$PROMPT" /mnt/e/app/flux2_portrait.png 1024 1024
#
# 3. 建筑室内
#    PROMPT="masterpiece, best quality, modern minimalist living room, floor-to-ceiling windows, natural light, warm wood tones, designer furniture, architectural photography"
#    ./img_flux2.sh "$PROMPT" /mnt/e/app/flux2_interior.png 1280 720
#
# =============================================================================

MODEL_DIR="/opt/image/model"

# FLUX.2 模型文件 (请确保这些文件已下载到 MODEL_DIR 目录)
FLUX_MODEL="${FLUX_MODEL:-flux-2-klein-base-9b-Q4_0.gguf}"
FLUX_VAE="${FLUX_VAE:-flux2-vae.safetensors}"
FLUX_LLM="${FLUX_LLM:-Qwen3-8B-Q4_K_M.gguf}"

PROMPT="${1:-A beautiful landscape}"
OUTPUT_FILE="$2"
WIDTH="${3:-1024}"
HEIGHT="${4:-1024}"

# 强制分辨率限制：FLUX.2-klein-9B 官方推荐 1024x1024
# 在 RTX 3080 10GB 上超过 1024x1024 可能崩溃
if [ "$WIDTH" -gt 1024 ] || [ "$HEIGHT" -gt 1024 ]; then
  echo "警告: 分辨率 ${WIDTH}x${HEIGHT} 超过安全范围，强制调整为 1024x1024"
  WIDTH=1024
  HEIGHT=1024
fi

NEGATIVE_PROMPT="${NEGATIVE_PROMPT:-}"

# FLUX 优化参数
# 避免过拟合参数 (可根据需要调整)
CFG_SCALE="${CFG_SCALE:-1.5}"
STEPS="${STEPS:-20}"
SAMPLER="${SAMPLER:-euler_a}"

OUTPUT_DIR="$HOME"

if [[ "$OUTPUT_FILE" == *"/"* ]]; then
  OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
  OUTPUT="$(basename "$OUTPUT_FILE")"
elif [ -n "$OUTPUT_FILE" ]; then
  OUTPUT="$OUTPUT_FILE"
else
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  MD5=$(echo "$PROMPT" | md5sum | cut -c1-8)
  OUTPUT="flux2_${TIMESTAMP}_${MD5}.png"
fi

mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo "  FLUX.2 Image Generation"
echo "========================================"
echo "Prompt: $PROMPT"
echo "Negative: ${NEGATIVE_PROMPT:-(none)}"
echo "Size: ${WIDTH}x${HEIGHT}"
echo "CFG Scale: $CFG_SCALE"
echo "Steps: $STEPS"
echo "Sampler: $SAMPLER"
echo "Output: $OUTPUT_DIR/$OUTPUT"
echo "========================================"

/home/dministrator/stable-diffusion.cpp/bin/sd-cli \
  --diffusion-model "$MODEL_DIR/$FLUX_MODEL" \
  --vae "$MODEL_DIR/$FLUX_VAE" \
  --llm "$MODEL_DIR/$FLUX_LLM" \
  -p "$PROMPT" \
  -n "$NEGATIVE_PROMPT" \
  --cfg-scale "$CFG_SCALE" \
  --sampling-method "$SAMPLER" \
  --diffusion-fa \
  --vae-tiling \
  -H "$HEIGHT" -W "$WIDTH" \
  --steps "$STEPS" \
  -s "$RANDOM" \
  -o "$OUTPUT_DIR/$OUTPUT"

echo "Image saved to: $OUTPUT_DIR/$OUTPUT"
