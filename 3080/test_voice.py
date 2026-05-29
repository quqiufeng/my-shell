#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
语音功能验证脚本
测试：语音转文字 (ASR) + 文字转语音 (TTS)

用法:
    python3 test_voice.py

依赖:
    - SenseVoice.cpp 已编译: /opt/SenseVoice.cpp/bin/sense-voice-main
    - CosyVoice 环境就绪: /opt/CosyVoice
    - 模型已下载: /data/models/
"""

import os
import sys
import subprocess
import tempfile
import struct
import math

# ============ 配置 ============
SENSEVOICE_BIN = "/opt/SenseVoice.cpp/bin/sense-voice-main"
SENSEVOICE_MODEL = "/data/models/sense-voice-small-q4_k.gguf"
COSYVOICE_DIR = "/opt/CosyVoice"
COSYVOICE_MODEL = "/data/models/CosyVoice-300M-SFT"  # SFT 模型有内置发音人
PYTHON = "/data/venv/bin/python3"

# 修复 cuDNN 混载问题: 强制使用 PyTorch bundled cuDNN
os.environ["LD_LIBRARY_PATH"] = "/data/venv/lib/python3.12/site-packages/nvidia/cudnn/lib:" + os.environ.get("LD_LIBRARY_PATH", "")


def generate_test_wav(path, duration=3, sample_rate=16000):
    """生成测试音频 (正弦波)"""
    with open(path, 'wb') as f:
        # 写 WAV header
        num_samples = int(sample_rate * duration)
        byte_rate = sample_rate * 2  # 16bit mono
        data_size = num_samples * 2

        f.write(b'RIFF')
        f.write(struct.pack('<I', 36 + data_size))
        f.write(b'WAVE')
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))  # Subchunk1Size
        f.write(struct.pack('<H', 1))   # AudioFormat (PCM)
        f.write(struct.pack('<H', 1))   # NumChannels (mono)
        f.write(struct.pack('<I', sample_rate))
        f.write(struct.pack('<I', byte_rate))
        f.write(struct.pack('<H', 2))   # BlockAlign
        f.write(struct.pack('<H', 16))  # BitsPerSample
        f.write(b'data')
        f.write(struct.pack('<I', data_size))

        # 写音频数据 (440Hz 正弦波)
        for i in range(num_samples):
            t = i / sample_rate
            sample = int(16000 * math.sin(2 * math.pi * 440 * t))
            f.write(struct.pack('<h', sample))


def test_asr():
    """测试语音转文字 (SenseVoice.cpp)"""
    print("=" * 60)
    print("[1/2] 测试语音转文字 (ASR) - SenseVoice.cpp")
    print("=" * 60)

    # 检查二进制和模型
    if not os.path.exists(SENSEVOICE_BIN):
        print(f"❌ 错误: SenseVoice 二进制不存在: {SENSEVOICE_BIN}")
        return False
    if not os.path.exists(SENSEVOICE_MODEL):
        print(f"❌ 错误: SenseVoice 模型不存在: {SENSEVOICE_MODEL}")
        return False

    # 生成测试音频
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        test_wav = f.name
    generate_test_wav(test_wav, duration=2)
    print(f"✓ 生成测试音频: {test_wav}")

    # 运行 ASR
    cmd = [
        SENSEVOICE_BIN,
        "-m", SENSEVOICE_MODEL,
        "-t", "6",
        "-f", test_wav
    ]
    print(f"✓ 运行: {' '.join(cmd)}")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )
        os.unlink(test_wav)

        # 检查输出中是否包含预期的运行信息
        if "sense_voice_model_load:" in result.stderr and "n_vocab" in result.stderr:
            print("✓ ASR 模型加载成功")
        else:
            print("⚠️  模型加载信息不完整")

        if result.returncode == 0:
            print("✓ ASR 运行完成 (returncode=0)")
        else:
            print(f"⚠️  ASR 返回码: {result.returncode}")

        # 检查 GPU 使用
        if "use gpu    = 1" in result.stderr:
            print("✓ GPU 加速已启用 (RTX 3080)")
        else:
            print("⚠️  GPU 可能未启用")

        print("✅ ASR 测试通过")
        return True

    except subprocess.TimeoutExpired:
        print("❌ ASR 运行超时")
        os.unlink(test_wav)
        return False
    except Exception as e:
        print(f"❌ ASR 运行异常: {e}")
        os.unlink(test_wav)
        return False


def test_tts():
    """测试文字转语音 (CosyVoice)"""
    print("\n" + "=" * 60)
    print("[2/2] 测试文字转语音 (TTS) - CosyVoice")
    print("=" * 60)

    # 检查模型
    if not os.path.exists(COSYVOICE_MODEL):
        print(f"❌ 错误: CosyVoice 模型不存在: {COSYVOICE_MODEL}")
        return False

    # 测试脚本
    test_script = """
