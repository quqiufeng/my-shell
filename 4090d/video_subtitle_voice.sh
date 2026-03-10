#!/bin/bash
# 给已有视频配字幕+配音
# 
# 参数说明:
#   $1 视频: 输入视频文件
#   $2 文案: 用|分隔每段文字，如 "第一句|第二句|第三句"
#   $3 克隆音频: (可选)用于克隆声音的音频文件路径，不提供则使用默认SFT音色
#   $4 输出视频: (可选)输出文件路径，默认在输入视频同目录下添加 _subtitled 后缀
#
# 示例:
#   ./video_subtitle_voice.sh ./input.mp4 '文案1|文案2|文案3' ./voice.wav
#   ./video_subtitle_voice.sh ./input.mp4 '文案1|文案2|文案3'
#
# 案例：38秒视频，每12汉字一段字幕
#   ./video_subtitle_voice.sh '/opt/video/1.mp4' 'JBL成立于1946年是全球|全球音响领域中极少数横跨|专业录音室电影院大型演出|现场车载音响及个人消费电|子五大领域顶级品牌标准制|定者全球超过50的影院和|70的大型体育场馆均采用|JBL设备它定义了现代扩|声系统的音效标准监听标杆|其经典的监听扬声器曾广泛|应用于顶级录音室被视为还|原音乐真实动态的教科书' /opt/video/voice.wav

# ==================== 配置变量 ====================
INTRO_PAUSE=0.2
SPEED=4.5
PAUSE=0.3
SUBTITLE_CHAR_LIMIT=12
# ==================== 配置变量 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

INPUT_VIDEO="$1"
PROMPT_WAV="$2"
TEXT="$3"
OUTPUT="$4"

# 参数检查
if [ -z "$INPUT_VIDEO" ] || [ -z "$PROMPT_WAV" ] || [ -z "$TEXT" ]; then
    echo "用法: $0 <视频> <克隆音频> <文案> [输出视频]"
    echo ""
    echo "参数说明:"
    echo "  视频: 输入视频文件 (必填)"
    echo "  克隆音频: (必填)用于克隆声音的音频文件"
    echo "  文案: 字幕文案，用|分隔 (必填，支持文件路径或直接文本)"
    echo "  输出视频: (可选)输出文件路径，默认在输入视频同目录下添加 _subtitled 后缀"
    echo ""
    echo "示例:"
    echo "  $0 ./video.mp4 ./voice.wav '文案1|文案2|文案3'"
    echo "  $0 ./video.mp4 ./voice.wav ./subtitle.txt"
    exit 1
fi

# 如果文案是文件路径，读取文件内容
if [ -f "$TEXT" ]; then
    TEXT=$(cat "$TEXT")
fi

if [ ! -f "$INPUT_VIDEO" ]; then
    echo "错误: 视频文件不存在: $INPUT_VIDEO"
    exit 1
fi

VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_VIDEO")
VIDEO_RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$INPUT_VIDEO")

if [ -z "$OUTPUT" ]; then
    input_dir=$(dirname "$INPUT_VIDEO")
    input_name=$(basename "$INPUT_VIDEO")
    input_ext="${input_name##*.}"
    input_name_noext="${input_name%.*}"
    OUTPUT="${input_dir}/${input_name_noext}_subtitled.${input_ext}"
fi

