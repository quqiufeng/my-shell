#!/usr/bin/env python3
"""
视频字幕文案生成工具 - 调用本地 Qwen 模型

用法:
    python3 generate_script.py <视频文件> <素材文件>

示例:
    python3 generate_script.py ~/video/orgin.mp4 ~/video/info.txt
    python3 generate_script.py ~/video/orgin.mp4 ~/video/info.txt --output ~/video/script.txt

依赖:
    - ffmpeg (ffprobe)
    - 本地 llama.cpp 服务运行在 localhost:11434

启动 llama.cpp 服务:
    cd ~/my-shell/3080 && ./run_qwen3.5-9b_llama.sh
"""

import sys
import os
import subprocess
import requests
import re

API_URL = "http://localhost:11434/v1/chat/completions"
MODEL_NAME = "Qwopus3.5-9B-v3.Q5_K_S.gguf"


def get_video_duration(video_path: str) -> float:
    """获取视频时长（秒）"""
    cmd = [
        "ffprobe", "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        video_path
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return float(result.stdout.strip())


def check_api() -> bool:
    """检查本地 API 是否可用"""
    try:
        r = requests.get("http://localhost:11434/v1/models", timeout=5)
        return r.status_code == 200
    except:
        return False


def call_qwen(prompt: str, max_tokens: int = 3000) -> str:
    """调用本地 Qwen 模型（支持 reasoning 模型）"""
    payload = {
        "model": MODEL_NAME,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.3,
    }

    try:
        r = requests.post(API_URL, json=payload, timeout=120)
        result = r.json()
        msg = result["choices"][0]["message"]
        content = msg.get("content", "")

        # 推理模型可能把输出放在 reasoning_content 中
        if not content.strip():
            reasoning = msg.get("reasoning_content", "")
            if reasoning:
                content = extract_from_reasoning(reasoning)

        return content
    except Exception as e:
        print(f"错误: API 调用失败 - {e}")
        sys.exit(1)


def extract_from_reasoning(reasoning: str) -> str:
    """从 reasoning_content 中提取最终文案输出"""
    lines = reasoning.split('\n')
    
    # 提取所有包含中文的候选行，去掉英文前缀
    candidates = []
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
        
        # 去掉常见的英文前缀
        line = re.sub(r'^[\s*\-]+\s*(Draft|Revision|Revised|Let\'s try|Let\'s|Okay|Or|Add|Try|Check|Wait|Actually|Maybe|Perhaps|Instead|Alternative|Example|Sample|Test|Note|Count|Char|Segment|Final|Version|Adjust|Short|Long|Trim|Remove|Method|Approach|Option|Choice|Result|Output|Constraint|Requirement|Format|Rule|Instruction|Prompt|Task|Model|Process|Think|Thinking|Analyse|Analyze|Review|Summary|Content)\s*[:：]\s*', '', line, flags=re.IGNORECASE)
        line = line.strip()
        
        # 过滤掉纯英文行
        chinese_chars = sum(1 for c in line if '\u4e00' <= c <= '\u9fff')
        if chinese_chars < 5:
            continue
        
        # 过滤掉包含大量英文的行（中文字符占比要超过50%）
        total_chars = len([c for c in line if c.isalpha()])
        if total_chars > 0 and chinese_chars / total_chars < 0.5:
            continue
        
        candidates.append(line)
    
    if not candidates:
        return ""
    
    # 清理每个候选：去掉英文、数字、标点，保留中文和|
    cleaned = []
    for line in candidates:
        # 去掉英文字母和数字
        line = re.sub(r'[a-zA-Z0-9]', '', line)
        # 去掉标点符号（保留|）
        line = re.sub(r'[^\u4e00-\u9fff\|]', '', line)
        line = line.strip()
        if line and len(line) >= 5:
            cleaned.append(line)
    
    if not cleaned:
        return ""
    
    # 去重：去掉相似的段落
    unique = []
    for line in cleaned:
        is_dup = False
        for existing in unique:
            # 如果相似度超过80%，认为是重复
            if len(line) > 5 and len(existing) > 5:
                common = sum(1 for a, b in zip(line, existing) if a == b)
                if common / max(len(line), len(existing)) > 0.7:
                    is_dup = True
                    break
        if not is_dup:
            unique.append(line)
    
    # 如果段落中有 |，说明模型已经格式化好了
    for line in unique:
        if '|' in line:
            return line
    
    # 否则取最后6个不重复的段落，用|连接
    if len(unique) >= 3:
        return '|'.join(unique[-6:])
    
    return '|'.join(unique)


def calculate_segments(duration: float) -> tuple:
    """根据视频时长计算文案参数"""
    speed = 3.1  # 语速：字/秒
    pause = 0.3  # 段间停顿
    
    # 估算段数（每段约 8-10 秒）
    segment_count = max(5, int(duration / 9))
    
    # 总停顿时间
    total_pause = (segment_count - 1) * pause
    
    # 可用时间
    available_time = duration - total_pause
    
    # 总字数
    total_chars = int(available_time * speed)
    
    # 每段字数
    chars_per_segment = total_chars // segment_count
    
    return segment_count, total_chars, chars_per_segment


def generate_prompt(info_content: str, segment_count: int, total_chars: int, chars_per_seg: int) -> str:
    """构建生成文案的 prompt"""
    return f"""根据以下产品介绍，生成{segment_count}段短视频字幕文案，用|分隔，每段约{chars_per_seg}汉字。

{info_content[:400]}

注意：
- 只输出文案，不要解释
- 不要标点符号
- 不要英文字母和数字
- 顺序：品牌介绍→核心卖点→功能特点→行动号召"""


def clean_script(text: str) -> str:
    """清理生成的文案"""
    # 去除 markdown 代码块
    text = re.sub(r'```[\w\s]*\n?', '', text)
    text = re.sub(r'```', '', text)
    
    # 去除 think 标签
    text = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL)
    
    # 去除多余空白
    text = text.strip()
    
    # 确保用 | 分隔
    if '|' not in text:
        # 尝试按换行分隔
        lines = [l.strip() for l in text.split('\n') if l.strip()]
        text = '|'.join(lines)
    
    # 去除标点符号（保留 |）
    text = re.sub(r'[^\u4e00-\u9fff\|]', '', text)
    
    # 确保 | 前后没有多余空格
    segments = [s.strip() for s in text.split('|') if s.strip()]
    
    # 过滤太短的段（少于10个字）
    segments = [s for s in segments if len(s) >= 10]
    
    # 去重：去掉相似的段落
    unique = []
    for seg in segments:
        is_dup = False
        for existing in unique:
            # 如果相似度超过70%，认为是重复
            if len(seg) > 5 and len(existing) > 5:
                common = sum(1 for a, b in zip(seg, existing) if a == b)
                if common / max(len(seg), len(existing)) > 0.7:
                    is_dup = True
                    break
        if not is_dup:
            unique.append(seg)
    
    return '|'.join(unique)


