#!/bin/bash
# 给已有视频配字幕+配音
# 
# 参数说明:
#   $1 视频: 输入视频文件
#   $2 文案: 用|分隔每段文字，如 "第一句|第二句|第三句"
#   $3 克隆音频: (可选)用于克隆声音的音频文件路径，不提供则使用默认SFT音色
#   $4 输出视频: (可选)输出文件路径，默认在输入视频同目录下添加 _subtitled 后缀
#
# 克隆音频要求:
#   - 格式: wav, mp3, flac 等
#   - 采样率: >= 16000 Hz（会自动重采样到16kHz）
#   - 建议时长: 3-30秒（太短可能特征不足）
#
# 示例:
#   ./video_subtitle_voice.sh ./input.mp4 '文案1|文案2|文案3' ./voice.wav
#   ./video_subtitle_voice.sh ./input.mp4 '文案1|文案2|文案3'
#   ./video_subtitle_voice.sh ./input.mp4 '文案1|文案2|文案3' ./voice.wav ./output.mp4

# ==================== 配置变量 ====================
# 开头停顿秒数：视频开始后N秒开始出字幕和声音
INTRO_PAUSE=0.2

# 语速：中文字/秒（值越大语速越快）
SPEED=4.5

# 段间停顿秒数
PAUSE=0.3
# ==================== 配置变量 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

INPUT_VIDEO="$1"
TEXT="$2"
PROMPT_WAV="$3"
OUTPUT="$4"

if [ -z "$INPUT_VIDEO" ] || [ -z "$TEXT" ]; then
    echo "用法: $0 <视频> <文案> [克隆音频] [输出视频]"
    echo ""
    echo "文案格式:"
    echo "  - 单文案: '整段文案'"
    echo "  - 多段文案: '第一句|第二句|第三句...' (用 | 分隔)"
    echo ""
    echo "示例:"
    echo "  # 有克隆音频"
    echo "  ./video_subtitle_voice.sh './input.mp4' '文案1|文案2|文案3' ./voice.wav"
    echo ""
    echo "  # 无克隆音频，使用默认音色"
    echo "  ./video_subtitle_voice.sh './input.mp4' '文案1|文案2|文案3'"
    echo ""
    echo "  # 指定输出路径"
    echo "  ./video_subtitle_voice.sh './input.mp4' '文案1|文案2|文案3' ./voice.wav ./output.mp4"
    exit 1
fi

if [ ! -f "$INPUT_VIDEO" ]; then
    echo "错误: 视频文件不存在: $INPUT_VIDEO"
    exit 1
fi

# 获取视频信息
VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_VIDEO")
VIDEO_RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$INPUT_VIDEO")

# 默认输出路径
if [ -z "$OUTPUT" ]; then
    input_dir=$(dirname "$INPUT_VIDEO")
    input_name=$(basename "$INPUT_VIDEO")
    input_ext="${input_name##*.}"
    input_name_noext="${input_name%.*}"
    OUTPUT="${input_dir}/${input_name_noext}_subtitled.${input_ext}"
fi

