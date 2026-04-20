#!/bin/bash

# =============================================================================
# HiRes Fix 测试脚本 - 使用 sd-img2img（my-img 项目）
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

# 2K 目标尺寸
TARGET_2K_W=2560
TARGET_2K_H=1440

echo "=========================================="
echo "HiRes Fix 对比测试（my-img 版本）"
echo "=========================================="
echo "Prompt: $PROMPT"
echo "Seed: $SEED"
echo ""

# 1. 直接生成小图（基线）
echo "[1/5] 生成基础小图 ${BASE_W}x${BASE_H}..."
/home/dministrator/my-img/build/sd-img2img \
  --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  --input "$OUTPUT_DIR/portrait_base_${BASE_W}x${BASE_H}.png" \
  --prompt "$PROMPT" \
  --negative-prompt "$NEGATIVE" \
  --strength 0.75 \
  --cfg-scale 1.01 \
  --steps 15 \
  --seed "$SEED" \
  --output "$OUTPUT_DIR/myimg_base_${BASE_W}x${BASE_H}.png" 2>&1 | grep -E "(Progress|Error|ERROR|SUCCESS|Hires)"

# 如果没有输入图，先创建一个
if [ ! -f "$OUTPUT_DIR/portrait_base_${BASE_W}x${BASE_H}.png" ]; then
    echo "[INFO] 创建测试输入图..."
    # 使用 sd-cli 创建基线图
    /home/dministrator/stable-diffusion.cpp/build/bin/sd-cli \
      --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
      --vae "$MODEL_DIR/ae.safetensors" \
      --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
      -p "$PROMPT" \
      -W "$BASE_W" -H "$BASE_H" \
      --steps 15 \
      -s "$SEED" \
      -o "$OUTPUT_DIR/portrait_base_${BASE_W}x${BASE_H}.png" 2>&1 | tail -5
fi

echo ""

# 2. 使用 sd-img2img 的 Deep HiRes Fix 生成 1280x720
echo "[2/5] sd-img2img Deep HiRes Fix ${BASE_W}x${BASE_H} -> ${HIRES_W}x${HIRES_H}..."
/home/dministrator/my-img/build/sd-img2img \
  --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  --input "$OUTPUT_DIR/portrait_base_${BASE_W}x${BASE_H}.png" \
  --prompt "$PROMPT" \
  --negative-prompt "$NEGATIVE" \
  --deep-hires \
  --target-width "$HIRES_W" \
  --target-height "$HIRES_H" \
  --strength 0.5 \
  --cfg-scale 1.01 \
  --steps 20 \
  --seed "$SEED" \
  --output "$OUTPUT_DIR/myimg_hires_${HIRES_W}x${HIRES_H}.png" 2>&1 | grep -E "(Progress|Error|ERROR|SUCCESS|Hires|Base|Target|Phase)"

echo ""

# 3. 使用 sd-img2img 的 Deep HiRes Fix 生成 2560x1440
echo "[3/5] sd-img2img Deep HiRes Fix ${BASE_W}x${BASE_H} -> ${TARGET_2K_W}x${TARGET_2K_H}..."
/home/dministrator/my-img/build/sd-img2img \
  --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  --input "$OUTPUT_DIR/portrait_base_${BASE_W}x${BASE_H}.png" \
  --prompt "$PROMPT" \
  --negative-prompt "$NEGATIVE" \
  --deep-hires \
  --target-width "$TARGET_2K_W" \
  --target-height "$TARGET_2K_H" \
  --strength 0.5 \
  --cfg-scale 1.01 \
  --steps 25 \
  --seed "$SEED" \
  --output "$OUTPUT_DIR/myimg_hires_${TARGET_2K_W}x${TARGET_2K_H}.png" 2>&1 | grep -E "(Progress|Error|ERROR|SUCCESS|Hires|Base|Target|Phase)"

echo ""

# 4. 对比：使用 sd-cli 的原生 hires_fix 生成 1280x720
echo "[4/5] sd-cli 原生 HiRes Fix ${BASE_W}x${BASE_H} -> ${HIRES_W}x${HIRES_H}（对比）..."
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
  --steps 20 \
  -s "$SEED" \
  -o "$OUTPUT_DIR/sdcli_hires_${HIRES_W}x${HIRES_H}.png" 2>&1 | grep -E "(sampling|generating|Error|INFO|HiRes)"

echo ""

# 5. 对比：使用 sd-cli 的原生 hires_fix 生成 2560x1440
echo "[5/5] sd-cli 原生 HiRes Fix ${BASE_W}x${BASE_H} -> ${TARGET_2K_W}x${TARGET_2K_H}（对比）..."
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
  --hires-width "$TARGET_2K_W" \
  --hires-height "$TARGET_2K_H" \
  --hires-strength 0.5 \
  --steps 25 \
  -s "$SEED" \
  -o "$OUTPUT_DIR/sdcli_hires_${TARGET_2K_W}x${TARGET_2K_H}.png" 2>&1 | grep -E "(sampling|generating|Error|INFO|HiRes)"

echo ""
echo "=========================================="
echo "测试完成！输出文件："
echo "=========================================="
ls -lh "$OUTPUT_DIR"/myimg_*.png "$OUTPUT_DIR"/sdcli_*.png 2>/dev/null || ls -lh "$OUTPUT_DIR"/*.png
