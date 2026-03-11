#!/usr/bin/env python3
# 配音批量生成 v3
# 特点：一次性生成所有文案配音，每段开头带静音，生成合并后的音频
#
# 参数说明:
#   $1 参考音频: 用于克隆声音的音频文件路径
#   $2 输出目录: 配音输出目录
#   $3+ 文案: 多段文案
#
# 示例:
#   python3 tts_batch_v3.py "/home/dministrator/CosyVoice/asset/zero_shot_prompt.wav" "/opt/image/audios" "文案1" "文案2" "文案3"

import sys
import os
import re

sys.path.insert(0, "/home/dministrator/CosyVoice")
sys.path.insert(0, "/home/dministrator/CosyVoice/third_party/Matcha-TTS")
from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio
import torch


def remove_punctuation(text):
    return re.sub(r"[^\w\s\u4e00-\u9fff]", "", text)


def main():
    prompt_wav = sys.argv[1]
    output_dir = sys.argv[2]
    texts = sys.argv[3:]

    texts = [remove_punctuation(t) for t in texts]

    os.chdir("/home/dministrator/CosyVoice")

    model_dir = "/opt/image/Fun-CosyVoice3-0.5B"
    print(f"加载模型: {model_dir}")
    cosyvoice = AutoModel(model_dir=model_dir)
    print("模型加载完成")

    instruct = "You are a helpful assistant. 请用讲故事的语气朗读。<|endofprompt|>"

    audio_segments = []
    sample_rate = cosyvoice.sample_rate

    for idx, text in enumerate(texts, 1):
        text = text.strip()
        if not text:
            continue

        output_path = f"{output_dir}/{idx}.wav"
        if os.path.exists(output_path):
            print(f"[缓存] {idx}: {text[:30]}...")
        else:
            print(f"[生成] {idx}: {text[:30]}...")
            for i, j in enumerate(
                cosyvoice.inference_instruct2(text, instruct, prompt_wav, stream=False)
            ):
                torchaudio.save(output_path, j["tts_speech"], sample_rate)
                duration = j["tts_speech"].shape[1] / sample_rate
                print(f"  长度: {duration:.2f}秒")
                audio_segments.append(j["tts_speech"])

    if audio_segments:
        pause_samples = int(0.3 * sample_rate)
        pause = torch.zeros((1, pause_samples))

        merged = audio_segments[0]
        for seg in audio_segments[1:]:
            merged = torch.cat([merged, pause, seg], dim=1)

        merged_path = f"{output_dir}/merged.wav"
        torchaudio.save(merged_path, merged, sample_rate)
        total_duration = merged.shape[1] / sample_rate
        print(f"合并完成: {merged_path}, 总时长: {total_duration:.2f}秒")

    # 保存每段时间信息
    timings = []
    current_time = 0

    for seg in audio_segments:
        start_time = current_time
        duration = seg.shape[1] / sample_rate
        end_time = current_time + duration
        timings.append((start_time, end_time, duration))
        current_time = end_time + 0.3  # 0.3秒停顿

    # 保存时间信息到文件
    timing_file = f"{output_dir}/timings.txt"
    with open(timing_file, "w") as f:
        for i, (start, end, dur) in enumerate(timings, 1):
            f.write(f"{i}: {start:.2f} {end:.2f} {dur:.2f}\n")
    print(f"时间信息已保存: {timing_file}")
    print("配音生成完成")


if __name__ == "__main__":
    main()
