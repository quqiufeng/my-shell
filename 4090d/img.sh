#!/bin/bash

# 用法:
#   ./img_4090d.sh [提示词] [输出文件] [宽度] [高度]
# 
# 参数说明:
#   提示词     - 要生成的图像描述 (默认: "A beautiful landscape")
#   输出文件    - 输出文件路径 (默认: /opt/时间戳_md5.png)
#                如果包含目录路径，则保存到指定目录
#   宽度       - 图像宽度 (默认: 1920)
#   高度       - 图像高度 (默认: 1080)
#
# 示例:
#   ./img_4090d.sh "A cat on the table"
#   ./img_4090d.sh "A sunset" /opt/sunset.png 2560 1440
#   ./img_4090d.sh "Mountain" mountain.png 1920 1080

# 模型文件路径 (位于 /opt/gguf/image/ 目录)
MODEL_DIR="/opt/gguf/image"

PROMPT="${1:-A beautiful landscape}"
OUTPUT_FILE="$2"
WIDTH="${3:-1920}"
HEIGHT="${4:-1080}"

# 默认保存到 /opt 目录
OUTPUT_DIR="/opt"

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

echo "Generating image..."
echo "Prompt: $PROMPT"
echo "Size: ${WIDTH}x${HEIGHT}"
echo "Output: $OUTPUT_DIR/$OUTPUT"

/opt/stable-diffusion.cpp/bin/sd-cli \
  --diffusion-model $MODEL_DIR/z_image_turbo-Q8_0.gguf \
  --vae $MODEL_DIR/ae.safetensors \
  --llm $MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf \
  -p "$PROMPT" \
  --cfg-scale 1.0 \
  --diffusion-fa \
  --cache-mode easycache \
  -H $HEIGHT -W $WIDTH \
  --steps 20 \
  -s $RANDOM \
  -o "$OUTPUT_DIR/$OUTPUT" > /dev/null 2>&1

echo "Image saved to: $OUTPUT_DIR/$OUTPUT"
