#!/usr/bin/env python3
import sys
import os

sys.path.insert(0, "/home/dministrator/CosyVoice")
sys.path.insert(0, "/home/dministrator/CosyVoice/third_party/Matcha-TTS")

from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio

if __name__ == "__main__":
    model_dir = "/opt/image"
    output_dir = sys.argv[1]
    texts = sys.argv[2:]

    print(f"加载模型: {model_dir}")
    cosyvoice = AutoModel(model_dir=model_dir, load_jit=True, load_trt=True, fp16=True)

    for i, text in enumerate(texts, 1):
        text = text.strip()
        if not text:
            continue

        print(f"  配音 {i}: {text}")

        for j in cosyvoice.inference_sft(text, "中文女", stream=False):
            torchaudio.save(
                f"{output_dir}/{i}.wav", j["tts_speech"], cosyvoice.sample_rate
            )
            print(f"    长度: {j['tts_speech'].shape[1] / cosyvoice.sample_rate:.2f}秒")
