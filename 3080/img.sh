#!/bin/bash
# Model: Z-Image Turbo (z_image_turbo-Q8_0.gguf)
# Best for: realistic, photorealistic, portrait, fashion, product, architecture, landscape, general purpose
# NOT good for: anime, cartoon, illustrations
# Steps: 20, CFG: 1.0
# Usage: ./img.sh "prompt" [output] [width] [height]

PROMPT="$1"
OUTPUT_FILE="$2"
WIDTH="${3:-1920}"
HEIGHT="${4:-1080}"

# 默认保存到 home 目录
OUTPUT_DIR="$HOME"

# 如果用户指定的输出路径包含目录，则使用用户指定的目录
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

NEG_PROMPT="[Pastedsource_furry, source_Futanari, censored, worst quality, low quality, ugly, deformed fingers, extra fingers, fused fingers, too many fingers, grainy, Sweat, looking up, monochrome, missing head, bad anatomy, bad hands, extra fingers, missing fingers, blurry"

CMD="$HOME/stable-diffusion.cpp/bin/sd-cli \
  --diffusion-model /opt/image/z_image_turbo-Q8_0.gguf \
  --vae /opt/image/ae.safetensors \
  --llm /opt/image/Qwen3-4B-Instruct-2507-Q4_K_M.gguf \
  -p \"$PROMPT\" \
  -n \"$NEG_PROMPT\" \
  --cfg-scale 1.0 \
  --diffusion-fa \
  --cache-mode easycache \
  --vae-tiling \
  -H $HEIGHT -W $WIDTH \
  --steps 12 \
  -s $RANDOM \
  -o \"$OUTPUT_DIR/$OUTPUT\""

eval $CMD

echo "$OUTPUT_DIR/$OUTPUT"