def validate_script(text: str) -> tuple:
    """验证文案质量"""
    segments = text.split('|')
    issues = []
    
    for i, seg in enumerate(segments):
        # 检查长度
        char_count = sum(1 for c in seg if '\u4e00' <= c <= '\u9fff')
        if char_count < 10:
            issues.append(f"第{i+1}段太短({char_count}字): {seg[:20]}")
        if char_count > 40:
            issues.append(f"第{i+1}段太长({char_count}字): {seg[:20]}")
    
    return len(issues) == 0, issues


def main():
    if len(sys.argv) < 3:
        print("用法: python3 generate_script.py <视频文件> <素材文件> [--output 输出文件]")
        print("")
        print("示例:")
        print("  python3 generate_script.py ~/video/orgin.mp4 ~/video/info.txt")
        print("  python3 generate_script.py ~/video/orgin.mp4 ~/video/info.txt --output ~/video/script.txt")
        sys.exit(1)
    
    video_path = sys.argv[1]
    info_path = sys.argv[2]
    output_path = None
    
    # 解析 --output 参数
    if "--output" in sys.argv:
        idx = sys.argv.index("--output")
        if idx + 1 < len(sys.argv):
            output_path = sys.argv[idx + 1]
    
    # 检查文件
    if not os.path.exists(video_path):
        print(f"错误: 视频文件不存在: {video_path}")
        sys.exit(1)
    
    if not os.path.exists(info_path):
        print(f"错误: 素材文件不存在: {info_path}")
        sys.exit(1)
    
    # 检查 API
    print("检查本地 Qwen 模型服务...")
    if not check_api():
        print("错误: 本地 API 未启动 (localhost:11434)")
        print("请先启动 llama.cpp 服务:")
        print("  cd ~/my-shell/3080 && ./run_qwen3.5-9b_llama.sh")
        sys.exit(1)
    print("  API 连接正常")
    
    # 获取视频时长
    duration = get_video_duration(video_path)
    print(f"\n视频时长: {duration:.1f}秒")
    
    # 读取素材
    with open(info_path, 'r', encoding='utf-8') as f:
        info_content = f.read()
    
    # 计算文案参数
    seg_count, total_chars, chars_per_seg = calculate_segments(duration)
    print(f"建议段数: {seg_count}段")
    print(f"总字数: ~{total_chars}字")
    print(f"每段字数: ~{chars_per_seg}字")
    
    # 生成文案
    print("\n正在生成文案...")
    prompt = generate_prompt(info_content, seg_count, total_chars, chars_per_seg)
    result = call_qwen(prompt)
    
    # 清理文案
    script = clean_script(result)
    
    # 验证
    is_valid, issues = validate_script(script)
    if not is_valid:
        print("\n警告: 文案存在以下问题:")
        for issue in issues:
            print(f"  - {issue}")
    
    # 输出结果
    print("\n" + "="*50)
    print("生成的字幕文案")
    print("="*50)
    print(script)
    print("="*50)
    
    # 统计
    segments = script.split('|')
    print(f"\n统计:")
    print(f"  总段数: {len(segments)}段")
    print(f"  总字数: {sum(len(s) for s in segments)}字")
    for i, seg in enumerate(segments):
        print(f"  第{i+1}段 ({len(seg)}字): {seg}")
    
    # 保存到文件
    if output_path:
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(script)
        print(f"\n文案已保存到: {output_path}")
    
    print("\n使用方式:")
    print(f"  ./video_subtitle_voice.sh {video_path} '{script}'")


if __name__ == "__main__":
    main()
