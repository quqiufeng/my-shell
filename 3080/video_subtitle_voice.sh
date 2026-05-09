#!/bin/bash
# =============================================================================
# video_subtitle_voice.sh - 短视频配音字幕生成工具
# =============================================================================
#
# 【功能说明】
#   根据一个现有短视频 + 文案，自动生成带配音和字幕的新视频。
#   原视频保留，生成的新视频带配音和字幕。
#
# 【工作流程】
#   1. 获取短视频播放时长
#   2. 处理文案（支持文件或直接传入）
#      - 文案总长度可以比视频时长稍短（留出片头/片尾空白）
#      - 每段文案长度接近，均匀分布
#      - 文案有意义，不是纯字符堆砌
#   3. 克隆 voice.wav 的音色生成配音（支持声音克隆）
#   4. 字幕与配音精确同步（借鉴 v3 算法，从 timings.txt 读取精确时间）
#   5. 合成新视频：原视频画面 + 配音 + 字幕
#
# 【参数说明】
#   $1 视频文件    : 输入视频文件路径（必填）
#   $2 文案        : 字幕文案（必填）
#                      - 方式1：直接传入用 | 分隔的文案字符串
#                      - 方式2：传入文案文件路径（.txt），脚本自动读取
#   $3 参考音频    : 用于声音克隆的音频文件（可选，默认使用视频同目录下的 voice.wav）
#                      传 "none" 则使用默认 SFT 预设音色（中文女声）
#   $4 输出视频    : 输出文件路径（可选，默认在原视频同目录添加 _subtitled 后缀）
#
# 【示例】
#   # 方式1：直接传入文案字符串（推荐）
#   ./video_subtitle_voice.sh ~/video/orgin.mp4 '第一句|第二句|第三句'
#
#   # 方式2：传入文案文件
#   ./video_subtitle_voice.sh ~/video/orgin.mp4 ~/video/script.txt
#
#   # 指定参考音频
#   ./video_subtitle_voice.sh ~/video/orgin.mp4 '第一句|第二句' ~/video/voice.wav
#
#   # 使用默认 SFT 音色（不克隆）
#   ./video_subtitle_voice.sh ~/video/orgin.mp4 '第一句|第二句' none
#
#   # 指定输出路径
#   ./video_subtitle_voice.sh ~/video/orgin.mp4 '第一句|第二句' ~/video/voice.wav ~/output.mp4
#
# 【前提条件】
#   - 视频同目录下需有 voice.wav（克隆音色用，默认自动查找）
#   - 需先运行 build_cosy_voice_3080.sh 配置 CosyVoice 环境
#   - 依赖: ffmpeg, ffprobe, CosyVoice, Python3
#
# 【输出】
#   - 新视频: 原视频画面 + 配音 + 字幕
#   - 原视频: 保留不变
#   - 临时文件: 自动清理
#
# =============================================================================

set -euo pipefail

# ==================== 配置变量 ====================
# 段间停顿时间（秒），控制每段配音之间的静音时长
PAUSE=0.3

# 开头延迟时间（秒），视频开始时的静音时长
INTRO_PAUSE=0.3

# 字幕样式配置
SUBTITLE_STYLE="Default,Noto Sans CJK SC Bold,14,&H00FFFFFF,&H00FFFFFF,&H00FFA500,&H00666666,-1,0,0,0,100,100,0,0,1,2,0,2,10,10,20,1"
# ==================== 配置变量 ====================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

INPUT_VIDEO="$1"
SCRIPT_TEXT="$2"
PROMPT_WAV="${3:-}"
OUTPUT="${4:-}"

# =============================================================================
# 参数检查与初始化
# =============================================================================
if [ -z "$INPUT_VIDEO" ] || [ -z "$SCRIPT_TEXT" ]; then
    echo "用法: $0 <视频文件> <文案> [参考音频] [输出视频]"
    echo ""
    echo "参数说明:"
    echo "  视频文件    : 输入视频文件路径 (必填)"
    echo "  文案        : 字幕文案 (必填)"
    echo "                - 方式1：直接传入用 | 分隔的文案字符串"
    echo "                - 方式2：传入文案文件路径 (.txt)，脚本自动读取"
    echo "  参考音频    : 用于声音克隆的音频文件 (可选，默认使用视频同目录下的 voice.wav)"
    echo "                传 'none' 则使用默认 SFT 预设音色"
    echo "  输出视频    : 输出文件路径 (可选，默认在原视频同目录添加 _subtitled 后缀)"
    echo ""
    echo "示例:"
    echo "  $0 ~/video/orgin.mp4 '第一句|第二句|第三句'"
    echo "  $0 ~/video/orgin.mp4 ~/video/script.txt"
    echo "  $0 ~/video/orgin.mp4 '第一句|第二句' ~/video/voice.wav"
    echo "  $0 ~/video/orgin.mp4 '第一句|第二句' none"
    exit 1
