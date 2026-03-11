#!/bin/bash
# 给已有视频配字幕+配音
# 
# 参数说明:
#   $1 视频: 输入视频文件
#   $2 文案信息文件: 包含产品介绍信息的文件路径
#   $3 克隆音频: (可选)用于克隆声音的音频文件，不传则使用默认SFT音色
#   $4 输出视频: (可选)输出文件路径，默认在输入视频同目录下添加 _subtitled 后缀
#
# 示例:
#   ./video_subtitle_voice.sh ./video.mp4 ./info.txt
#   ./video_subtitle_voice.sh ./video.mp4 ./info.txt ./voice.wav
#
# 案例：JBL产品介绍
#   ./video_subtitle_voice.sh ~/video/1.mp4 ~/video/info.txt

# ==================== 配置变量 ====================
INTRO_PAUSE=0.2
SPEED=1.2
PAUSE=0.3
SUBTITLE_CHAR_LIMIT=12
# ==================== 配置变量 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

INPUT_VIDEO="$1"
INFO_FILE="$2"
PROMPT_WAV="$3"
OUTPUT="$4"

# 参数检查
if [ -z "$INPUT_VIDEO" ] || [ -z "$INFO_FILE" ]; then
    echo "用法: $0 <视频> <文案信息文件> [克隆音频] [输出视频]"
    echo ""
    echo "参数说明:"
    echo "  视频: 输入视频文件 (必填)"
    echo "  文案信息文件: (必填)包含产品介绍信息的文件路径"
    echo "  克隆音频: (可选)用于克隆声音的音频文件，默认 ./voice.wav"
    echo "  输出视频: (可选)输出文件路径，默认在输入视频同目录下添加 _subtitled 后缀"
    echo ""
    echo "示例:"
    echo "  $0 ./video.mp4 ./info.txt"
    echo "  $0 ./video.mp4 ./info.txt ./voice.wav"
    exit 1
fi

# 默认克隆音频
if [ -z "$PROMPT_WAV" ]; then
    PROMPT_WAV="./voice.wav"
fi

if [ ! -f "$INFO_FILE" ]; then
    echo "错误: 文案信息文件不存在: $INFO_FILE"
    exit 1
fi

