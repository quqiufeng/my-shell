#!/usr/bin/env python3
import sys
import torchaudio
import os
import os

sys.path.insert(0, os.path.expanduser("~/CosyVoice"))
sys.path.insert(0, os.path.expanduser("~/CosyVoice/third_party/Matcha-TTS"))
from cosyvoice.cli.cosyvoice import AutoModel


def main():
    model_dir = sys.argv[1]
    prompt_wav = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != "none" else None
    output_dir = sys.argv[3]
    speed = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
    texts = sys.argv[5:]

    print(f"加载模型: {model_dir}")
    cosyvoice = AutoModel(model_dir=model_dir, load_trt=True, fp16=True)
    print("模型加载完成")

    for idx, text in enumerate(texts, 1):
        text = text.strip()
        if not text:
            continue

        output_path = f"{output_dir}/{idx}.wav"
        if os.path.exists(output_path):
            print(f"[缓存] {idx}: {text[:30]}...")
            continue

        print(f"[生成] {idx}: {text[:30]}...")

        if prompt_wav and os.path.exists(prompt_wav):
            instruct = "You are a helpful assistant. 请用真诚推荐好物分享的语气说。<|endofprompt|>"
            tts_text = f"\n{text}"
            result = cosyvoice.inference_instruct2(
                tts_text, instruct, prompt_wav, stream=False, speed=speed
            )
        else:
            result = cosyvoice.inference_sft(text, "中文女", stream=False, speed=speed)

        for j in result:
            torchaudio.save(output_path, j["tts_speech"], cosyvoice.sample_rate)
            audio_len = j["tts_speech"].shape[1] / cosyvoice.sample_rate
            print(f"  长度: {audio_len:.2f}秒")


if __name__ == "__main__":
    main()