fi

# 检查视频文件
if [ ! -f "$INPUT_VIDEO" ]; then
    echo "错误: 视频文件不存在: $INPUT_VIDEO"
    exit 1
fi

# 判断文案是文件还是字符串
if [ -f "$SCRIPT_TEXT" ]; then
    # 从文件读取文案
    echo "[INFO] 从文件读取文案: $SCRIPT_TEXT"
    TEXT=$(cat "$SCRIPT_TEXT" | tr '\n' '|' | sed 's/|$//')
else
    # 直接使用传入的文案字符串
    TEXT="$SCRIPT_TEXT"
fi

# 设置默认参考音频
if [ -z "$PROMPT_WAV" ]; then
    PROMPT_WAV="$(dirname "$INPUT_VIDEO")/voice.wav"
    echo "[INFO] 使用默认参考音频: $PROMPT_WAV"
fi

# 检查参考音频（如果不是 "none"）
if [ "$PROMPT_WAV" != "none" ] && [ ! -f "$PROMPT_WAV" ]; then
    echo "错误: 参考音频不存在: $PROMPT_WAV"
    echo "提示: 请提供参考音频文件，或传 'none' 使用默认 SFT 音色"
    exit 1
fi

# =============================================================================
# 步骤 0: 获取视频时长并解析文案
# =============================================================================
echo "========================================"
echo "视频配音字幕生成工具"
echo "========================================"

VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_VIDEO")
VIDEO_RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$INPUT_VIDEO")

echo "视频文件: $INPUT_VIDEO"
echo "视频时长: ${VIDEO_DURATION}秒"
echo "视频分辨率: $VIDEO_RES"

# 设置输出路径
if [ -z "$OUTPUT" ]; then
    input_dir=$(dirname "$INPUT_VIDEO")
    input_name=$(basename "$INPUT_VIDEO")
    input_ext="${input_name##*.}"
    input_name_noext="${input_name%.*}"
    OUTPUT="${input_dir}/${input_name_noext}_subtitled.${input_ext}"
fi

echo "输出文件: $OUTPUT"
echo "========================================"
echo ""

