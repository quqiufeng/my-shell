#!/bin/bash
set -euo pipefail

# =============================================================================
# 图像生成脚本 - 基于 stable-diffusion.cpp (快速版，无 HiRes Fix)
# =============================================================================
#
# 【用法】
#   ./img.sh [提示词] [输出文件] [宽度] [高度]
#
# 【示例】
#   ./img.sh "A beautiful landscape"
#   ./img.sh "A sunset" /mnt/e/app/sunset.png 1280 720
#
# 【环境变量覆盖】
#   SAMPLING_METHOD=euler CFG_SCALE=3.2 STEPS=25 ./img.sh "..."
#
# =============================================================================

# 颜色定义
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m"

# 模型路径
# 图像生成模型放在 /data/models/image/ 子目录下
MODEL_DIR="${MODEL_DIR:-/data/models/image}"
SD_CLI="${SD_CLI:-/opt/stable-diffusion.cpp/bin/sd-cli}"
DIFFUSION_MODEL="$MODEL_DIR/z-image-turbo-Q6_K.gguf"
VAE_MODEL="$MODEL_DIR/ae.safetensors"
LLM_MODEL="$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf"

PROMPT="${1:-A beautiful landscape}"
OUTPUT_FILE="${2:-}"
WIDTH="${3:-1280}"
HEIGHT="${4:-720}"

# 展开 ~ 路径
if [[ "$OUTPUT_FILE" == ~* ]]; then
    OUTPUT_FILE="${HOME}${OUTPUT_FILE:1}"
fi

# =============================================================================
# 预检查
# =============================================================================
echo "========================================"
echo "  Pre-check"
echo "========================================"

if [ ! -f "$SD_CLI" ]; then echo -e "${RED}Error: sd-cli not found: $SD_CLI${NC}"; exit 1; fi
if [ ! -x "$SD_CLI" ]; then echo -e "${RED}Error: sd-cli not executable: $SD_CLI${NC}"; exit 1; fi

for model in "$DIFFUSION_MODEL" "$VAE_MODEL" "$LLM_MODEL"; do
    if [ ! -f "$model" ]; then echo -e "${RED}Error: model not found: $model${NC}"; exit 1; fi
done

echo -e "${GREEN}✓ All checks passed${NC}"

# 验证尺寸参数
if ! [[ "$WIDTH" =~ ^[0-9]+$ ]] || [ "$WIDTH" -le 0 ]; then echo -e "${RED}Error: width must be positive integer${NC}"; exit 1; fi
if ! [[ "$HEIGHT" =~ ^[0-9]+$ ]] || [ "$HEIGHT" -le 0 ]; then echo -e "${RED}Error: height must be positive integer${NC}"; exit 1; fi

# =============================================================================
# 参数配置（支持环境变量覆盖）
# =============================================================================
SAMPLING_METHOD="${SAMPLING_METHOD:-euler}"
SCHEDULER="${SCHEDULER:-discrete}"
CFG_SCALE="${CFG_SCALE:-3.2}"
STEPS="${STEPS:-25}"

echo -e "${BLUE}[INFO] Mode: steps=$STEPS, cfg=$CFG_SCALE, sampler=$SAMPLING_METHOD${NC}"

# 自动添加质量前缀词
QUALITY_PREFIX="masterpiece, best quality, ultra-detailed, sharp focus, 8k uhd, photorealistic, highly detailed, crisp, clear, centered composition, complete face, full head, professional portrait"
if [[ "$PROMPT" != *"masterpiece"* ]]; then
    PROMPT="$QUALITY_PREFIX, $PROMPT"
fi

# 默认负面提示词
NEGATIVE_PROMPT="${NEGATIVE_PROMPT:-blurry, low quality, worst quality, jpeg artifacts, noise, grain, soft focus, out of focus, hazy, unclear, bad anatomy, deformed, border artifacts, edge distortion, tiling artifacts, edge artifacts, frame distortion, warped edges, stretched proportions, asymmetrical face, off-center, cropped, out of frame, partial face, cut off, incomplete head, cropped head, watermark, text, logo, signature, cropped shoulders, embedding:EasyNegative, embedding:bad-hands-5}"

