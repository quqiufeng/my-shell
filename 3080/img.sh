#!/bin/bash
set -euo pipefail

# =============================================================================
# 图像生成脚本 - 基于 stable-diffusion.cpp (优化版)
# =============================================================================
#
# 【出图原理 / Why HiRes Fix】
# 直接生成高分辨率会导致"多人症"、畸形五官等问题，因为扩散模型训练时
# 未见过高分辨率。HiRes Fix 分两阶段：
#   1. 先生成低分辨率图像（构图、骨架正确）
#   2. 在 latent 空间放大后 refine（保留结构 + 补充细节）
#
# 【3080 10G 显存限制】
# 10G 显存无法直接以高分辨率作为基础（会 OOM 爆显存），因此：
#   - 基础分辨率只能到 1280x720（latent 160x90，刚好在显存极限）
#   - 再通过 HiRes Fix 放大到目标 2560x1440（2x 放大）
#   - 虽然放大倍数较大，但这是 10G 显存下生成 2560x1440 的唯一可行方案
#
# 【模型下载地址】
#   - Z-Image-Turbo GGUF: https://modelscope.cn/models/jayn7/Z-Image-Turbo-GGUF/files
#     推荐: z_image_turbo-Q4_K_M.gguf / z_image_turbo-Q5_K_M.gguf (RTX 3080 10GB 验证可用)
#
# 【用法】
#   ./img.sh [提示词] [输出文件] [宽度] [高度] [--upscale]
#
# 【示例】
#   ./img.sh "A beautiful landscape"
#   ./img.sh "A sunset" /mnt/e/app/sunset.png 1280 720
#   ./img.sh "portrait" ~/portrait.png 2560 1440 --upscale
#
# 【环境变量覆盖】
#   SAMPLING_METHOD=euler CFG_SCALE=3.2 STEPS=25 ./img.sh "..."
#
# =============================================================================
# 参考提示词示例
# =============================================================================
#
# 1. 花卉肖像 (2560x1440)
#    PROMPT="A captivating portrait of a young woman with a powerful gaze..."
#    NEGATIVE="oily skin, acne, blemishes, wrinkles..."
#    ./img.sh "$PROMPT" /mnt/e/app/flower_portrait.png 2560 1440
#
# 2. 油画百合肖像 (2560x1440)
#    PROMPT="A captivating portrait of a young woman with a powerful gaze... Oil painting style..."
#    NEGATIVE="oily skin, acne... digital art, smooth texture..."
#    ./img.sh "$PROMPT" /mnt/e/app/lily_oil_painting.png 2560 1440
#
# =============================================================================
# 全球十大美景壁纸 (2560x1440)
# =============================================================================
#
# 1. 瑞士阿尔卑斯山
#    PROMPT="Swiss Alps, majestic mountain peaks, snow-capped mountains, crystal clear lake..."
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_01_alps.png 2560 1440
#
# 2. 日本樱花
#    PROMPT="Japanese cherry blossoms, sakura trees in full bloom..."
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_02_sakura.png 2560 1440
#
# 3. 冰岛极光
#    PROMPT="Iceland northern lights, aurora borealis dancing across the night sky..."
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_03_aurora.png 2560 1440
#
# 4. 马尔代夫海滩
#    PROMPT="Maldives tropical beach, crystal clear turquoise water..."
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_04_maldives.png 2560 1440
#
# 5. 非洲草原日落
#    PROMPT="African savanna sunset, golden grass plains..."
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_05_savanna.png 2560 1440
#
# 6. 科罗拉多大峡谷
#    PROMPT="Grand Canyon Colorado, majestic red rock formations..."
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_06_canyon.png 2560 1440
#
# 7. 挪威峡湾
#    PROMPT="Norwegian fjord, dramatic steep mountains..."
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_07_fjord.png 2560 1440
#
# 8. 新西兰南岛
#    PROMPT="New Zealand South Island, dramatic mountain peaks..."
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_08_nz.png 2560 1440
#
# 9. 土耳其卡帕多奇亚
#    PROMPT="Cappadocia Turkey, fairy chimneys rock formations..."
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_09_cappadocia.png 2560 1440
#
# 10. 中国黄山
#     PROMPT="Yellow Mountain China, dramatic granite peaks..."
#     ./img.sh "$PROMPT" /mnt/e/app/landscape_10_huangshan.png 2560 1440
#
# =============================================================================

