#!/bin/bash
# 图片生成视频 + 配音 + 字幕（多段文案版，支持声音克隆）
# 
# ⚠️ 修复记录：Fun-CosyVoice3模型对短文本(<10字)会生成异常音频(0.08秒)
#    解决方案：使用inference_instruct2 + tts_text前加换行符(\n)
#
# 参数说明:
#   $1 图片: 图片文件夹/单张图片/空格分隔的图片路径
#   $2 每张秒数: 每张图片展示时长(秒)，默认2秒。建议: 短文案用2秒，长文案用2.5秒
#   $3 文案: 用|分隔每段文字，如 "第一句|第二句|第三句"
#   $4 参考音频: 用于克隆声音的音频文件路径 (3-30秒)
#   $5 输出视频: 输出文件路径，默认 output.mp4
#
# 示例:
#   ./img_to_video_v2.sh '/opt/image/' 2 '文案1|文案2|文案3' ./voice.wav output.mp4

# 保存脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 参数
IMAGES="$1"
PER_IMAGE="${2:-2}"
TEXT="$3"
PROMPT_WAV="$4"
OUTPUT="${5:-output.mp4}"

# 去掉末尾的 /
IMAGES=$(echo "$IMAGES" | sed 's|/$||')

if [ -z "$IMAGES" ] || [ -z "$TEXT" ] || [ -z "$PROMPT_WAV" ]; then
    echo "用法: $0 <图片> <每张秒数> <文案> <参考音频> [输出视频] [延迟]"
    echo ""
    echo "文案格式:"
    echo "  - 单文案: '整段文案' (全部图片用同一文案)"
    echo "  - 多段文案: '第一句|第二句|第三句...' (用 | 分隔，每段对应一张图片)"
    echo ""
    echo "示例:"
    echo "  # 单文案"
    echo "  ./img_to_video.sh './story/' 2 '古时候有个书生' ./voice.wav"
    echo ""
    echo "  # 多段文案（每张图片配不同文案）"
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

if [ ! -f "$PROMPT_WAV" ]; then
    echo "错误: 参考音频不存在: $PROMPT_WAV"
    rm -rf "$WORK_DIR"
    exit 1
fi

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

# 激活 conda
source $HOME/anaconda3/bin/activate cosyvoice

echo ""
echo "[1/4] 生成配音..."

# v2版本：每段单独配音
cd $HOME/CosyVoice

for i in "${!TEXT_ARRAY[@]}"; do
    idx=$((i+1))
    text="${TEXT_ARRAY[$i]}"
    text=$(echo "$text" | xargs)
    
    echo "  配音 $idx: $text"
    
    # 使用 Fun-CosyVoice3-0.5B + TensorRT
    python3 << EOF
import sys
sys.path.append('$HOME/CosyVoice/third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio

cosyvoice = AutoModel(model_dir='/opt/image/Fun-CosyVoice3-0.5B', load_trt=True, fp16=True)

# prompt_text改为空，tts_text前加换行符
prompt = '<|endofprompt|>'
tts_text = '\n$text'

for j in cosyvoice.inference_instruct2(tts_text, prompt, '$PROMPT_WAV', stream=False):
    torchaudio.save('$AUDIO_DIR/$idx.wav', j['tts_speech'], cosyvoice.sample_rate)
    audio_len = j["tts_speech"].shape[1]/cosyvoice.sample_rate
    print(f'    长度: {audio_len:.2f}秒')
EOF
done

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

# 字幕时间：从0开始，每段持续配音时长+0.3秒停顿
CURRENT_TIME=0

for i in "${!TEXT_ARRAY[@]}"; do
    idx=$((i+1))
    text="${TEXT_ARRAY[$i]}"
    text=$(echo "$text" | xargs)
    
    # 自动换行
    text=$(auto_wrap "$text" 1080)
    
    # 使用实际配音时长 + 0.3秒停顿（和视频/音频一致）
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
IMG_LIST=$(echo "$IMG_LIST" | sed 's|//|/|g')

# 用 find 获取图片列表
IMG_LIST=$(find "$IMAGES" -maxdepth 1 \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | sort -V | tr '\n' ' ')

echo "使用图片: $IMG_LIST"

i=0
for img in $IMG_LIST; do
    # 使用实际配音时长 + 0.3秒停顿（和音频一致）
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

# 合并所有配音，每段之间加0.3秒延迟
AUDIO_LIST="/tmp/audio_list_$$.txt"
PADDED_DIR="/tmp/padded_$$"
mkdir -p "$PADDED_DIR"

# 给每段音频前后加0.3秒静音（和字幕/视频片段一致）
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