IFS='|' read -ra TEXT_ARRAY <<< "$TEXT"
TOTAL_TEXTS=${#TEXT_ARRAY[@]}

# 调试模式：只显示文案信息
if [ "$DEBUG" = "1" ]; then
    echo "========================================"
    echo "调试模式：只显示文案信息"
    echo "========================================"
    echo "视频: $INPUT_VIDEO"
    echo "时长: ${VIDEO_DURATION}秒"
    echo "段数: $TOTAL_TEXTS"
    echo ""
    echo "字幕文案:"
    for i in "${!TEXT_ARRAY[@]}"; do
        idx=$((i+1))
        echo "  $idx: ${TEXT_ARRAY[$i]}"
    done
    exit 0
fi

echo "========================================"
echo "视频配字幕 + 配音"
echo "========================================"
echo "视频: $INPUT_VIDEO"
echo "时长: ${VIDEO_DURATION}秒"
echo "文案: $TOTAL_TEXTS 段"
if [ -n "$PROMPT_WAV" ] && [ -f "$PROMPT_WAV" ]; then
    echo "配音: 克隆 (参考音频: $PROMPT_WAV)"
else
    echo "配音: 默认SFT音色"
fi
echo "输出: $OUTPUT"
echo "========================================"

AUDIO_DIR="$(dirname "$INPUT_VIDEO")/audio_$(basename "$INPUT_VIDEO" .mp4)"
mkdir -p "$AUDIO_DIR"
SUB_ASS="$(dirname "$INPUT_VIDEO")/$(basename "$INPUT_VIDEO" .mp4).ass"

if [ -n "$PROMPT_WAV" ] && [ -f "$PROMPT_WAV" ]; then
    PROMPT_WAV_EXT="${PROMPT_WAV##*.}"
    if [ "$PROMPT_WAV_EXT" != "wav" ]; then
        PROMPT_WAV_WAV="$(dirname "$INPUT_VIDEO")/$(basename "$PROMPT_WAV" .$PROMPT_WAV_EXT).wav"
        if [ ! -f "$PROMPT_WAV_WAV" ]; then
            ffmpeg -y -i "$PROMPT_WAV" -ar 16000 -ac 1 "$PROMPT_WAV_WAV" 2>/dev/null
        fi
        PROMPT_WAV="$PROMPT_WAV_WAV"
    fi
fi

cd /opt/CosyVoice

echo ""
echo "[1/3] 生成配音..."

if [ -n "$PROMPT_WAV" ] && [ -f "$PROMPT_WAV" ]; then
    conda run -n cosyvoice2 python3 /opt/my-shell/4090d/tts_batch.py \
        "/opt/CosyVoice/pretrained_models/Fun-CosyVoice3-0.5B" \
        "$PROMPT_WAV" \
        "$AUDIO_DIR" \
        "${TEXT_ARRAY[@]}"
else
    conda run -n cosyvoice2 python3 /opt/my-shell/4090d/tts_batch.py \
        "/opt/CosyVoice/pretrained_models/CosyVoice-300M-SFT" \
        "none" \
        "$AUDIO_DIR" \
        "${TEXT_ARRAY[@]}"
fi

echo "  配音生成完成"

# 获取每段时长
declare -a ADJUSTED_DURATIONS
for i in $(seq 1 $TOTAL_TEXTS); do
    dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_DIR/$i.wav")
    ADJUSTED_DURATIONS+=($dur)
done

echo ""
echo "[2/3] 生成字幕..."

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

CURRENT_TIME=$INTRO_PAUSE

for i in "${!TEXT_ARRAY[@]}"; do
    idx=$((i+1))
    text="${TEXT_ARRAY[$i]}"
    text=$(echo "$text" | xargs)
    text_no_punct=$(echo "$text" | sed 's/[,，。、！!？?。；;：:""''（）()【】《》]//g')
    
    duration="${ADJUSTED_DURATIONS[$i]}"
    # 每段字幕后加0.3秒停顿
    duration_with_pause=$(awk "BEGIN {print $duration + $PAUSE}")
    
    # 不拆分字幕，整段显示
    START_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int($CURRENT_TIME/60), $CURRENT_TIME%60}")
    END_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int(($CURRENT_TIME+$duration_with_pause)/60), ($CURRENT_TIME+$duration_with_pause)%60}")
    echo "Dialogue: 0,$START_TIME,$END_TIME,Default,,0,0,0,,$text_no_punct" >> "$SUB_ASS"
    CURRENT_TIME=$(awk "BEGIN {print $CURRENT_TIME + $duration_with_pause}")
done

echo "  字幕生成完成"

echo ""
echo "[3/3] 合成最终视频..."

# 给每段音频加0.3秒静音
PADDED_DIR="/tmp/padded_$$"
mkdir -p "$PADDED_DIR"
for i in $(seq 1 $TOTAL_TEXTS); do
    ffmpeg -y -i "$AUDIO_DIR/$i.wav" -af "apad=pad_dur=$PAUSE" "$PADDED_DIR/$i.wav" 2>/dev/null
done

# 给第一个音频文件前端加0.2秒静音
ffmpeg -y -f lavfi -i "anullsrc=r=16000:cl=mono:d=$INTRO_PAUSE" -i "$PADDED_DIR/1.wav" -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1" "$PADDED_DIR/1_intro.wav" 2>/dev/null && \
mv "$PADDED_DIR/1_intro.wav" "$PADDED_DIR/1.wav"

AUDIO_LIST="/tmp/audio_list_$$.txt"
for i in $(seq 1 $TOTAL_TEXTS); do
    echo "file '$PADDED_DIR/$i.wav'" >> "$AUDIO_LIST"
done

COMBINED_AAC="/tmp/combined_$$.aac"
ffmpeg -y -f concat -safe 0 -i "$AUDIO_LIST" -c:a aac "$COMBINED_AAC" 2>/dev/null

ffmpeg -y -i "$INPUT_VIDEO" -i "$COMBINED_AAC" -vf "ass=$SUB_ASS" \
    -map 0:v -map 1:a \
    -c:v libx264 -c:a aac -shortest \
    "$OUTPUT" 2>/dev/null

rm -rf "$AUDIO_LIST" "$COMBINED_AAC" "$PROMPT_WAV_WAV" "$PADDED_DIR"

echo ""
echo "========================================"
echo "完成！输出: $OUTPUT"
echo "========================================"
