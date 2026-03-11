#!/bin/bash
# 图片生成视频 + 配音 + 字幕（新流程）
# 特点：一次性配音，每段开头静音，段间停顿，根据配音时长生成字幕和分配图片时间
#
# 参数说明:
#   $1 图片: 图片文件夹/单张图片/空格分隔的图片路径
#   $2 每张秒数: 每张图片展示时长(秒)，默认2秒。建议: 短文案用2秒，长文案用2.5秒
#   $3 文案: 用|分隔每段文字
#   $4 参考音频: 用于克隆声音的音频文件路径
#   $5 输出视频: 输出文件路径，默认 output.mp4
#
# 示例:
#   ./img_to_video_v3.sh '/opt/image/' 2 '文案1|文案2|文案3' ./voice.wav output.mp4

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 参数
IMAGES="$1"
PER_IMAGE="${2:-2}"
TEXT="$3"
PROMPT_WAV="$4"
OUTPUT="${5:-output.mp4}"

# 静音参数
INTRO_SILENCE=0.3  # 每段开头静音
PAUSE=0.3          # 段间停顿

# 解析文案
IFS='|' read -ra TEXT_ARRAY <<< "$TEXT"
TEXT_COUNT=${#TEXT_ARRAY[@]}

echo "========================================"
echo "图片生成视频 + 配音 + 字幕（新流程）"
echo "========================================"
echo "图片: $IMAGES"
echo "文案: $TEXT_COUNT 段"
echo "静音: 开头${INTRO_SILENCE}秒, 段间${PAUSE}秒"
echo "输出: $OUTPUT"
echo "========================================"

# 检查图片
if [ -d "$IMAGES" ]; then
    IMG_LIST=$(ls -1 "$IMAGES"/*.png "$IMAGES"/*.jpg 2>/dev/null | head -$TEXT_COUNT)
    TOTAL_IMAGES=$(echo "$IMG_LIST" | wc -l)
    echo "检测到文件夹: $IMAGES"
    echo "图片数量: $TOTAL_IMAGES"
    echo "使用图片: $IMG_LIST"
elif [ -f "$IMAGES" ]; then
    IMG_LIST="$IMAGES"
    TOTAL_IMAGES=1
else
    echo "错误: 图片不存在: $IMAGES"
    exit 1
fi

# 检查参考音频
if [ "$PROMPT_WAV" != "none" ] && [ ! -f "$PROMPT_WAV" ]; then
    echo "错误: 参考音频不存在: $PROMPT_WAV"
    exit 1
fi

# 创建临时目录
WORK_DIR=$(mktemp -d)
AUDIO_DIR="$WORK_DIR/audios"
mkdir -p "$AUDIO_DIR"

echo ""
echo "[1/4] 生成配音..."

# 切换到CosyVoice目录，使用tts_batch_v3.py
source /home/dministrator/anaconda3/bin/activate cosyvoice
cd /home/dministrator/CosyVoice
python3 /home/dministrator/my-shell/3080/tts_batch_v3.py \
    "$PROMPT_WAV" \
    "$AUDIO_DIR" \
    "${TEXT_ARRAY[@]}"

# 合并配音（直接concat，不加额外静音）
echo ""
echo "[2/4] 合并配音..."

# 使用已合并的配音（带0.3秒段间停顿）
COMBINED_AUDIO="$AUDIO_DIR/merged.wav"

if [ ! -f "$COMBINED_AUDIO" ]; then
    echo "错误: 合并音频不存在"
    exit 1
fi

echo "  使用合并后的配音: $COMBINED_AUDIO"

echo "  配音合并完成"

# 获取合并后配音总时长
TOTAL_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$COMBINED_AUDIO")
echo "  总配音时长: ${TOTAL_DURATION}秒"

# 计算每张图停留时间（平均分配）
if [ $TOTAL_IMAGES -gt 0 ]; then
    PER_IMAGE_CALC=$(awk "BEGIN {printf \"%.2f\", $TOTAL_DURATION / $TOTAL_IMAGES}")
    echo "  每张图停留: ${PER_IMAGE_CALC}秒"
fi

# ========== 3. 生成字幕 ==========
echo ""
echo "[3/4] 生成字幕..."

SUB_ASS="$WORK_DIR/subtitle.ass"

# 生成ASS字幕头
cat > "$SUB_ASS" << 'ASS_EOF'
[Script Info]
Title: Generated Subtitle
ScriptType: v4.00+
WrapStyle: 1
ScaledBorderAndShadow: yes
YCbCr Matrix: None

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,WenQuanYi Zen Hei,14,&H00FFFF,&H00FFFF,&H000000,&H00666666,-1,0,0,0,100,100,0,0,1,2,2,2,10,10,20,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
ASS_EOF

# 自动换行函数
auto_wrap() {
    local text="$1"
    local max_len=12
    
    local len=${#text}
    
    if [ $len -le $max_len ]; then
        echo "$text"
        return
    fi
    
    local lines=$(( (len + max_len - 1) / max_len ))
    local result=""
    
    for i in $(seq 0 $((lines-1))); do
        local start=$((i * max_len))
        local end=$(((i + 1) * max_len))
        if [ $end -gt $len ]; then
            end=$len
        fi
        local chunk="${text:$start:$((end-start))}"
        if [ -n "$result" ]; then
            result="$result\\N$chunk"
        else
            result="$chunk"
        fi
    done
    echo "$result"
}

# 计算字幕时间（对齐配音）
# 从tts_batch_v3.py生成的时间文件读取
TIMING_FILE="$AUDIO_DIR/timings.txt"

if [ -f "$TIMING_FILE" ]; then
    while IFS=' :' read -r idx start end dur; do
        if [ -z "$idx" ] || [ "$idx" = "#" ]; then
            continue
        fi
        
        text_idx=$(echo "$idx" | tr -d ':')
        text="${TEXT_ARRAY[$((text_idx-1))]}"
        text=$(echo "$text" | xargs)
        text=$(auto_wrap "$text")
        
        START_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int($start/60), $start%60}")
        END_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int($end/60), $end%60}")
        
        echo "Dialogue: 0,$START_TIME,$END_TIME,Default,,0,0,0,,$text" >> "$SUB_ASS"
        
        echo "  字幕 $text_idx: $START_TIME -> $END_TIME"
    done < "$TIMING_FILE"
else
    echo "警告: 时间文件不存在，使用简单计算"
    CURRENT_TIME=0
    for i in "${!TEXT_ARRAY[@]}"; do
        idx=$((i+1))
        text="${TEXT_ARRAY[$i]}"
        text=$(echo "$text" | xargs)
        text=$(auto_wrap "$text")
        
        if [ -f "$AUDIO_DIR/$idx.wav" ]; then
            DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_DIR/$idx.wav")
        else
            DURATION=$PER_IMAGE_CALC
        fi
        
        START_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int($CURRENT_TIME/60), $CURRENT_TIME%60}")
        END_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int(($CURRENT_TIME+$DURATION)/60), ($CURRENT_TIME+$DURATION)%60}")
        
        echo "Dialogue: 0,$START_TIME,$END_TIME,Default,,0,0,0,,$text" >> "$SUB_ASS"
        
        CURRENT_TIME=$(awk "BEGIN {print $CURRENT_TIME + $DURATION + $PAUSE}")
        echo "  字幕 $idx: $START_TIME -> $END_TIME"
    done
fi

echo "  字幕生成完成"

# ========== 4. 生成视频 ==========
echo ""
echo "[4/4] 生成视频..."

SEG_DIR="$WORK_DIR/segments"
mkdir -p "$SEG_DIR"

IMG_ARRAY=($IMG_LIST)
CONCAT_LIST="$WORK_DIR/concat.txt"

for i in "${!IMG_ARRAY[@]}"; do
    idx=$((i+1))
    img="${IMG_ARRAY[$i]}"
    
    # 每张图停留时间
    duration=$PER_IMAGE_CALC
    
    # 生成视频片段
    ffmpeg -y -hide_banner -loglevel error \
        -loop 1 -i "$img" \
        -c:v libx264 -t $duration -pix_fmt yuv420p \
        -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2" \
        "$SEG_DIR/$idx.mp4" 2>/dev/null
    
    echo "file '$SEG_DIR/$idx.mp4'" >> "$CONCAT_LIST"
    echo "  处理图片 $idx: $img (时长: ${duration}秒)"
done

echo "  视频片段生成完成"

# 合并视频
TEMP_VIDEO="$WORK_DIR/temp_video.mp4"
ffmpeg -y -hide_banner -loglevel error \
    -f concat -safe 0 -i "$CONCAT_LIST" \
    -c copy "$TEMP_VIDEO"

# 添加配音和字幕
ffmpeg -y -hide_banner -loglevel error \
    -i "$TEMP_VIDEO" \
    -i "$COMBINED_AUDIO" \
    -vf "ass=$SUB_ASS" \
    -map 0:v -map 1:a \
    -c:v libx264 -c:a aac -shortest \
    "$OUTPUT"

echo ""
echo "========================================"
echo "完成！输出: $OUTPUT"
echo "========================================"

# 清理
rm -rf "$WORK_DIR"