# 从信息文件生成文案
echo "[0/3] 自动生成文案..."
TEXT=$(python3 -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from prompt import get_video_duration, calculate_char_count, generate_subtitle
duration = get_video_duration('$INPUT_VIDEO')
est_chars = calculate_char_count(duration, speed=3.1, adjust=0)
result = generate_subtitle('$INPUT_VIDEO', '$INFO_FILE', total_chars=est_chars)
print(result)
")
echo "  自动生成文案: ${TEXT:0:50}..."

# 检测并合并不达标的段落（每段至少12个汉字）
MIN_CHARS=12
TEXT=$(python3 -c "
import sys
text = '''$TEXT'''
segments = text.split('|')
result = []
current = ''
for seg in segments:
    chinese = sum(1 for c in seg if '\u4e00' <= c <= '\u9fff')
    if chinese >= $MIN_CHARS:
        if current:
            result.append(current)
            current = ''
        result.append(seg)
    else:
        current += seg
if current:
    result.append(current)
print('|'.join(result))
")

if [ -z "$TEXT" ]; then
    echo "错误: 文案为空"
    exit 1
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

cd ~/CosyVoice

# 激活 conda
source $HOME/anaconda3/bin/activate cosyvoice

echo ""
echo "[1/3] 生成配音..."

if [ -n "$PROMPT_WAV" ] && [ -f "$PROMPT_WAV" ]; then
    python3 ~/my-shell/3080/tts_batch.py \
        "/opt/image/Fun-CosyVoice3-0.5B" \
        "$PROMPT_WAV" \
        "$AUDIO_DIR" \
        "$SPEED" \
        "${TEXT_ARRAY[@]}"
else
    python3 ~/my-shell/3080/tts_batch.py \
        "/opt/image/CosyVoice-300M-SFT" \
        "none" \
        "$AUDIO_DIR" \
        "$SPEED" \
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
Style: Default,Noto Sans CJK SC Bold,14,&H00FFFF,&H00FFFF,&H000000,&H00666666,-1,0,0,0,100,100,0,0,1,2,0,2,10,10,20,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
ASS_EOF

CURRENT_TIME=$INTRO_PAUSE

for i in "${!TEXT_ARRAY[@]}"; do
    idx=$((i+1))
    text="${TEXT_ARRAY[$i]}"
    text=$(echo "$text" | xargs)
    text_no_punct=$(echo "$text" | sed 's/[,，。、！!？?。；;：:""''（）()【】《》]//g')
    
    # 超过13个汉字则换行
    chinese_count=$(echo "$text_no_punct" | grep -oP '\p{Han}' | wc -l)
    if [ "$chinese_count" -gt 13 ]; then
        text_no_punct=$(python3 -c "
text = '''$text_no_punct'''
count = 0
pos = 0
for i, c in enumerate(text):
    if '\u4e00' <= c <= '\u9fff':
        count += 1
        if count == 13:
            pos = i + 1
            break
if pos > 0:
    print(text[:pos] + r'\N' + text[pos:])
else:
    print(text)
")
    fi
    
    duration="${ADJUSTED_DURATIONS[$i]}"
    # 每段字幕前后各加0.2秒停顿
    duration_with_pause=$(awk "BEGIN {print $duration + $PAUSE + $INTRO_PAUSE}")
    
    # 不拆分字幕，整段显示
    START_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int($CURRENT_TIME/60), $CURRENT_TIME%60}")
    END_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int(($CURRENT_TIME+$duration_with_pause)/60), ($CURRENT_TIME+$duration_with_pause)%60}")
    echo "Dialogue: 0,$START_TIME,$END_TIME,Default,,0,0,0,,$text_no_punct" >> "$SUB_ASS"
    CURRENT_TIME=$(awk "BEGIN {print $CURRENT_TIME + $duration_with_pause}")
done

echo "  字幕生成完成"

echo ""
echo "[3/3] 合成最终视频..."

# 给每段音频加0.2秒前后停顿
PADDED_DIR="/tmp/padded_$$"
mkdir -p "$PADDED_DIR"
for i in $(seq 1 $TOTAL_TEXTS); do
    # 先加前端0.2秒静音
    ffmpeg -y -f lavfi -i "anullsrc=r=16000:cl=mono:d=$INTRO_PAUSE" -i "$AUDIO_DIR/$i.wav" -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1" "$PADDED_DIR/${i}_prefix.wav" 2>/dev/null
    # 再加后端0.3秒静音
    ffmpeg -y -i "$PADDED_DIR/${i}_prefix.wav" -af "apad=pad_dur=$PAUSE" "$PADDED_DIR/$i.wav" 2>/dev/null
done

# 给整体音频加0.2秒前置偏移，对齐字幕
AUDIO_LIST="/tmp/audio_list_$$.txt"
for i in $(seq 1 $TOTAL_TEXTS); do
    echo "file '$PADDED_DIR/$i.wav'" >> "$AUDIO_LIST"
done

COMBINED_AAC="/tmp/combined_$$.aac"
ffmpeg -y -f concat -safe 0 -i "$AUDIO_LIST" -c:a aac "$COMBINED_AAC" 2>/dev/null

# 整体前置0.2秒静音对齐字幕
ffmpeg -y -f lavfi -i "anullsrc=r=16000:cl=mono:d=$INTRO_PAUSE" -i "$COMBINED_AAC" -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1" "$COMBINED_AAC" 2>/dev/null

ffmpeg -y -i "$INPUT_VIDEO" -i "$COMBINED_AAC" -vf "ass=$SUB_ASS" -af "volume=1.5" \
    -map 0:v -map 1:a \
    -c:v libx264 -c:a aac -shortest \
    "$OUTPUT" 2>/dev/null

rm -rf "$AUDIO_LIST" "$COMBINED_AAC" "$PROMPT_WAV_WAV" "$PADDED_DIR"

echo ""
echo "========================================"
echo "完成！输出: $OUTPUT"
echo "========================================"
