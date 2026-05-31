#!/bin/bash
set -euo pipefail

# =============================================================================
# 图像生成脚本 - RTX 3080 20GB 优化版 (ESRGAN 放大方案)
# =============================================================================
#
# 【用法】
#   ./img.sh [提示词] [输出文件] [宽度] [高度]
#
# 【示例】
#   ./img.sh "A beautiful landscape"
#   ./img.sh "portrait" ~/portrait.png 2560 1440
#
# 【环境变量覆盖】
#   STEPS=30 ./img.sh "..."
#
# =============================================================================

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m"

# 模型路径
MODEL_DIR="${MODEL_DIR:-/data/models/image}"
SD_CLI="${SD_CLI:-/opt/my-img/build/myimg-cli}"

# 自动选择模型：优先使用 Q4_K_M（显存更小）
if [ -f "$MODEL_DIR/z-image-turbo-Q4_K_M.gguf" ]; then
    DIFFUSION_MODEL="${DIFFUSION_MODEL:-$MODEL_DIR/z-image-turbo-Q4_K_M.gguf}"
else
    DIFFUSION_MODEL="${DIFFUSION_MODEL:-$MODEL_DIR/z-image-turbo-Q6_K.gguf}"
fi

VAE_MODEL="${VAE_MODEL:-$MODEL_DIR/ae.safetensors}"
LLM_MODEL="${LLM_MODEL:-$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf}"
UPSCALE_MODEL="${UPSCALE_MODEL:-$MODEL_DIR/2x_ESRGAN.gguf}"

PROMPT="${1:-A beautiful landscape}"
OUTPUT_FILE="${2:-}"
WIDTH="${3:-1280}"
HEIGHT="${4:-720}"

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

# =============================================================================
# 高分辨率策略：RTX 3080 20GB 安全方案
# =============================================================================
# 问题：直接生成 1920x1080+ 时 VAE decode 需要 13GB+，会 OOM
# 方案：生成安全分辨率 + 2x ESRGAN 放大
# =============================================================================

PIXEL_COUNT=$((WIDTH * HEIGHT))
USE_UPSCALE=0
BASE_W=$WIDTH
BASE_H=$HEIGHT

# 超过 1280x720 时，使用 ESRGAN 放大
if [ "$PIXEL_COUNT" -gt $((1280 * 720)) ]; then
    USE_UPSCALE=1
    # 计算基础分辨率（目标的一半，对齐到 64）
    BASE_W=$(((WIDTH / 2 + 63) / 64 * 64))
    BASE_H=$(((HEIGHT / 2 + 63) / 64 * 64))
    
    # 最小 512
    if [ "$BASE_W" -lt 512 ]; then BASE_W=512; fi
    if [ "$BASE_H" -lt 512 ]; then BASE_H=512; fi
    
    echo -e "${YELLOW}[ESRGAN] ${WIDTH}x${HEIGHT} 超出直接生成范围${NC}"
    echo -e "${YELLOW}[ESRGAN] 先生成 ${BASE_W}x${BASE_H}，再 2x 放大${NC}"
fi

# =============================================================================
# 参数配置
# =============================================================================
SAMPLING_METHOD="${SAMPLING_METHOD:-euler}"
SCHEDULER="${SCHEDULER:-discrete}"
CFG_SCALE="${CFG_SCALE:-3.2}"
STEPS="${STEPS:-25}"

# 自动添加质量前缀词
QUALITY_PREFIX="masterpiece, best quality, ultra-detailed, sharp focus, 8k uhd, photorealistic, highly detailed, crisp, clear, centered composition, complete face, full head, professional portrait"
if [[ "$PROMPT" != *"masterpiece"* ]]; then
    PROMPT="$QUALITY_PREFIX, $PROMPT"
fi

NEGATIVE_PROMPT="${NEGATIVE_PROMPT:-blurry, low quality, worst quality, jpeg artifacts, noise, grain, soft focus, out of focus, hazy, unclear, bad anatomy, deformed, border artifacts, edge distortion, tiling artifacts, edge artifacts, frame distortion, warped edges, stretched proportions, asymmetrical face, off-center, cropped, out of frame, partial face, cut off, incomplete head, cropped head, watermark, text, logo, signature, cropped shoulders, embedding:EasyNegative, embedding:bad-hands-5}"

# =============================================================================
# 输出路径
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
# 生成信息
# =============================================================================
echo ""
echo "========================================"
echo "  Image Generation"
echo "========================================"
echo -e "Target: ${GREEN}${WIDTH}x${HEIGHT}${NC}"
if [ "$USE_UPSCALE" -eq 1 ]; then
    echo -e "Base:   ${GREEN}${BASE_W}x${BASE_H}${NC}"
    echo -e "Mode:   ${CYAN}ESRGAN 2x Upscale${NC}"
fi
echo -e "Steps:  $STEPS"
echo -e "CFG:    ${CYAN}$CFG_SCALE${NC}"
echo -e "Sampler: ${CYAN}$SAMPLING_METHOD${NC}"
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
  -W "$BASE_W" -H "$BASE_H"
  --steps "$STEPS"
  -s "$SEED"
  -o "$OUTPUT_PATH"
)

# ESRGAN 放大
if [ "$USE_UPSCALE" -eq 1 ]; then
    if [ ! -f "$UPSCALE_MODEL" ]; then
        echo -e "${RED}Error: Upscale model not found: $UPSCALE_MODEL${NC}"
        echo -e "${YELLOW}Falling back to base resolution ${BASE_W}x${BASE_H}${NC}"
    else
        SD_CMD+=(
            --upscale-model "$UPSCALE_MODEL"
            --upscale-repeats 1
        )
        echo -e "${CYAN}Using ESRGAN: $UPSCALE_MODEL${NC}"
    fi
fi

"${SD_CMD[@]}"

# =============================================================================
# 结果
# =============================================================================
if [ -f "$OUTPUT_PATH" ]; then
    FILE_SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)
    echo ""
    echo "========================================"
    echo -e "${GREEN}✓ Generation successful!${NC}"
    echo -e "File: ${GREEN}$OUTPUT_PATH${NC}"
    echo -e "Size: ${BLUE}$FILE_SIZE${NC}"
    echo -e "Seed: ${YELLOW}$SEED${NC}"
    echo -e "Resolution: ${GREEN}${WIDTH}x${HEIGHT}${NC}"
    echo "========================================"
else
    echo ""
    echo "========================================"
    echo -e "${RED}✗ Generation failed!${NC}"
    echo "========================================"
    exit 1
fi