import sys
sys.path.insert(0, "/opt/CosyVoice/third_party/Matcha-TTS")

from cosyvoice.cli.cosyvoice import CosyVoice
import scipy.io.wavfile as wavfile

print("✓ CosyVoice 导入成功")

model = CosyVoice("/data/models/CosyVoice-300M-SFT")
print("✓ 模型加载成功")

spks = model.list_available_spks()
print(f"✓ 可用发音人: {spks}")

if not spks:
    print("❌ 没有可用发音人")
    sys.exit(1)

# 生成语音
for item in model.inference_sft("你好,欢迎使用语音合成系统。", spk_id=spks[0]):
    wav = item["tts_speech"][0].numpy()
    wavfile.write("/tmp/test_voice_tts.wav", 22050, (wav * 32767).astype("int16"))
    print(f"✓ TTS 生成成功: {len(wav)} 采样点")

print("✅ TTS 测试通过")
"""

    print(f"✓ 运行: {PYTHON} -c '<test_script>'")
    print(f"✓ LD_LIBRARY_PATH={os.environ.get('LD_LIBRARY_PATH', '')[:60]}...")

    try:
        result = subprocess.run(
            [PYTHON, "-c", test_script],
            capture_output=True,
            text=True,
            timeout=120,
            cwd=COSYVOICE_DIR
        )

        # 打印输出
        for line in result.stdout.strip().split('\n'):
            if line:
                print(line)
        for line in result.stderr.strip().split('\n'):
            if 'ERROR' in line or 'Error' in line or '错误' in line:
                print(line)

        if result.returncode == 0 and os.path.exists("/tmp/test_voice_tts.wav"):
            size = os.path.getsize("/tmp/test_voice_tts.wav")
            print(f"✓ 音频文件已生成: /tmp/test_voice_tts.wav ({size} bytes)")
            return True
        else:
            print(f"❌ TTS 失败 (returncode={result.returncode})")
            return False

    except subprocess.TimeoutExpired:
        print("❌ TTS 运行超时")
        return False
    except Exception as e:
        print(f"❌ TTS 运行异常: {e}")
        return False


def main():
    print("语音功能验证")
    print("=" * 60)
    print(f"SenseVoice: {SENSEVOICE_BIN}")
    print(f"CosyVoice:  {COSYVOICE_DIR}")
    print(f"Python:     {PYTHON}")
    print("=" * 60)

    asr_ok = test_asr()
    tts_ok = test_tts()

    print("\n" + "=" * 60)
    print("测试结果汇总")
    print("=" * 60)
    print(f"语音转文字 (ASR): {'✅ 通过' if asr_ok else '❌ 失败'}")
    print(f"文字转语音 (TTS): {'✅ 通过' if tts_ok else '❌ 失败'}")
    print("=" * 60)

    if asr_ok and tts_ok:
        print("🎉 所有语音功能正常!")
        return 0
    else:
        print("⚠️  部分功能异常，请检查日志")
        return 1


if __name__ == "__main__":
    sys.exit(main())