# =============================================================================
# 输出路径处理
# =============================================================================
if [ -n "$OUTPUT_FILE" ]; then
    if [[ "$OUTPUT_FILE" == *"/"* ]]; then
        OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
        OUTPUT="$(basename "$OUTPUT_FILE")"
    else
        OUTPUT_DIR="$HOME"
        OUTPUT="$OUTPUT_FILE"
    fi
else
    OUTPUT_DIR="$HOME"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    MD5=$(echo "$PROMPT" | md5sum | cut -c1-8)
    OUTPUT="${TIMESTAMP}_${MD5}.png"
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT"

# =============================================================================
# 生成信息输出
# =============================================================================
echo ""
echo "========================================"
echo "  Image Generation"
echo "========================================"
echo -e "Size: ${GREEN}${WIDTH}x${HEIGHT}${NC}"
echo -e "Steps: $STEPS"
echo -e "CFG Scale: ${CYAN}$CFG_SCALE${NC}"
echo -e "Sampler: ${CYAN}$SAMPLING_METHOD${NC} + ${CYAN}$SCHEDULER${NC}"
echo "----------------------------------------"
echo -e "Prompt: ${YELLOW}${PROMPT:0:120}${NC}"
if [ ${#PROMPT} -gt 120 ]; then echo -e "        ${YELLOW}...${NC}"; fi
echo -e "Output: ${GREEN}$OUTPUT_PATH${NC}"
echo "========================================"
echo ""

# =============================================================================
# 执行生成
# =============================================================================
SEED="${SEED:-$RANDOM}"
echo "Generating..."

# 显存管理: 高分辨率自动启用 CPU offloading
VRAM_ARGS=()
PIXEL_COUNT=$((WIDTH * HEIGHT))
if [ "$PIXEL_COUNT" -gt $((1024 * 1024)) ]; then
    VRAM_ARGS+=(--vae-on-cpu)
    echo -e "${YELLOW}[VRAM] High resolution ${WIDTH}x${HEIGHT}, VAE -> CPU${NC}"
fi
if [ "$PIXEL_COUNT" -gt $((1280 * 1280)) ]; then
    VRAM_ARGS+=(--clip-on-cpu)
    echo -e "${YELLOW}[VRAM] Very high resolution, CLIP -> CPU${NC}"
fi
if [ "${FORCE_OFFLOAD:-0}" = "1" ]; then
    VRAM_ARGS+=(--offload-to-cpu)
    echo -e "${YELLOW}[VRAM] Force offload to CPU${NC}"
fi

SD_CMD=("$SD_CLI"
  --diffusion-model "$DIFFUSION_MODEL"
  --vae "$VAE_MODEL"
  --llm "$LLM_MODEL"
  -p "$PROMPT"
  -n "$NEGATIVE_PROMPT"
  --cfg-scale "$CFG_SCALE"
  --sampling-method "$SAMPLING_METHOD"
  --scheduler "$SCHEDULER"
  --diffusion-fa
  --vae-tiling
  --vae-tile-size 256x256
  --vae-tile-overlap 0.75
  --embd-dir "$MODEL_DIR/embeddings"
  -W "$WIDTH" -H "$HEIGHT"
  --steps "$STEPS"
  -s "$SEED"
  -o "$OUTPUT_PATH"
  "${VRAM_ARGS[@]}"
)

"${SD_CMD[@]}"

# =============================================================================
# 结果输出
# =============================================================================
if [ -f "$OUTPUT_PATH" ]; then
    FILE_SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)
    echo ""
    echo "========================================"
    echo -e "${GREEN}✓ Generation successful!${NC}"
    echo -e "File: ${GREEN}$OUTPUT_PATH${NC}"
    echo -e "Size: ${BLUE}$FILE_SIZE${NC}"
    echo -e "Seed: ${YELLOW}$SEED${NC}"
    echo -e "CFG: ${CYAN}$CFG_SCALE${NC}"
    echo -e "Resolution: ${GREEN}${WIDTH}x${HEIGHT}${NC}"
    echo "========================================"
else
    echo ""
    echo "========================================"
    echo -e "${RED}✗ Generation failed! Output file not found${NC}"
    echo "========================================"
    exit 1
fi
