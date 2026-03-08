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
  --scheduler karras \
  --vae-tiling \
  -H $HEIGHT -W $WIDTH \
  --steps 25 \
  -s $RANDOM \
  -o \"$OUTPUT_DIR/$OUTPUT\" > /dev/null 2>&1"

eval $CMD

echo "$OUTPUT_DIR/$OUTPUT"

# 参数说明:
# --scheduler karras: 使用 Karras 调度器，图像更清晰
# --steps 25: 步数越多，细节越好（默认20，推荐25）
# --diffusion-fa: Flash Attention 加速
# --cache-mode easycache: 缓存加速，跳过部分步骤

# =============================================================================
# 风景壁纸生成参考命令 (1280x720 小图)
# =============================================================================
# 配合 upscale_hires.sh 放大到 2560x1440
#
# # 1. 马丘比丘
# ./img.sh "Machu Picchu, ancient Incan citadel perched on mountain ridge, misty clouds, lush green mountains, stone ruins, dramatic landscape, golden hour lighting, breathtaking view, travel destination, photorealistic, high detail, 8K quality" /opt/wallpaper_01.png 1280 720
# ./upscale_hires.sh /opt/wallpaper_01.png /opt/wallpaper_01_hires.png
#
# # 2. 瑞士阿尔卑斯山
# ./img.sh "Swiss Alps, majestic mountain peaks, snow-capped mountains, crystal clear lake, green valleys, scenic landscape, dramatic clouds, golden sunlight, travel destination, photorealistic, high detail, 8K quality" /opt/wallpaper_02.png 1280 720
# ./upscale_hires.sh /opt/wallpaper_02.png /opt/wallpaper_02_hires.png
#
# # 3. 美国大峡谷
# ./img.sh "Grand Canyon USA, massive red rock canyon, layered rock formations, Colorado River winding through, dramatic desert landscape, golden hour, breathtaking vista, travel destination, photorealistic, high detail, 8K quality" /opt/wallpaper_03.png 1280 720
# ./upscale_hires.sh /opt/wallpaper_03.png /opt/wallpaper_03_hires.png
#
# # 4. 圣托里尼岛
# ./img.sh "Santorini Greece, iconic blue-domed churches, white-washed buildings, cliffside village, Aegean Sea, sunset sky, romantic atmosphere, travel destination, photorealistic, high detail, 8K quality" /opt/wallpaper_04.png 1280 720
# ./upscale_hires.sh /opt/wallpaper_04.png /opt/wallpaper_04_hires.png
#
# # 5. 挪威峡湾
# ./img.sh "Norway Fjords, majestic steep cliffs, crystal clear water, mountains reflected in fjord, green vegetation, dramatic landscape, misty atmosphere, travel destination, photorealistic, high detail, 8K quality" /opt/wallpaper_05.png 1280 720
# ./upscale_hires.sh /opt/wallpaper_05.png /opt/wallpaper_05_hires.png
#
# # 6. 日本富士山
# ./img.sh "Mount Fuji Japan, iconic snow-capped mountain, cherry blossoms in foreground, peaceful lake reflection, traditional Japanese temple, dramatic landscape, serene atmosphere, travel destination, photorealistic, high detail, 8K quality" /opt/wallpaper_06.png 1280 720
# ./upscale_hires.sh /opt/wallpaper_06.png /opt/wallpaper_06_hires.png
#
# # 7. 布拉格老城广场
# ./img.sh "Prague Old Town Square, historic Gothic architecture, Astronomical Clock, colorful baroque buildings, cobblestone streets, Charles Bridge in distance, golden hour lighting, European charm, travel destination, photorealistic, high detail, 8K quality" /opt/wallpaper_07.png 1280 720
# ./upscale_hires.sh /opt/wallpaper_07.png /opt/wallpaper_07_hires.png
#
# # 8. 纳米比亚索苏斯盐沼
# ./img.sh "Namibia Sossusvlei, iconic red sand dunes, dead tree silhouettes, Deadvlei pan, dramatic desert landscape, golden hour, clear blue sky, surreal atmosphere, travel destination, photorealistic, high detail, 8K quality" /opt/wallpaper_08.png 1280 720
# ./upscale_hires.sh /opt/wallpaper_08.png /opt/wallpaper_08_hires.png
#
# # 9. 威尼斯
# ./img.sh "Venice Italy, iconic Grand Canal, historic palazzos, gondola on water, Rialto Bridge, golden sunset, romantic atmosphere, travel destination, photorealistic, high detail, 8K quality" /opt/wallpaper_09.png 1280 720
# ./upscale_hires.sh /opt/wallpaper_09.png /opt/wallpaper_09_hires.png
#
# # 10. 巴厘岛梯田
# ./img.sh "Bali Rice Terraces, Tegallalang terraced rice fields, lush green tropical landscape, palm trees, traditional Balinese temple, misty mountains in background, scenic beauty, travel destination, photorealistic, high detail, 8K quality" /opt/wallpaper_10.png 1280 720
# ./upscale_hires.sh /opt/wallpaper_10.png /opt/wallpaper_10_hires.png