# 设置 ONNX Runtime 库路径
export LD_LIBRARY_PATH=/home/dministrator/onnxruntime-linux-x64-1.20.1/lib:${LD_LIBRARY_PATH:-}

# 颜色定义
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m"

# 模型路径
MODEL_DIR="${MODEL_DIR:-/opt/image/model}"
SD_CLI="${SD_CLI:-/home/dministrator/stable-diffusion.cpp/bin/sd-cli}"
DIFFUSION_MODEL="$MODEL_DIR/z_image_turbo-Q5_K_M.gguf"
VAE_MODEL="$MODEL_DIR/ae.safetensors"
LLM_MODEL="$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
UPSCALE_MODEL="$MODEL_DIR/2x_ESRGAN.gguf"

# 解析参数（支持 --upscale）
UPSCALE_FLAG=0
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--upscale" ]; then
        UPSCALE_FLAG=1
    else
        ARGS+=("$arg")
    fi
done

PROMPT="${ARGS[0]:-A beautiful landscape}"
OUTPUT_FILE="${ARGS[1]:-}"
WIDTH="${ARGS[2]:-1280}"
HEIGHT="${ARGS[3]:-720}"

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

if [ "$UPSCALE_FLAG" -eq 1 ]; then
    if [ ! -f "$UPSCALE_MODEL" ]; then echo -e "${RED}Error: upscale model not found: $UPSCALE_MODEL${NC}"; exit 1; fi
    echo -e "${CYAN}✓ Upscale mode enabled (2x ESRGAN)${NC}"
fi

echo -e "${GREEN}✓ All checks passed${NC}"

# 验证尺寸参数
if ! [[ "$WIDTH" =~ ^[0-9]+$ ]] || [ "$WIDTH" -le 0 ]; then echo -e "${RED}Error: width must be positive integer${NC}"; exit 1; fi
if ! [[ "$HEIGHT" =~ ^[0-9]+$ ]] || [ "$HEIGHT" -le 0 ]; then echo -e "${RED}Error: height must be positive integer${NC}"; exit 1; fi

# =============================================================================
# 参数配置（支持环境变量覆盖）
# =============================================================================
# HD optimized parameters (实测调优)
# 人像推荐: euler + discrete + cfg 3.2 + strength 0.30 + 1280x720低分辨率 (边缘最稳定)
# 风景推荐: dpm++2m + karras + cfg 1.5 + strength 0.35
SAMPLING_METHOD="${SAMPLING_METHOD:-euler}"
SCHEDULER="${SCHEDULER:-discrete}"
CFG_SCALE="${CFG_SCALE:-3.2}"
STEPS="${STEPS:-25}"
HIRES_STEPS="${HIRES_STEPS:-60}"
HIRES_STRENGTH="${HIRES_STRENGTH:-0.25}"

if [ "$WIDTH" -ge 1920 ] && [ "$HEIGHT" -ge 1080 ]; then
    echo -e "${BLUE}[INFO] Ultra HD Mode: steps=$STEPS, cfg=$CFG_SCALE, sampler=$SAMPLING_METHOD${NC}"
else
    echo -e "${BLUE}[INFO] HD Mode: steps=$STEPS, cfg=$CFG_SCALE, sampler=$SAMPLING_METHOD${NC}"
fi

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
# HiRes Fix 低分辨率计算
# =============================================================================
TARGET_LATENT_W=$((WIDTH / 8))
TARGET_LATENT_H=$((HEIGHT / 8))

# 关键修复：确保低分辨率 latent 宽高比与目标严格匹配
# Z-Image 模型 latent 对齐到 8 的倍数后，比例必须保持一致
#
# 对于 16:9 比例，使用已知正确的低分辨率对
# 2560x1440 (latent 320x180, ratio=1.778):
#   1280x720 -> latent 160x90 (ratio=1.778) 推荐，放大倍数最小，边缘最稳定
#   1024x576 -> latent 128x72 (ratio=1.778) 备选，放大倍数适中
# 1280x720 (latent 160x90, ratio=1.778):
#   1024x576 -> latent 128x72 (ratio=1.778) 修复版，避免 640x360 模糊
if [ "$WIDTH" -eq 2560 ] && [ "$HEIGHT" -eq 1440 ]; then
    LOW_W=1280
    LOW_H=720
