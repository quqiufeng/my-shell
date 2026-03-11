#!/bin/bash
# 图片生成视频 + 配音 + 字幕（多段文案版）
# 用法: ./img_to_video.sh <图片> <每张秒数> <文案> <参考音频> [输出视频] [延迟]

# 保存脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 参数
IMAGES="$1"
PER_IMAGE="${2:-2}"
TEXT="$3"
OUTPUT="${4:-output.mp4}"
DELAY="${5:-0.6}"

# v1版本：第4个参数不需要（预留）

# 去掉末尾的 /
IMAGES=$(echo "$IMAGES" | sed 's|/$||')

if [ -z "$IMAGES" ] || [ -z "$TEXT" ]; then
    echo "用法: $0 <图片> <每张秒数> <文案> [输出视频] [延迟]"
    echo ""
    echo "v1版本：使用SFT预设音色（中文女），不需要参考音频"
    echo ""
    echo "示例:"
    echo "  ./img_to_video.sh './story/' 2 '第一句|第二句|第三句' output.mp4"
    echo "  ./img_to_video.sh './story/' 2 '第一句|第二句|第三句' ./voice.wav"
    exit 1
fi

# 处理图片输入
IMG_LIST=""
WORK_DIR="/tmp/img_$$"
mkdir -p "$WORK_DIR"

