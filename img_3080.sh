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

OUTPUT_DIR="$HOME"
OUTPUT_DIR_MNT="/mnt/e/app/img"

if [ -z "$OUTPUT_FILE" ]; then
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  MD5=$(echo "$PROMPT" | md5sum | cut -c1-8)
  OUTPUT="${TIMESTAMP}_${MD5}.png"
else
  OUTPUT="$OUTPUT_FILE"
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

if [ -f "$OUTPUT_DIR/$OUTPUT" ]; then
  mv "$OUTPUT_DIR/$OUTPUT" "$OUTPUT_DIR_MNT/"
fi

echo "$OUTPUT_DIR_MNT/$OUTPUT"