# 解析文案段数
echo "[步骤 1/5] 解析文案..."
IFS='|' read -ra TEXT_ARRAY <<< "$TEXT"
TOTAL_TEXTS=${#TEXT_ARRAY[@]}

# 过滤空文案段
VALID_TEXTS=()
for text in "${TEXT_ARRAY[@]}"; do
    text=$(echo "$text" | xargs)
    if [ -n "$text" ]; then
        VALID_TEXTS+=("$text")
    fi
done
TEXT_ARRAY=("${VALID_TEXTS[@]}")
TOTAL_TEXTS=${#TEXT_ARRAY[@]}

if [ "$TOTAL_TEXTS" -eq 0 ]; then
    echo "错误: 文案为空"
    exit 1
fi

echo "  文案段数: $TOTAL_TEXTS 段"
for i in "${!TEXT_ARRAY[@]}"; do
    idx=$((i+1))
    echo "  第 $idx 段: ${TEXT_ARRAY[$i]}"
done
echo ""

# 调试模式：只显示文案信息
if [ "${DEBUG:-}" = "1" ]; then
    echo "========================================"
    echo "调试模式：文案信息"
    echo "========================================"
    for i in "${!TEXT_ARRAY[@]}"; do
        idx=$((i+1))
        echo "  第 $idx 段: ${TEXT_ARRAY[$i]}"
    done
    exit 0
fi

# =============================================================================
# 步骤 2: 准备参考音频
# =============================================================================
echo "[步骤 2/5] 准备参考音频..."

# 创建临时工作目录
WORK_DIR=$(mktemp -d)
AUDIO_DIR="$WORK_DIR/audios"
mkdir -p "$AUDIO_DIR"

# 转换参考音频为 wav 格式（如果需要）
if [ "$PROMPT_WAV" != "none" ]; then
    PROMPT_WAV_EXT="${PROMPT_WAV##*.}"
    if [ "$PROMPT_WAV_EXT" != "wav" ]; then
        PROMPT_WAV_WAV="$WORK_DIR/voice.wav"
        ffmpeg -y -i "$PROMPT_WAV" -ar 16000 -ac 1 "$PROMPT_WAV_WAV" 2>/dev/null
        PROMPT_WAV="$PROMPT_WAV_WAV"
    fi
    echo "  使用克隆音色: $(basename "$PROMPT_WAV")"
else
    echo "  使用默认 SFT 音色（中文女声）"
fi
echo ""

# =============================================================================
# 步骤 3: 生成配音（借鉴 v3 算法，使用 tts_batch_v3.py）
# =============================================================================
echo "[步骤 3/5] 生成配音（使用 v3 同步算法）..."

cd ~/CosyVoice
source $HOME/anaconda3/bin/activate cosyvoice

# 使用 tts_batch_v3.py 一次性生成所有配音
# 特点：
#   - 模型只加载一次
#   - 自动在段间插入 0.3 秒停顿
#   - 生成 merged.wav（已含停顿的合并音频）
#   - 生成 timings.txt（精确时间信息）
python3 "$SCRIPT_DIR/tts_batch_v3.py" \
    "$PROMPT_WAV" \
    "$AUDIO_DIR" \
    "${TEXT_ARRAY[@]}"

# 检查输出文件
if [ ! -f "$AUDIO_DIR/merged.wav" ]; then
    echo "错误: 配音生成失败，未找到 merged.wav"
    exit 1
fi

if [ ! -f "$AUDIO_DIR/timings.txt" ]; then
    echo "错误: 时间信息文件不存在: $AUDIO_DIR/timings.txt"
    exit 1
fi

# 获取配音总时长
TTS_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_DIR/merged.wav")
echo "  配音总时长: ${TTS_DURATION}秒"
echo "  时间信息: $AUDIO_DIR/timings.txt"
echo ""

# =============================================================================
# 步骤 4: 生成字幕（从 timings.txt 读取精确时间）
# =============================================================================
echo "[步骤 4/5] 生成字幕（精确同步配音）..."

SUB_ASS="$WORK_DIR/subtitle.ass"

# 生成 ASS 字幕头
cat > "$SUB_ASS" << ASS_EOF
[Script Info]
Title: Generated Subtitle
ScriptType: v4.00+
WrapStyle: 1
ScaledBorderAndShadow: yes
YCbCr Matrix: None

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: $SUBTITLE_STYLE

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
ASS_EOF

# 自动换行函数
auto_wrap() {
    local text="$1"
    local max_len=13
    local len=${#text}
    
    if [ "$len" -le "$max_len" ]; then
        echo "$text"
        return
    fi
    
    local lines=$(( (len + max_len - 1) / max_len ))
    local result=""
    
    for i in $(seq 0 $((lines-1))); do
        local start=$((i * max_len))
        local end=$(((i + 1) * max_len))
        if [ "$end" -gt "$len" ]; then
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

# 从 timings.txt 读取精确时间并生成字幕
# 格式: idx: start end duration subtitle_start subtitle_end
mapfile -t timing_lines < <(grep -v "^#" "$AUDIO_DIR/timings.txt")

for line in "${timing_lines[@]}"; do
    [ -z "$line" ] && continue
    
    idx=$(echo "$line" | awk '{print $1}' | tr -d ':')
    subtitle_start=$(echo "$line" | awk '{print $5}')
    subtitle_end=$(echo "$line" | awk '{print $6}')
    
    text="${TEXT_ARRAY[$((idx-1))]}"
    text=$(echo "$text" | xargs)
    text=$(auto_wrap "$text")
    
    START_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int($subtitle_start/60), $subtitle_start%60}")
    END_TIME=$(awk "BEGIN {printf \"0:%02d:%05.2f\", int($subtitle_end/60), $subtitle_end%60}")
    
    echo "Dialogue: 0,$START_TIME,$END_TIME,Default,,0,0,0,,$text" >> "$SUB_ASS"
    echo "  字幕 $idx: $START_TIME -> $END_TIME"
done

echo "  字幕生成完成"
echo ""

# =============================================================================
# 步骤 5: 合成最终视频
# =============================================================================
echo "[步骤 5/5] 合成最终视频..."

# 将配音合并到视频中
# 策略：如果配音时长 < 视频时长，则保留完整视频（配音结束后视频继续播放）
#       如果配音时长 > 视频时长，则截断配音（使用 -shortest）
ffmpeg -y -i "$INPUT_VIDEO" -i "$AUDIO_DIR/merged.wav" -vf "ass=$SUB_ASS" -af "volume=1.5" \
    -map 0:v -map 1:a \
    -c:v libx264 -c:a aac \
    -shortest \
    "$OUTPUT" 2>/dev/null

# 清理临时文件
rm -rf "$WORK_DIR"

echo ""
echo "========================================"
echo "完成！"
echo "========================================"
echo "输入视频: $INPUT_VIDEO (保留)"
echo "输出视频: $OUTPUT"
echo "配音时长: ${TTS_DURATION}秒"
echo "视频时长: ${VIDEO_DURATION}秒"
echo "========================================"
