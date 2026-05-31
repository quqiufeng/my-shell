#!/bin/bash

# =============================================================================
# HiRes Fix 测试脚本 - 2560x1440 高质量人像
# =============================================================================
# 测试正确的 HiRes Fix 实现，确保无幻影重合

MODEL_DIR="/opt/image/model"
OUTPUT_DIR="$HOME/generated_images"
mkdir -p "$OUTPUT_DIR"

# 高质量人像提示词
PROMPT="beautiful young lady, baby like skin, realistic photo, professional portrait, studio lighting, detailed skin texture, sharp focus, Canon 85mm f/1.4, high definition, face close-up"
NEGATIVE="blurry, low quality, ugly, deformed, duplicate, multiple faces, extra limbs, bad anatomy"
SEED=42

# 基础尺寸
BASE_W=640
BASE_H=360

# HiRes 目标尺寸 - 2K
HIRES_W=2560
HIRES_H=1440

echo "=========================================="
echo "HiRes Fix 高质量人像测试"
echo "=========================================="
echo "Prompt: $PROMPT"
echo "Seed: $SEED"
echo ""

# 1. 直接生成小图（基线）
echo "[1/3] 生成基础小图 ${BASE_W}x${BASE_H}..."
/opt/stable-diffusion.cpp/build/bin/sd-cli \
  --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  -p "$PROMPT" \
  -n "$NEGATIVE" \
  --cfg-scale 1.01 \
  --sampling-method euler \
  --diffusion-fa \
  --vae-tiling \
  --vae-tile-size 256x256 \
  -W "$BASE_W" -H "$BASE_H" \
  --steps 20 \
  -s "$SEED" \
  -o "$OUTPUT_DIR/portrait_base_${BASE_W}x${BASE_H}.png" 2>&1 | grep -E "(sampling|generating|Error|INFO|completed)"

echo ""

# 2. HiRes Fix strength=0.4（推荐值，平衡细节和结构）
echo "[2/3] HiRes Fix (strength=0.4) ${BASE_W}x${BASE_H} -> ${HIRES_W}x${HIRES_H}..."
/opt/stable-diffusion.cpp/build/bin/sd-cli \
  --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  -p "$PROMPT" \
  -n "$NEGATIVE" \
  --cfg-scale 1.01 \
  --sampling-method euler \
  --diffusion-fa \
  --vae-tiling \
  --vae-tile-size 256x256 \
  -W "$BASE_W" -H "$BASE_H" \
  --hires-fix \
  --hires-width "$HIRES_W" \
  --hires-height "$HIRES_H" \
  --hires-strength 0.4 \
  --steps 25 \
  -s "$SEED" \
  -o "$OUTPUT_DIR/portrait_hires_04_${HIRES_W}x${HIRES_H}.png" 2>&1 | grep -E "(sampling|generating|Error|INFO|HiRes|completed)"

echo ""

# 3. HiRes Fix strength=0.5（更多细节变化）
echo "[3/3] HiRes Fix (strength=0.5) ${BASE_W}x${BASE_H} -> ${HIRES_W}x${HIRES_H}..."
/opt/stable-diffusion.cpp/build/bin/sd-cli \
  --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  -p "$PROMPT" \
  -n "$NEGATIVE" \
  --cfg-scale 1.01 \
  --sampling-method euler \
  --diffusion-fa \
  --vae-tiling \
  --vae-tile-size 256x256 \
  -W "$BASE_W" -H "$BASE_H" \
  --hires-fix \
  --hires-width "$HIRES_W" \
  --hires-height "$HIRES_H" \
  --hires-strength 0.5 \
  --steps 25 \
  -s "$SEED" \
  -o "$OUTPUT_DIR/portrait_hires_05_${HIRES_W}x${HIRES_H}.png" 2>&1 | grep -E "(sampling|generating|Error|INFO|HiRes|completed)"

echo ""
echo "=========================================="
echo "测试完成！输出文件："
echo "=========================================="
ls -lh "$OUTPUT_DIR"/portrait_*.png

echo ""
echo "检查要点："
echo "1. 图片应清晰，无幻影/重影"
echo "2. 人脸细节应自然，无重复特征"
echo "3. 2560x1440 大图应无 tile 接缝"
