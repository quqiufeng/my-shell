#!/bin/bash

# =============================================================================
# 图像生成脚本 - 基于 stable-diffusion.cpp
# =============================================================================
#
# 模型下载地址:
#   - Z-Image-Turbo GGUF: https://modelscope.cn/models/jayn7/Z-Image-Turbo-GGUF/files
#     推荐: z_image_turbo-Q4_K_M.gguf / z_image_turbo-Q5_K_M.gguf (RTX 3080 10GB 验证可用)
#
# 用法:
#   ./img.sh [提示词] [输出文件] [宽度] [高度]
#
# 示例:
#   ./img.sh "A beautiful landscape"
#   ./img.sh "A sunset" /mnt/e/app/sunset.png 1280 720
#
# 3. 花卉肖像 (2560x1440)
#    PROMPT="A captivating portrait of a young woman with a powerful gaze, her dark hair styled in an elegant updo. She is flanked by large white flowers in full bloom on either side, their presence simple yet grand, adding a touch of purity and grace to the composition. The flowers are depicted with rich detail, their stamens plump and petals layered in multiple, intricate arrays. The foreground highlights these blossoms, allowing the viewer to appreciate their full beauty and the artist's skill in rendering them. Her makeup is striking, and her mysterious aura draws the viewer in. The background features a deep green wall that conveys a sense of depth and richness. The color, reminiscent of a lush forest or a verdant meadow, adds a layer of sophistication and historical resonance to the piece. The traces of years are still evident, showcasing a classical and atmospheric elegance. This extraordinary masterpiece perfectly captures the essence of both tradition and modernity, leaving a lasting impression on all who behold it."
#    NEGATIVE="oily skin, acne, blemishes, wrinkles, dark circles, redness, rosacea, sunburn, uneven skin tone, excessive pores, dry flaky skin, scars, freckles, moles, skin disease, artificial smooth skin, plastic skin, doll-like skin, overexposed, oversaturated, pale skin, gray skin, yellow skin, ashy skin, dull skin, lifeless skin, flat lighting, harsh shadows, window shadow pattern, striped shadows, patchy lighting, uneven illumination"
#    ./img.sh "$PROMPT" /mnt/e/app/flower_portrait.png 2560 1440
#
# 4. 油画百合肖像 (2560x1440)
#    PROMPT="A captivating portrait of a young woman with a powerful gaze, her dark hair styled in an elegant updo. She is flanked by large white lilies of the valley in full bloom on either side, their presence simple yet grand, adding a touch of purity and grace to the composition. The flowers are depicted with rich detail, their stamens plump and petals layered in multiple, intricate arrays. The foreground highlights these blossoms, allowing the viewer to appreciate their full beauty and the artist's skill in rendering them. Her makeup is striking, and her mysterious aura draws the viewer in. The background features a soft pastel gradient that conveys a sense of depth and richness. The color, reminiscent of a gentle spring morning, adds a layer of sophistication and historical resonance to the piece. The traces of years are still evident, showcasing a classical and atmospheric elegance. Oil painting style with rough brushstrokes, thick impasto texture covering the entire canvas, visible paint strokes, bold blending of colors, expressive line graphics, geometric abstraction elements, dramatic play of shadows and light across the surface, traditional fine art masterpiece."
#    NEGATIVE="oily skin, acne, blemishes, wrinkles, dark circles, redness, rosacea, sunburn, uneven skin tone, excessive pores, dry flaky skin, scars, freckles, moles, skin disease, artificial smooth skin, plastic skin, doll-like skin, overexposed, oversaturated, pale skin, gray skin, yellow skin, ashy skin, dull skin, lifeless skin, flat lighting, harsh shadows, window shadow pattern, striped shadows, patchy lighting, uneven illumination, digital art, smooth texture, photographic, hyperrealistic, 3d render"
#    ./img.sh "$PROMPT" /mnt/e/app/lily_oil_painting.png 2560 1440
#
# =============================================================================
# 全球十大美景壁纸 (2560x1440)
# =============================================================================
#
# 1. 瑞士阿尔卑斯山
#    PROMPT="Swiss Alps, majestic mountain peaks, snow-capped mountains, crystal clear lake, green valleys, scenic landscape, dramatic clouds, golden sunlight at sunrise, photorealistic, high detail, 8K ultra quality, breathtaking panoramic view"
#    NEGATIVE="low quality, blurry, noisy, oversaturated, overexposed, dark, flat, flat lighting, dull, lifeless, ugly, deformed"
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_01_alps.png 2560 1440
#
# 2. 日本樱花
#    PROMPT="Japanese cherry blossoms, sakura trees in full bloom, pink flower petals falling, serene temple, traditional architecture, soft spring light, peaceful garden, Mt Fuji in background, photorealistic, high detail, 8K ultra quality, breathtaking view"
#    NEGATIVE="low quality, blurry, noisy, oversaturated, overexposed, dark, flat, flat lighting, dull, lifeless, ugly, deformed"
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_02_sakura.png 2560 1440
#
# 3. 冰岛极光
#    PROMPT="Iceland northern lights, aurora borealis dancing across the night sky, green and purple lights, snow-covered landscape, frozen lake reflection, Scandinavian pine trees, starry sky, dramatic nature, photorealistic, high detail, 8K ultra quality"
#    NEGATIVE="low quality, blurry, noisy, oversaturated, overexposed, dark, flat, flat lighting, dull, lifeless, ugly, deformed"
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_03_aurora.png 2560 1440
#
# 4. 马尔代夫海滩
#    PROMPT="Maldives tropical beach, crystal clear turquoise water, white sandy beach, palm trees, overwater bungalows, sunset sky, paradise island, coconuts, coral reef visible underwater, photorealistic, high detail, 8K ultra quality"
#    NEGATIVE="low quality, blurry, noisy, oversaturated, overexposed, dark, flat, flat lighting, dull, lifeless, ugly, deformed"
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_04_maldives.png 2560 1440
#
# 5. 非洲草原日落
#    PROMPT="African savanna sunset, golden grass plains, acacia trees silhouette, wildlife including elephants and giraffes, dramatic orange sky, dust particles in air, epic nature landscape, golden hour lighting, National Geographic quality, photorealistic, high detail, 8K ultra quality"
#    NEGATIVE="low quality, blurry, noisy, oversaturated, overexposed, dark, flat, flat lighting, dull, lifeless, ugly, deformed"
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_05_savanna.png 2560 1440
#
# 6. 科罗拉多大峡谷
#    PROMPT="Grand Canyon Colorado, majestic red rock formations, layered canyon walls, Colorado River winding through, dramatic lighting, golden hour, vast panoramic view, American Southwest landscape, photorealistic, high detail, 8K ultra quality, breathtaking scenery"
#    NEGATIVE="low quality, blurry, noisy, oversaturated, overexposed, dark, flat, flat lighting, dull, lifeless, ugly, deformed"
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_06_canyon.png 2560 1440
#
# 7. 挪威峡湾
#    PROMPT="Norwegian fjord, dramatic steep mountains, crystal clear blue water, small wooden houses, green valleys, waterfalls cascading down cliffs, scenic village, Nordic landscape, dramatic clouds, photorealistic, high detail, 8K ultra quality"
#    NEGATIVE="low quality, blurry, noisy, oversaturated, overexposed, dark, flat, flat lighting, dull, lifeless, ugly, deformed"
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_07_fjord.png 2560 1440
#
# 8. 新西兰南岛
#    PROMPT="New Zealand South Island, dramatic mountain peaks, turquoise lakes, lush green forests, rolling hills, sheep grazing, dramatic sky with clouds, Lord of the Rings landscape, scenic beauty, golden hour lighting, photorealistic, high detail, 8K ultra quality"
#    NEGATIVE="low quality, blurry, noisy, oversaturated, overexposed, dark, flat, flat lighting, dull, lifeless, ugly, deformed"
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_08_nz.png 2560 1440
#
# 9. 土耳其卡帕多奇亚
#    PROMPT="Cappadocia Turkey, fairy chimneys rock formations, hot air balloons floating, golden sunrise, unique geological landscape, ancient cave dwellings, dramatic sky, dreamy atmosphere, aerial view, photorealistic, high detail, 8K ultra quality"
#    NEGATIVE="low quality, blurry, noisy, oversaturated, overexposed, dark, flat, flat lighting, dull, lifeless, ugly, deformed"
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_09_cappadocia.png 2560 1440
#
# 10. 中国黄山
#    PROMPT="Yellow Mountain China, dramatic granite peaks, famous pine trees, sea of clouds, misty mountains, Chinese ink painting style, traditional shan shui scenery, ethereal atmosphere, Zhang Daqian art style, UNESCO World Heritage, photorealistic, high detail, 8K ultra quality"
#    NEGATIVE="low quality, blurry, noisy, oversaturated, overexposed, dark, flat, flat lighting, dull, lifeless, ugly, deformed"
#    ./img.sh "$PROMPT" /mnt/e/app/landscape_10_huangshan.png 2560 1440
#
# =============================================================================

