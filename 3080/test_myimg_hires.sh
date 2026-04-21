#!/bin/bash

# =============================================================================
# HiRes Fix 测试脚本 - 使用 sd-img2img（my-img 项目）
# =============================================================================

MODEL_DIR="/opt/image/model"
OUTPUT_DIR="$HOME/generated_images"
mkdir -p "$OUTPUT_DIR"

PROMPT="beautiful young lady, baby like skin, realistic photo, professional portrait, studio lighting, detailed skin texture, sharp focus, Canon 85mm f/1.4, high definition, face close-up"
NEGATIVE="blurry, low quality, ugly, deformed, duplicate, multiple faces, extra limbs, bad anatomy"
SEED=42

# 基础尺寸
BASE_W=640
BASE_H=360

# 2K 目标尺寸
TARGET_2K_W=2560
TARGET_2K_H=1440

echo "=========================================="
echo "HiRes Fix 测试（my-img sd-img2img）"
echo "=========================================="
echo "Prompt: $PROMPT"
echo "Seed: $SEED"
echo ""

# 如果没有输入图，先创建
if [ ! -f "$OUTPUT_DIR/portrait_base_${BASE_W}x${BASE_H}.png" ]; then
    echo "[INFO] 创建测试输入图..."
    /opt/stable-diffusion.cpp/build/bin/sd-cli \
      --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
      --vae "$MODEL_DIR/ae.safetensors" \
      --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
      -p "$PROMPT" \
      -W "$BASE_W" -H "$BASE_H" \
      --steps 15 \
      -s "$SEED" \
      -o "$OUTPUT_DIR/portrait_base_${BASE_W}x${BASE_H}.png" 2>&1 | tail -3
fi

echo ""

# 使用 sd-img2img 的 Deep HiRes Fix 生成 2560x1440
echo "[1/1] sd-img2img Deep HiRes Fix ${BASE_W}x${BASE_H} -> ${TARGET_2K_W}x${TARGET_2K_H}..."
/opt/my-img/build/sd-img2img \
  --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  --input "$OUTPUT_DIR/portrait_base_${BASE_W}x${BASE_H}.png" \
  --prompt "$PROMPT" \
  --negative-prompt "$NEGATIVE" \
  --deep-hires \
  --target-width "$TARGET_2K_W" \
  --target-height "$TARGET_2K_H" \
  --strength 0.4 \
  --cfg-scale 1.01 \
  --steps 25 \
  --seed "$SEED" \
  --output "$OUTPUT_DIR/myimg_hires_${TARGET_2K_W}x${TARGET_2K_H}.png" 2>&1 | tee "$OUTPUT_DIR/test_myimg_hires.log"

echo ""
echo "=========================================="
echo "测试完成！输出文件："
echo "=========================================="
ls -lh "$OUTPUT_DIR"/myimg_hires_*.png