# 判断输入类型
if [[ "$IMAGES" == http://* ]] || [[ "$IMAGES" == https://* ]]; then
    echo "检测到 HTTP 图片，下载到本地..."
    for url in $IMAGES; do
        filename=$(basename "$url")
        wget -q "$url" -O "$WORK_DIR/$filename"
        [ -f "$WORK_DIR/$filename" ] && IMG_LIST="$IMG_LIST $WORK_DIR/$filename"
    done
elif [ -d "$IMAGES" ]; then
    echo "检测到文件夹: $IMAGES"
    for f in $(ls "$IMAGES"/*.{jpg,jpeg,png,JPG,JPEG,PNG} 2>/dev/null | sort); do
        [ -f "$f" ] && IMG_LIST="$IMG_LIST $f"
    done
else
    for img in $IMAGES; do
        if [[ "$img" == http://* ]] || [[ "$img" == https://* ]]; then
            filename=$(basename "$img")
            wget -q "$img" -O "$WORK_DIR/$filename"
            [ -f "$WORK_DIR/$filename" ] && IMG_LIST="$IMG_LIST $WORK_DIR/$filename"
        elif [ -f "$img" ]; then
            IMG_LIST="$IMG_LIST $img"
        fi
    done
fi

# 修复路径中的 //
IMG_LIST=$(echo "$IMG_LIST" | sed 's|//|/|g')
IMG_LIST=$(echo "$IMG_LIST" | xargs)

TOTAL_IMAGES=$(echo $IMG_LIST | wc -w)

if [ -z "$IMG_LIST" ]; then
    echo "错误: 未找到图片"
    rm -rf "$WORK_DIR"
    exit 1
fi

echo "图片数量: $TOTAL_IMAGES"
echo "使用图片: $IMG_LIST"

# v1版本不需要参考音频

# 判断文案类型
IFS='|' read -ra TEXT_ARRAY <<< "$TEXT"
TOTAL_TEXTS=${#TEXT_ARRAY[@]}

echo "========================================"
echo "图片生成视频 + 配音 + 字幕"
echo "========================================"
echo "图片: $TOTAL_IMAGES 张"
echo "每张: ${PER_IMAGE}秒"
echo "文案: $TOTAL_TEXTS 段"
echo "输出: $OUTPUT"
echo "========================================"

# 临时文件
AUDIO_DIR="/tmp/audios_$$"
mkdir -p "$AUDIO_DIR"
SUB_ASS="/tmp/sub_$$.ass"

echo ""
echo "[1/4] 生成配音..."

# 使用批量配音脚本，模型只加载一次
cd /opt/CosyVoice
conda run -n cosyvoice2 python3 /opt/my-shell/4090d/tts_batch_v1.py \
    "/opt/CosyVoice/pretrained_models/CosyVoice-300M-SFT" \
    "none" \
    "$AUDIO_DIR" \
    "${TEXT_ARRAY[@]}"

echo "  配音生成完成"

echo ""
echo "[2/4] 生成字幕..."

# 生成 ASS 字幕
cat > "$SUB_ASS" << 'ASS_EOF'
[Script Info]
Title: Generated Subtitle
ScriptType: v4.00+
WrapStyle: 1
ScaledBorderAndShadow: yes
YCbCr Matrix: None

[V4+ Styles]
# 颜色格式: &H00BBGGRR (BGR, 倒序)
# 黄色 = &H00FFFF (红色+绿色)
# 红色 = &H00FF   # 蓝色 = &H00FF0000
# 绿色 = &H0000FF # 白色 = &H00FFFFFF
# 黑色 = &H000000
# MarginV: 字幕距离底部距离
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,WenQuanYi Zen Hei,14,&H00FFFF,&H00FFFF,&H000000,&H00666666,-1,0,0,0,100,100,0,0,1,2,2,2,10,10,20,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
ASS_EOF

# 计算每段字幕时间（和配音同步，每段后加0.3秒延迟）
CURRENT_TIME=0

# 自动换行函数（根据分辨率动态计算）
auto_wrap() {
    local text="$1"
    local width=${2:-1080}  # 默认1080宽度
    
    # 1080宽度约12个汉字每行，按比例计算
    local max_len=$((width / 90))
    if [ $max_len -lt 6 ]; then
        max_len=6
    fi
    
    local len=${#text}
    
    if [ $len -le $max_len ]; then
        echo "$text"
        return
    fi
    
    # 计算需要几行
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

for i in "${!TEXT_ARRAY[@]}"; do
    idx=$((i+1))
    text="${TEXT_ARRAY[$i]}"
    text=$(echo "$text" | xargs)
    
    # 自动换行（1080宽度）
    text=$(auto_wrap "$text" 1080)
    
    # 使用实际配音时长 + 0.3秒停顿
    if [ -f "$AUDIO_DIR/$idx.wav" ]; then
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_DIR/$idx.wav")
    else
        DURATION=$PER_IMAGE
    fi
    
    # 加上0.3秒停顿
    DURATION=$(awk "BEGIN {print $DURATION + 0.3}")
    
    START_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int($CURRENT_TIME/60), $CURRENT_TIME%60}")
    END_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int(($CURRENT_TIME+$DURATION)/60), ($CURRENT_TIME+$DURATION)%60}")
    
    echo "Dialogue: 0,$START_TIME,$END_TIME,Default,,0,0,0,,$text" >> "$SUB_ASS"
    
    CURRENT_TIME=$(awk "BEGIN {print $CURRENT_TIME + $DURATION}")
done

echo "  字幕生成完成"

echo ""
echo "[3/4] 生成视频片段..."

# 每张图片转视频片段（使用配音时长）
SEG_DIR="/tmp/segs_$$"
mkdir -p "$SEG_DIR"

FADE_DURATION=0.5

# 替换 // 为 /
IMAGES=$(echo "$IMAGES" | sed 's|//|/|g')

# 用 find 获取图片列表
IMG_LIST=$(find "$IMAGES" -maxdepth 1 \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | sort -V | tr '\n' ' ')

echo "使用图片: $IMG_LIST"

i=0
for img in $IMG_LIST; do
    # 使用实际配音时长 + 0.3秒停顿
    audio_idx=$((i+1))
    if [ -f "$AUDIO_DIR/$audio_idx.wav" ]; then
        SEG_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_DIR/$audio_idx.wav")
    else
        SEG_DURATION=$PER_IMAGE
    fi
    
    # 加上0.3秒停顿
    SEG_DURATION=$(awk "BEGIN {print $SEG_DURATION + 0.3}")
    
    echo "  处理图片 $((i+1)): $img (时长: ${SEG_DURATION}秒)"
    ffmpeg -y -loop 1 -i "$img" -vf "scale=1080:1920" -c:v libx264 -t "$SEG_DURATION" -pix_fmt yuv420p "$SEG_DIR/seg_$i.mp4" 2>&1 | tail -3
    if [ -f "$SEG_DIR/seg_$i.mp4" ]; then
        echo "    OK"
    fi
    i=$((i+1))
done

# 合并片段
CONCAT_LIST="/tmp/concat_$$.txt"
for f in $(ls $SEG_DIR/seg_*.mp4 2>/dev/null | sort -V); do
    echo "file '$f'" >> "$CONCAT_LIST"
done

if [ ! -s "$CONCAT_LIST" ]; then
    echo "错误: 没有生成视频片段"
    exit 1
fi

TEMP_VIDEO="/tmp/video_$$.mp4"
ffmpeg -y -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$TEMP_VIDEO" 2>/dev/null

echo "  视频片段生成完成"

echo ""
echo "[4/4] 合成最终视频..."

# 合并所有配音，每段之间加0.3秒延迟（和字幕/视频片段一致）
AUDIO_LIST="/tmp/audio_list_$$.txt"
PADDED_DIR="/tmp/padded_$$"
mkdir -p "$PADDED_DIR"

for i in $(seq 1 $TOTAL_TEXTS); do
    ffmpeg -y -i "$AUDIO_DIR/$i.wav" -af "apad=pad_dur=0.3" "$PADDED_DIR/$i.wav" 2>/dev/null
    echo "file '$PADDED_DIR/$i.wav'" >> "$AUDIO_LIST"
done

COMBINED_AAC="/tmp/combined_$$.aac"
ffmpeg -y -f concat -safe 0 -i "$AUDIO_LIST" -c:a aac "$COMBINED_AAC" 2>/dev/null

# 合成最终视频
ffmpeg -y -i "$TEMP_VIDEO" -i "$COMBINED_AAC" -vf "ass=$SUB_ASS" \
    -map 0:v -map 1:a \
    -c:v libx264 -c:a aac -shortest \
    "$OUTPUT" 2>/dev/null

echo ""
echo "========================================"
echo "完成！输出: $OUTPUT"
echo "========================================"

# 清理
rm -rf "$WORK_DIR" "$AUDIO_DIR" "$SEG_DIR" "$CONCAT_LIST" "$AUDIO_LIST" "$TEMP_VIDEO" "$COMBINED_AAC" "$SUB_ASS"