elif [ "$WIDTH" -eq 1920 ] && [ "$HEIGHT" -eq 1080 ]; then
    LOW_W=1024
    LOW_H=576
elif [ "$WIDTH" -eq 1280 ] && [ "$HEIGHT" -eq 720 ]; then
    LOW_W=1024
    LOW_H=576
else
    # 通用计算：确保 latent 能被 8 整除且比例匹配
    LOW_LATENT_W=$((TARGET_LATENT_W / 2))
    LOW_LATENT_H=$((TARGET_LATENT_H / 2))
    
    # 对齐到 8 的倍数
    LOW_LATENT_W=$(((LOW_LATENT_W + 7) / 8 * 8))
    LOW_LATENT_H=$(((LOW_LATENT_H + 7) / 8 * 8))
    
    LOW_W=$((LOW_LATENT_W * 8))
    LOW_H=$((LOW_LATENT_H * 8))
fi

# 保持比例的最小限制：只在单边小于512时按比例放大
if [ "$LOW_W" -lt 512 ] || [ "$LOW_H" -lt 512 ]; then
    TARGET_RATIO=$(echo "scale=6; $WIDTH / $HEIGHT" | bc)
    if [ "$LOW_W" -lt "$LOW_H" ]; then
        LOW_W=512
        LOW_H=$(echo "scale=0; $LOW_W / $TARGET_RATIO / 8 * 8" | bc)
        if [ "$LOW_H" -lt 512 ]; then LOW_H=512; fi
    else
        LOW_H=512
        LOW_W=$(echo "scale=0; $LOW_H * $TARGET_RATIO / 8 * 8" | bc)
        if [ "$LOW_W" -lt 512 ]; then LOW_W=512; fi
    fi
fi

# =============================================================================
# 生成信息输出
# =============================================================================
echo ""
echo "========================================"
echo "  HD Image Generation"
echo "========================================"
echo -e "Target Size: ${GREEN}${WIDTH}x${HEIGHT}${NC}"
echo -e "Low-res Pass: ${GREEN}${LOW_W}x${LOW_H} -> ${WIDTH}x${HEIGHT}${NC}"
echo -e "Steps: $STEPS -> $HIRES_STEPS (HiRes)"
echo -e "CFG Scale: ${CYAN}$CFG_SCALE${NC}"
echo -e "HiRes Strength: $HIRES_STRENGTH"
echo -e "Sampler: ${CYAN}$SAMPLING_METHOD${NC} + ${CYAN}$SCHEDULER${NC}"
if [ "$UPSCALE_FLAG" -eq 1 ]; then
    UPSCALED_W=$((WIDTH * 2))
    UPSCALED_H=$((HEIGHT * 2))
    echo -e "Upscale: ${CYAN}2x ESRGAN -> ${UPSCALED_W}x${UPSCALED_H}${NC}"
fi
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
  --vae-tiling
  --vae-tile-size 256x256
  --vae-tile-overlap 0.75
  --freeu
  --freeu-b1 1.4
  --freeu-b2 1.5
  --sag
  --sag-scale 0.5
  --auto-enhance
  --clarity 0.4
  --sharpen 1.2
  --sharpen-radius 2
  --embd-dir "$MODEL_DIR/embeddings"
  -W "$LOW_W" -H "$LOW_H"
  --steps "$STEPS"
  --hires
  --hires-width "$WIDTH"
  --hires-height "$HEIGHT"
  --hires-strength "$HIRES_STRENGTH"
  --hires-steps "$HIRES_STEPS"
  -s "$SEED"
  -o "$OUTPUT_PATH"
)

if [ "$UPSCALE_FLAG" -eq 1 ]; then
    SD_CMD+=(--upscale-model "$UPSCALE_MODEL")
    SD_CMD+=(--upscale-repeats 1)
    SD_CMD+=(--upscale-tile-size 1440)
fi

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
    if [ "$UPSCALE_FLAG" -eq 1 ]; then
        echo -e "Upscaled: ${CYAN}${UPSCALED_W}x${UPSCALED_H}${NC}"
    fi
    echo "========================================"
else
    echo ""
    echo "========================================"
    echo -e "${RED}✗ Generation failed! Output file not found${NC}"
    echo "========================================"
    exit 1
fi