MODEL_DIR="/opt/image/model"

PROMPT="${1:-A beautiful landscape}"
OUTPUT_FILE="$2"
WIDTH="${3:-1280}"
HEIGHT="${4:-720}"

NEGATIVE_PROMPT="${NEGATIVE_PROMPT:-}"

OUTPUT_DIR="$HOME"

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

mkdir -p "$OUTPUT_DIR"

echo "Generating image..."
echo "Prompt: $PROMPT"
echo "Negative: ${NEGATIVE_PROMPT:-(none)}"
echo "Size: ${WIDTH}x${HEIGHT}"
echo "Output: $OUTPUT_DIR/$OUTPUT"

/home/dministrator/stable-diffusion.cpp/bin/sd-cli \
  --diffusion-model "$MODEL_DIR/z_image_turbo-Q5_K_M.gguf" \
  --vae "$MODEL_DIR/ae.safetensors" \
  --llm "$MODEL_DIR/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  -p "$PROMPT" \
  -n "$NEGATIVE_PROMPT" \
  --cfg-scale 1.01 \
  --sampling-method euler \
  --diffusion-fa \
  --vae-tiling \
  --vae-tile-size 64x64 \
  -H "$HEIGHT" -W "$WIDTH" \
  --steps 15 \
  -s "$RANDOM" \
  -o "$OUTPUT_DIR/$OUTPUT"

echo "Image saved to: $OUTPUT_DIR/$OUTPUT"
