#!/usr/bin/env python3
import sys
import os

sys.path.insert(0, "/home/dministrator/CosyVoice")
sys.path.insert(0, "/home/dministrator/CosyVoice/third_party/Matcha-TTS")
from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio


def main():
    prompt_wav = "./asset/zero_shot_prompt.wav"
    output_dir = sys.argv[1]
    texts = sys.argv[2:]

    model_dir = "/opt/image/Fun-CosyVoice3-0.5B"
    print(f"加载模型: {model_dir}")
    cosyvoice = AutoModel(model_dir=model_dir)
    print("模型加载完成")

    instruct = "You are a helpful assistant. 请用讲故事的语气朗读。<|endofprompt|>"

    for idx, text in enumerate(texts, 1):
        text = text.strip()
        if not text:
            continue

        output_path = f"{output_dir}/{idx}.wav"
        if os.path.exists(output_path):
            print(f"[缓存] {idx}: {text[:30]}...")
            continue

        print(f"[生成] {idx}: {text[:30]}...")

        for i, j in enumerate(
            cosyvoice.inference_instruct2(text, instruct, prompt_wav, stream=False)
        ):
            torchaudio.save(output_path, j["tts_speech"], cosyvoice.sample_rate)
            print(f"  长度: {j['tts_speech'].shape[1] / cosyvoice.sample_rate:.2f}秒")


if __name__ == "__main__":
    main()
