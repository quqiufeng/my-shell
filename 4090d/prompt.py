#!/usr/bin/env python3
"""
视频字幕文案生成工具

用法:
    python3 prompt.py <视频文件> [文案文件]

示例:
    python3 prompt.py /opt/video/1.mp4 /opt/video/info.txt
"""

import os
import sys
import requests
import subprocess
from pathlib import Path

MINIMAX_API_KEY = ""

env_file = Path(__file__).parent.parent / ".env"
if env_file.exists():
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and "=" in line and not line.startswith("#"):
                key, value = line.split("=", 1)
                if key == "MINIMAX_API_KEY":
                    MINIMAX_API_KEY = value

BASE_URL = "https://api.minimaxi.com/v1/chat/completions"


def call_minimax(prompt: str) -> str:
    headers = {
        "Authorization": f"Bearer {MINIMAX_API_KEY}",
        "Content-Type": "application/json",
    }

    payload = {
        "model": "MiniMax-M2.5",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 8192,
        "temperature": 0.7,
    }

    response = requests.post(BASE_URL, headers=headers, json=payload, timeout=180)
    result = response.json()
    return result["choices"][0]["message"]["content"]


def get_video_duration(video_path: str) -> float:
    """获取视频时长（秒）"""
    cmd = ["ffprobe", "-v", "error", "-show_entries", "format=duration", 
           "-of", "default=noprint_wrappers=1:nokey=1", video_path]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return float(result.stdout.strip())


def calculate_char_count(video_duration: float, speed: float = 3.1, 
                         intro_pause: float = 0.2, segment_pause: float = 0.3,
                         segment_count: int = None, adjust: int = 10) -> int:
    """
    根据视频时长计算预估字幕汉字总数量
    
    参数:
        video_duration: 视频时长（秒）
        speed: 语速（字/秒），默认4.0
        intro_pause: 开头停顿（秒），默认0.2
        segment_pause: 每段间停顿（秒），默认0.3
        segment_count: 文案段数，如果为None则自动估算
    
    返回:
        预估汉字总数量
    """
    # 开头停顿时间
    total_pause = intro_pause
    
    # 如果没有指定段数，根据视频时长估算（大约每8-10秒一段）
    if segment_count is None:
        segment_count = max(5, int(video_duration / 8))
    
    # 段间停顿时间
    total_pause += (segment_count - 1) * segment_pause
    
    # 可用时间 = 视频时长 - 停顿时间
    available_time = video_duration - total_pause
    
    if available_time <= 0:
        available_time = video_duration * 0.8  # 保守估计80%时间
    
    # 总汉字数 = 可用时间 * 语速 - 调整值
    total_chars = int(available_time * speed) - adjust
    
    if total_chars < 10:
        total_chars = 10
    
    return total_chars


def generate_subtitle(video_path: str, info_file: str = None, adjust: int = 10, speed: float = 3.1, total_chars: int = None) -> str:
    """生成字幕文案
    参数:
        video_path: 视频文件路径
        info_file: 文案文件路径
        adjust: 调整值，默认10，用于微调预估汉字数
        speed: 语速，默认3.1字/秒
        total_chars: 预估汉字总数，如果为None则自动计算
    """
    # 获取视频时长
    duration = get_video_duration(video_path)
    
    # 预估字幕汉字总数
    if total_chars is None:
        total_chars = calculate_char_count(duration, speed=speed, adjust=adjust)
    
    if info_file is None:
        info_file = "/opt/video/info.txt"
    
    with open(info_file, "r", encoding="utf-8") as f:
        content = f.read()

    prompt = f"""根据以下产品介绍生成字幕文案，要求：
1. 每段约20汉字，用|分隔
2. 约{total_chars}字
3. 语气：真诚推荐好物分享

示例格式：
百年纯正低频音响界的活化石大品牌|横跨五大领域包括大部分影院还有体育场馆|它真正了定义扩声系统监听扬声器金标准|被哈曼卡顿集团收购的超强美式低音品牌|特别是弹性下潜深度高动态适合流行坚韧耐用|适合喜欢超强重低音的爱好者体验|想要的来我直播间

产品介绍内容：
{content[:500]}"""
    result = call_minimax(prompt)

    result = result.strip()
    if result.startswith("```"):
        result = result.split("```")[1]
        if result.startswith("json") or result.startswith("文案"):
            result = result.split("\n", 1)[1]
        if result.endswith("```"):
            result = result.rsplit("```", 1)[0]
    return result.strip()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python3 prompt.py <视频文件> [文案文件]", file=sys.stderr)
        print("")
        print("示例:")
        print("  python3 prompt.py /opt/video/1.mp4 /opt/video/info.txt")
        sys.exit(1)

    video_file = sys.argv[1]
    info_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    if not os.path.exists(video_file):
        print(f"错误: 视频文件不存在: {video_file}", file=sys.stderr)
        sys.exit(1)
    
    if info_file and not os.path.exists(info_file):
        print(f"错误: 文案文件不存在: {info_file}", file=sys.stderr)
        sys.exit(1)
    
    # 显示视频信息
    duration = get_video_duration(video_file)
    adjust = 0  # 默认调整值0
    est_chars = calculate_char_count(duration, speed=3.1, adjust=adjust)
    print(f"视频时长: {duration:.1f}秒", file=sys.stderr)
    print(f"预估汉字: {est_chars}字 (调整值: {adjust})", file=sys.stderr)
    print("-" * 30, file=sys.stderr)
    
    result = generate_subtitle(video_file, info_file, adjust=adjust)
    print(result)