# 判断文案类型
IFS='|' read -ra TEXT_ARRAY <<< "$TEXT"
TOTAL_TEXTS=${#TEXT_ARRAY[@]}

echo "========================================"
echo "视频配字幕 + 配音"
echo "========================================"
echo "视频: $INPUT_VIDEO"
echo "时长: ${VIDEO_DURATION}秒"
echo "分辨率: $VIDEO_RES"
echo "文案: $TOTAL_TEXTS 段"
if [ -n "$PROMPT_WAV" ] && [ -f "$PROMPT_WAV" ]; then
    echo "配音: 克隆 (参考音频: $PROMPT_WAV)"
else
    echo "配音: 默认SFT音色"
fi
echo "输出: $OUTPUT"
echo "========================================"

# 计算每段文案时长（根据视频总时长按字数比例分配）
# 参数: 视频总时长, 文案数组
calculate_durations() {
    local total_video=$1
    shift
    local texts=("$@")
    
    # 减去开头停顿
    total_video=$(awk "BEGIN {print $total_video - $INTRO_PAUSE}")
    
    # 计算总字数
    local total_chars=0
    for text in "${texts[@]}"; do
        total_chars=$((total_chars + ${#text}))
    done
    
    # 预估语速: 使用变量 SPEED（中文字/秒）
    local speed=$SPEED
    
    # 计算每段时长（按字数比例 + 停顿）
    local durations=()
    local calc_total=0
    
    for i in "${!texts[@]}"; do
        local chars=${#texts[$i]}
        # 基础时长 = 字数/语速
        local base=$(awk "BEGIN {printf \"%.2f\", $chars / $speed}")
        # 该段时长 = 基础时长 + 停顿（最后一段不加停顿）
        if [ $i -eq $((${#texts[@]} - 1)) ]; then
            durations+=("$base")
        else
            durations+=("$base + $PAUSE")
        fi
        calc_total=$(awk "BEGIN {print $calc_total + ${durations[-1]}}")
    done
    
    # 如果计算总时长不等于视频时长，按比例调整
    if [ $(awk "BEGIN {print $calc_total != $total_video}") -eq 1 ]; then
        local ratio=$(awk "BEGIN {print $total_video / $calc_total}")
        for i in "${!durations[@]}"; do
            durations[$i]=$(awk "BEGIN {printf \"%.2f\", ${durations[$i]} * $ratio}")
        done
    fi
    
    # 输出每段时长
    for d in "${durations[@]}"; do
        echo "$d"
    done
}

# 计算每段配音时长
DURATIONS=($(calculate_durations "$VIDEO_DURATION" "${TEXT_ARRAY[@]}"))

echo "  每段时长: ${DURATIONS[@]}"

# 配音和字幕保存目录（视频同目录）
AUDIO_DIR="$(dirname "$INPUT_VIDEO")/audio_$(basename "$INPUT_VIDEO" .mp4)"
mkdir -p "$AUDIO_DIR"
SUB_ASS="$(dirname "$INPUT_VIDEO")/$(basename "$INPUT_VIDEO" .mp4).ass"
SUB_ASS_SAVE="$SUB_ASS"

# 如果有克隆音频，先转换为wav格式（避免mp3等格式加载失败）
if [ -n "$PROMPT_WAV" ] && [ -f "$PROMPT_WAV" ]; then
    PROMPT_WAV_EXT="${PROMPT_WAV##*.}"
    if [ "$PROMPT_WAV_EXT" != "wav" ]; then
        # 转换后的wav保存到视频同目录，使用同名wav
        PROMPT_WAV_WAV="$(dirname "$INPUT_VIDEO")/$(basename "$PROMPT_WAV" .$PROMPT_WAV_EXT).wav"
        if [ ! -f "$PROMPT_WAV_WAV" ]; then
            ffmpeg -y -i "$PROMPT_WAV" -ar 16000 -ac 1 "$PROMPT_WAV_WAV" 2>/dev/null
            echo "  已转换克隆音频为wav格式: $PROMPT_WAV_WAV"
        else
            echo "  使用已转换的wav: $PROMPT_WAV_WAV"
        fi
        PROMPT_WAV="$PROMPT_WAV_WAV"
    fi
fi

# 激活 conda
source $HOME/anaconda3/bin/activate cosyvoice

echo ""
echo "[1/3] 生成配音..."

cd $HOME/CosyVoice

# 预加载模型（避免每段都重新加载）
echo "  加载模型..."

if [ -n "$PROMPT_WAV" ] && [ -f "$PROMPT_WAV" ]; then
    python3 << 'EOF_LOAD'
import sys
sys.path.append('/home/dministrator/CosyVoice/third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
cosyvoice = AutoModel(model_dir='/opt/image/Fun-CosyVoice3-0.5B', load_trt=False, fp16=False)
print("MODEL_LOADED")
EOF_LOAD
    
    for i in "${!TEXT_ARRAY[@]}"; do
        idx=$((i+1))
        text="${TEXT_ARRAY[$i]}"
        text=$(echo "$text" | xargs)
        
        # 检查缓存：如果配音文件已存在，跳过生成
        if [ -f "$AUDIO_DIR/$idx.wav" ]; then
            echo "  配音 $idx: [已缓存] $text"
            continue
        fi
        
        echo "  配音 $idx: $text"
        
        python3 << EOF
import sys
sys.path.append('$HOME/CosyVoice/third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio

cosyvoice = AutoModel(model_dir='/opt/image/Fun-CosyVoice3-0.5B', load_trt=True, fp16=True)
prompt = '<|endofprompt|>'
tts_text = '\n$text'

for j in cosyvoice.inference_instruct2(tts_text, prompt, '$PROMPT_WAV', stream=False):
    torchaudio.save('$AUDIO_DIR/$idx.wav', j['tts_speech'], cosyvoice.sample_rate)
    audio_len = j["tts_speech"].shape[1]/cosyvoice.sample_rate
    print(f'    长度: {audio_len:.2f}秒')
EOF
    done
else
    # 无克隆音频：使用CosyVoice-300M-SFT
    python3 << 'EOF_LOAD'
import sys
sys.path.append('/home/dministrator/CosyVoice/third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
cosyvoice = AutoModel(model_dir='/opt/image/CosyVoice-300M-SFT', load_trt=True, fp16=True)
print("MODEL_LOADED")
EOF_LOAD
    
    for i in "${!TEXT_ARRAY[@]}"; do
        idx=$((i+1))
        text="${TEXT_ARRAY[$i]}"
        text=$(echo "$text" | xargs)
        
        # 检查缓存：如果配音文件已存在，跳过生成
        if [ -f "$AUDIO_DIR/$idx.wav" ]; then
            echo "  配音 $idx: [已缓存] $text"
            continue
        fi
        
        echo "  配音 $idx: $text"
        
        python3 << EOF
import sys
sys.path.append('$HOME/CosyVoice/third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio

cosyvoice = AutoModel(model_dir='/opt/image/CosyVoice-300M-SFT', load_trt=True, fp16=True)

for j in cosyvoice.inference_sft('$text', 'neutral', stream=False):
    torchaudio.save('$AUDIO_DIR/$idx.wav', j['tts_speech'], cosyvoice.sample_rate)
    audio_len = j["tts_speech"].shape[1]/cosyvoice.sample_rate
    print(f'    长度: {audio_len:.2f}秒')
EOF
    done
fi

echo "  配音生成完成"

# 调整每段配音时长以匹配计算出的时长
echo ""
echo "  调整配音时长..."

for i in "${!DURATIONS[@]}"; do
    idx=$((i+1))
    target_duration="${DURATIONS[$i]}"
    
    if [ -f "$AUDIO_DIR/$idx.wav" ]; then
        # 获取原始时长
        orig_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_DIR/$idx.wav")
        
        # 计算需要调整的比例
        ratio=$(awk "BEGIN {printf \"%.2f\", $target_duration / $orig_duration}")
        
        # 使用atempo调整语速（范围0.5-2.0）
        if [ $(awk "BEGIN {print $ratio < 0.5}") -eq 1 ]; then
            ratio=0.5
        elif [ $(awk "BEGIN {print $ratio > 2.0}") -eq 1 ]; then
            ratio=2.0
        fi
        
        # 如果比例接近1，不需要调整
        if [ $(awk "BEGIN {print $ratio > 0.9 && $ratio < 1.1}") -eq 1 ]; then
            echo "    段$idx: 原时${orig_duration}秒 → 目标${target_duration}秒 (接近无需调整)"
        else
            # 两次atempo可以覆盖0.25-4倍范围
            if [ $(awk "BEGIN {print $ratio >= 1}") -eq 1 ]; then
                ffmpeg -y -i "$AUDIO_DIR/$idx.wav" -af "atempo=$ratio" -ar 16000 "$AUDIO_DIR/${idx}_adjusted.wav" 2>/dev/null
            else
                # 对于减速，先用一次atempo，再用一次
                sqrt_ratio=$(awk "BEGIN {printf \"%.2f\", sqrt($ratio)}")
                ffmpeg -y -i "$AUDIO_DIR/$idx.wav" -af "atempo=$sqrt_ratio,atempo=$sqrt_ratio" -ar 16000 "$AUDIO_DIR/${idx}_adjusted.wav" 2>/dev/null
            fi
            mv "$AUDIO_DIR/${idx}_adjusted.wav" "$AUDIO_DIR/$idx.wav"
            echo "    段$idx: 原时${orig_duration}秒 → 目标${target_duration}秒 (调整${ratio}x)"
        fi
    fi
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

# 提取视频分辨率宽度用于字幕换行
VIDEO_WIDTH=$(echo "$VIDEO_RES" | cut -d'x' -f1)

CURRENT_TIME=$INTRO_PAUSE

for i in "${!TEXT_ARRAY[@]}"; do
    idx=$((i+1))
    text="${TEXT_ARRAY[$i]}"
    text=$(echo "$text" | xargs)
    
    text=$(auto_wrap "$text" "$VIDEO_WIDTH")
    
    # 使用计算出的时长（已包含停顿）
    DURATION="${DURATIONS[$i]}"
    
    START_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int($CURRENT_TIME/60), $CURRENT_TIME%60}")
    END_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int(($CURRENT_TIME+$DURATION)/60), ($CURRENT_TIME+$DURATION)%60}")
    
    echo "Dialogue: 0,$START_TIME,$END_TIME,Default,,0,0,0,,$text" >> "$SUB_ASS"
    
    CURRENT_TIME=$(awk "BEGIN {print $CURRENT_TIME + $DURATION}")
done

echo "  字幕生成完成"

echo ""
echo "[3/3] 合成最终视频..."

# 合并配音（每段时长已在DURATIONS中包含停顿，直接拼接）
AUDIO_LIST="/tmp/audio_list_$$.txt"

for i in $(seq 1 $TOTAL_TEXTS); do
    echo "file '$AUDIO_DIR/$i.wav'" >> "$AUDIO_LIST"
done

COMBINED_AAC="/tmp/combined_$$.aac"
ffmpeg -y -f concat -safe 0 -i "$AUDIO_LIST" -c:a aac "$COMBINED_AAC" 2>/dev/null

# 合成最终视频：原视频画面 + 静音原音频 + 叠加新配音 + 字幕
ffmpeg -y -i "$INPUT_VIDEO" -i "$COMBINED_AAC" -vf "ass=$SUB_ASS" \
    -map 0:v -map 1:a \
    -c:v libx264 -c:a aac -shortest \
    "$OUTPUT" 2>/dev/null

# 清理临时文件（保留配音和字幕）
rm -rf "$AUDIO_LIST" "$COMBINED_AAC" "$PROMPT_WAV_WAV"

echo ""
echo "========================================"
echo "完成！输出: $OUTPUT"
echo "========================================"
