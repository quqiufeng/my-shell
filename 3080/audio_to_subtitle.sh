#!/bin/bash
# 根据配音文件生成对齐的字幕
#
# 参数说明:
#   $1 配音文件夹: 包含1.wav, 2.wav...的目录
#   $2 每段停顿: 每段配音后的停顿时间(秒)，默认0.3
#   $3 文案: 用|分隔每段文字
#   $4 输出字幕: 输出字幕文件路径
#
# 示例:
#   ./audio_to_subtitle.sh "/opt/image/audios/" 0.3 "第一句|第二句|第三句" /opt/image/subtitle.ass

AUDIO_DIR="$1"
PAUSE="${2:-0.3}"
TEXT="$3"
OUTPUT="$4"

if [ -z "$AUDIO_DIR" ] || [ -z "$TEXT" ] || [ -z "$OUTPUT" ]; then
    echo "用法: $0 <配音文件夹> <停顿秒数> <文案(用|分隔)> <输出字幕>"
    exit 1
fi

IFS='|' read -ra TEXT_ARRAY <<< "$TEXT"

# 生成ASS字幕头
cat > "$OUTPUT" << 'ASS_EOF'
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

# 计算每段字幕时间
CURRENT_TIME=0

for i in "${!TEXT_ARRAY[@]}"; do
    idx=$((i+1))
    text="${TEXT_ARRAY[$i]}"
    text=$(echo "$text" | xargs)
    
    # 自动换行
    text=$(auto_wrap "$text")
    
    # 获取配音时长
    if [ -f "$AUDIO_DIR/$idx.wav" ]; then
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_DIR/$idx.wav")
    else
        echo "警告: $AUDIO_DIR/$idx.wav 不存在，跳过"
        continue
    fi
    
    # 加上停顿
    DURATION=$(awk "BEGIN {print $DURATION + $PAUSE}")
    
    START_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int($CURRENT_TIME/60), $CURRENT_TIME%60}")
    END_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int(($CURRENT_TIME+$DURATION)/60), ($CURRENT_TIME+$DURATION)%60}")
    
    echo "Dialogue: 0,$START_TIME,$END_TIME,Default,,0,0,0,,$text" >> "$OUTPUT"
    
    CURRENT_TIME=$(awk "BEGIN {print $CURRENT_TIME + $DURATION}")
done

echo "字幕生成完成: $OUTPUT"
