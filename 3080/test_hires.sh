#!/bin/bash

# =============================================================================
# HiRes Fix 测试脚本
# =============================================================================
# 对比测试：直接生成 vs HiRes Fix

MODEL_DIR="/opt/image/model"
OUTPUT_DIR="$HOME/generated_images"
mkdir -p "$OUTPUT_DIR"

PROMPT="A beautiful mountain landscape with a crystal clear lake, sunset lighting, photorealistic, high detail"
NEGATIVE="blurry, low quality, ugly, deformed"
SEED=42

# 基础尺寸
BASE_W=640
BASE_H=360

# HiRes 目标尺寸
HIRES_W=1280
HIRES_H=720

echo "=========================================="
echo "HiRes Fix 对比测试"
echo "=========================================="
echo "Prompt: $PROMPT"
echo "Seed: $SEED"
echo ""

# 1. 直接生成小图
echo "[1/4] 生成基础小图 ${BASE_W}x${BASE_H}..."
/home/dministrator/stable-diffusion.cpp/build/bin/sd-cli \
  --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  -p "$PROMPT" \
  -n "$NEGATIVE" \
  --cfg-scale 1.01 \
  --sampling-method euler \
  --diffusion-fa \
  --vae-tiling \
  --vae-tile-size 64x64 \
  -W "$BASE_W" -H "$BASE_H" \
  --steps 15 \
  -s "$SEED" \
  -o "$OUTPUT_DIR/base_${BASE_W}x${BASE_H}.png" 2>&1 | grep -E "(sampling|generating|Error|INFO)"

echo ""

# 2. 直接生成大图（对比用）
echo "[2/4] 直接生成大图 ${HIRES_W}x${HIRES_H}..."
/home/dministrator/stable-diffusion.cpp/build/bin/sd-cli \
  --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  -p "$PROMPT" \
  -n "$NEGATIVE" \
  --cfg-scale 1.01 \
  --sampling-method euler \
  --diffusion-fa \
  --vae-tiling \
  --vae-tile-size 64x64 \
  -W "$HIRES_W" -H "$HIRES_H" \
  --steps 15 \
  -s "$SEED" \
  -o "$OUTPUT_DIR/direct_${HIRES_W}x${HIRES_H}.png" 2>&1 | grep -E "(sampling|generating|Error|INFO)"

echo ""

# 3. HiRes Fix strength=0.3
echo "[3/4] HiRes Fix (strength=0.3) ${BASE_W}x${BASE_H} -> ${HIRES_W}x${HIRES_H}..."
/home/dministrator/stable-diffusion.cpp/build/bin/sd-cli \
  --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  -p "$PROMPT" \
  -n "$NEGATIVE" \
  --cfg-scale 1.01 \
  --sampling-method euler \
  --diffusion-fa \
  --vae-tiling \
  --vae-tile-size 64x64 \
  -W "$BASE_W" -H "$BASE_H" \
  --hires-fix \
  --hires-width "$HIRES_W" \
  --hires-height "$HIRES_H" \
  --hires-strength 0.3 \
  --steps 15 \
  -s "$SEED" \
  -o "$OUTPUT_DIR/hires_03_${HIRES_W}x${HIRES_H}.png" 2>&1 | grep -E "(sampling|generating|Error|INFO|HiRes)"

echo ""

# 4. HiRes Fix strength=0.5
echo "[4/4] HiRes Fix (strength=0.5) ${BASE_W}x${BASE_H} -> ${HIRES_W}x${HIRES_H}..."
/home/dministrator/stable-diffusion.cpp/build/bin/sd-cli \
  --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  -p "$PROMPT" \
  -n "$NEGATIVE" \
  --cfg-scale 1.01 \
  --sampling-method euler \
  --diffusion-fa \
  --vae-tiling \
  --vae-tile-size 64x64 \
  -W "$BASE_W" -H "$BASE_H" \
  --hires-fix \
  --hires-width "$HIRES_W" \
  --hires-height "$HIRES_H" \
  --hires-strength 0.5 \
  --steps 15 \
  -s "$SEED" \
  -o "$OUTPUT_DIR/hires_05_${HIRES_W}x${HIRES_H}.png" 2>&1 | grep -E "(sampling|generating|Error|INFO|HiRes)"

echo ""
echo "=========================================="
echo "测试完成！输出文件："
echo "=========================================="
ls -lh "$OUTPUT_DIR"/*.png | grep -E "(base|direct|hires)"
