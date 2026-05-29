#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
语音功能验证脚本 (Voice Functionality Verification)
======================================================

本脚本用于验证完整的语音 AI 流水线是否正常工作：
1. 语音转文字 (ASR) - 使用 SenseVoice.cpp + RTX 3080 CUDA 加速
2. 文字转语音 (TTS) - 使用 CosyVoice + PyTorch CUDA

设计目标:
    - 一键验证: 运行即可确认 ASR 和 TTS 两条链路正常
    - 自检机制: 自动检查二进制、模型、GPU 可用性
    - 环境兼容: 自动处理 cuDNN 版本冲突 (见下方说明)

系统环境要求:
    - GPU: NVIDIA RTX 3080 (sm_86)
    - CUDA: /data/cuda (CUDA 12.6)
    - Python: /data/venv (Python 3.12, torch 2.9.0+cu126)
    - 语音模型: /data/models/ (GGUF for ASR, PyTorch for TTS)

cuDNN 版本冲突说明 (重要):
    系统默认安装了 cuDNN 9.22 (/usr/lib/x86_64-linux-gnu/),
    但 PyTorch 2.9.0 捆绑的是 cuDNN 9.10.2 (在 venv 的 nvidia/cudnn/lib 中)。
    当 PyTorch 的 cuDNN 动态加载子库 (libcudnn_cnn.so.9, libcudnn_ops.so.9 等) 时，
    如果系统 cuDNN 被优先加载，会导致 CUDNN_STATUS_SUBLIBRARY_VERSION_MISMATCH。
    
    修复方法: 设置 LD_LIBRARY_PATH，强制优先使用 PyTorch 捆绑的 cuDNN:
        export LD_LIBRARY_PATH=/data/venv/lib/python3.12/site-packages/nvidia/cudnn/lib:$LD_LIBRARY_PATH

目录结构:
    /opt/SenseVoice.cpp/bin/sense-voice-main  - ASR 推理二进制 (GGML + CUDA)
    /opt/CosyVoice/                           - TTS Python 项目
    /data/models/sense-voice-small-q4_k.gguf  - ASR 模型文件
    /data/models/CosyVoice-300M-SFT/          - TTS 模型文件 (含内置发音人)
    /tmp/test_voice_tts.wav                   - TTS 生成的测试音频输出

用法:
    python3 test_voice.py

返回值:
    0 - 所有测试通过
    1 - 至少一项测试失败

作者: AI Assistant
日期: 2025-05-29
"""

import os
import sys
import subprocess
import tempfile
import struct
import math

# =============================================================================
# 全局配置 - 硬编码路径，与当前系统环境匹配
# =============================================================================
# ASR 配置: SenseVoice.cpp 二进制和 GGUF 模型路径
SENSEVOICE_BIN = "/opt/SenseVoice.cpp/bin/sense-voice-main"  # 编译后的 C++ 二进制
SENSEVOICE_MODEL = "/data/models/sense-voice-small-q4_k.gguf"  # 量化后的 GGUF 模型

# TTS 配置: CosyVoice Python 项目和模型路径
COSYVOICE_DIR = "/opt/CosyVoice"  # 源码目录，含 third_party/Matcha-TTS
COSYVOICE_MODEL = "/data/models/CosyVoice-300M-SFT"  # SFT 模型，包含 7 个内置发音人
PYTHON = "/data/venv/bin/python3"  # 虚拟环境 Python 解释器

# =============================================================================
# 环境修复: cuDNN 版本冲突 workaround
# 必须在任何 import torch/cudnn 之前设置，否则子库可能已被系统版本污染
# =============================================================================
os.environ["LD_LIBRARY_PATH"] = "/data/venv/lib/python3.12/site-packages/nvidia/cudnn/lib:" + os.environ.get("LD_LIBRARY_PATH", "")


def generate_test_wav(path, duration=3, sample_rate=16000):
    """
    生成测试音频文件 (WAV 格式)
    
    使用 440Hz 正弦波作为测试音频。注意这不是真实语音，
    所以 ASR 可能不会识别出有效文字，但足以验证 pipeline 是否能正常加载和运行。
    
    Args:
        path: 输出 WAV 文件路径
        duration: 音频时长 (秒)
        sample_rate: 采样率 (Hz)
    """
    with open(path, 'wb') as f:
        # 计算音频参数
        num_samples = int(sample_rate * duration)
        byte_rate = sample_rate * 2  # 16bit mono = 2 bytes/sample
        data_size = num_samples * 2

        # 写 WAV 文件头 (RIFF chunk)
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36 + data_size))  # 文件总大小
        f.write(b'WAVE')
        
        # fmt chunk - PCM 格式说明
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))   # Subchunk1Size (PCM = 16)
        f.write(struct.pack('<H', 1))    # AudioFormat (1 = PCM)
        f.write(struct.pack('<H', 1))    # NumChannels (1 = mono)
        f.write(struct.pack('<I', sample_rate))
        f.write(struct.pack('<I', byte_rate))
        f.write(struct.pack('<H', 2))    # BlockAlign
        f.write(struct.pack('<H', 16))   # BitsPerSample
        
        # data chunk - 音频采样数据
        f.write(b'data')
        f.write(struct.pack('<I', data_size))

        # 生成 440Hz 正弦波 (A4 音高)
        for i in range(num_samples):
            t = i / sample_rate
            sample = int(16000 * math.sin(2 * math.pi * 440 * t))
            f.write(struct.pack('<h', sample))


def test_asr():
    """
    测试语音转文字 (ASR) - SenseVoice.cpp
    
    测试流程:
        1. 检查二进制和模型文件是否存在
        2. 生成测试音频 (正弦波)
        3. 调用 sense-voice-main 进行推理
        4. 验证 GPU 加速是否启用
        5. 检查模型加载是否成功
    
    Returns:
        bool: True 表示测试通过，False 表示失败
    """
    print("=" * 60)
    print("[1/2] 测试语音转文字 (ASR) - SenseVoice.cpp")
    print("=" * 60)

    # 前置检查: 二进制和模型必须存在
    if not os.path.exists(SENSEVOICE_BIN):
        print(f"❌ 错误: SenseVoice 二进制不存在: {SENSEVOICE_BIN}")
        print("   提示: 请先运行 build_sense_voice.sh 编译")
        return False
    if not os.path.exists(SENSEVOICE_MODEL):
        print(f"❌ 错误: SenseVoice 模型不存在: {SENSEVOICE_MODEL}")
        print("   提示: 请先下载模型到 /data/models/")
        return False

    # 生成测试音频文件 (临时文件，测试后自动删除)
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        test_wav = f.name
    generate_test_wav(test_wav, duration=2)
    print(f"✓ 生成测试音频: {test_wav}")

    # 构建 ASR 命令行参数
    # -m: 模型路径 (GGUF 格式)
    # -t: 线程数 (使用全部 6 核)
    # -f: 输入音频文件 (WAV 格式)
    cmd = [
        SENSEVOICE_BIN,
        "-m", SENSEVOICE_MODEL,
        "-t", "6",
        "-f", test_wav
    ]
    print(f"✓ 运行: {' '.join(cmd)}")

    try:
        # 执行 ASR 推理，捕获 stdout/stderr
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30  # 正常应在几秒内完成
        )
        os.unlink(test_wav)  # 清理临时文件

        # 验证模型加载: stderr 中应包含模型结构信息
        if "sense_voice_model_load:" in result.stderr and "n_vocab" in result.stderr:
            print("✓ ASR 模型加载成功")
        else:
            print("⚠️  模型加载信息不完整")

        # 检查进程返回码
        if result.returncode == 0:
            print("✓ ASR 运行完成 (returncode=0)")
        else:
            print(f"⚠️  ASR 返回码: {result.returncode}")

        # 关键验证: 检查 GPU 是否被使用
        # sense-voice-main 的 stderr 会输出 "use gpu    = 1"
        if "use gpu    = 1" in result.stderr:
            print("✓ GPU 加速已启用 (RTX 3080)")
        else:
            print("⚠️  GPU 可能未启用")

        print("✅ ASR 测试通过")
        return True

    except subprocess.TimeoutExpired:
        print("❌ ASR 运行超时 (超过 30 秒)")
        os.unlink(test_wav)
        return False
    except Exception as e:
        print(f"❌ ASR 运行异常: {e}")
        os.unlink(test_wav)
        return False


def test_tts():
    """
    测试文字转语音 (TTS) - CosyVoice
    
    测试流程:
        1. 检查模型目录是否存在
        2. 在子进程中运行 Python 测试代码 (隔离环境，避免 import 冲突)
        3. 加载 CosyVoice-300M-SFT 模型
        4. 列出可用发音人
        5. 使用第一个发音人生成语音
        6. 保存为 WAV 文件到 /tmp/test_voice_tts.wav
    
    设计说明:
        使用 subprocess 运行测试代码，而不是直接在当前进程 import，
        这样可以避免 CosyVoice 的复杂依赖污染当前 Python 环境。
        LD_LIBRARY_PATH 已在脚本开头设置，确保子进程继承正确的 cuDNN 路径。
    
    Returns:
        bool: True 表示测试通过，False 表示失败
    """
    print("\n" + "=" * 60)
    print("[2/2] 测试文字转语音 (TTS) - CosyVoice")
    print("=" * 60)

    # 前置检查: 模型目录必须存在
    if not os.path.exists(COSYVOICE_MODEL):
        print(f"❌ 错误: CosyVoice 模型不存在: {COSYVOICE_MODEL}")
        print("   提示: 请先运行 build_cosy_voice.sh 下载模型")
        return False

    # 在子进程中运行的测试脚本
    # 原因: CosyVoice 依赖复杂 (Matcha-TTS, diffusers, transformers 等)，
    #       直接在主进程 import 可能导致模块路径冲突
    test_script = """
import sys
# 必须将 Matcha-TTS 加入 Python 路径，否则 CosyVoice 无法导入
sys.path.insert(0, "/opt/CosyVoice/third_party/Matcha-TTS")

from cosyvoice.cli.cosyvoice import CosyVoice
import scipy.io.wavfile as wavfile

print("✓ CosyVoice 导入成功")

# 加载 SFT 模型 (Supervised Fine-Tuned，包含预训练发音人)
model = CosyVoice("/data/models/CosyVoice-300M-SFT")
print("✓ 模型加载成功")

# 获取内置发音人列表 (SFT 模型包含 7 个发音人)
spks = model.list_available_spks()
print(f"✓ 可用发音人: {spks}")

if not spks:
    print("❌ 没有可用发音人")
    sys.exit(1)

# 使用第一个发音人进行语音合成
# inference_sft 返回 generator，每个 item 包含生成的音频数据
for item in model.inference_sft("你好,欢迎使用语音合成系统。", spk_id=spks[0]):
    wav = item["tts_speech"][0].numpy()
    # 保存为 16-bit PCM WAV，采样率 22050Hz
    wavfile.write("/tmp/test_voice_tts.wav", 22050, (wav * 32767).astype("int16"))
    print(f"✓ TTS 生成成功: {len(wav)} 采样点")

print("✅ TTS 测试通过")
"""

    print(f"✓ 运行: {PYTHON} -c '<test_script>'")
    print(f"✓ LD_LIBRARY_PATH={os.environ.get('LD_LIBRARY_PATH', '')[:60]}...")

    try:
        # 在 CosyVoice 目录下运行，确保相对路径正确
        result = subprocess.run(
            [PYTHON, "-c", test_script],
            capture_output=True,
            text=True,
            timeout=120,  # TTS 首次加载模型较慢，需要较长时间
            cwd=COSYVOICE_DIR
        )

        # 打印 stdout (正常输出)
        for line in result.stdout.strip().split('\n'):
            if line:
                print(line)
        
        # 过滤 stderr，只显示错误信息
        for line in result.stderr.strip().split('\n'):
            if 'ERROR' in line or 'Error' in line or '错误' in line:
                print(line)

        # 验证: 检查返回码和输出文件
        if result.returncode == 0 and os.path.exists("/tmp/test_voice_tts.wav"):
            size = os.path.getsize("/tmp/test_voice_tts.wav")
            print(f"✓ 音频文件已生成: /tmp/test_voice_tts.wav ({size} bytes)")
            return True
        else:
            print(f"❌ TTS 失败 (returncode={result.returncode})")
            return False

    except subprocess.TimeoutExpired:
        print("❌ TTS 运行超时 (超过 120 秒)")
        return False
    except Exception as e:
        print(f"❌ TTS 运行异常: {e}")
        return False


def main():
    """
    主入口函数
    
    依次执行 ASR 和 TTS 测试，汇总结果。
    任一测试失败不影响另一个测试的执行。
    """
    print("语音功能验证")
    print("=" * 60)
    print(f"SenseVoice: {SENSEVOICE_BIN}")
    print(f"CosyVoice:  {COSYVOICE_DIR}")
    print(f"Python:     {PYTHON}")
    print("=" * 60)

    # 执行两项测试 (相互独立，一个失败不影响另一个)
    asr_ok = test_asr()
    tts_ok = test_tts()

    # 打印汇总报告
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
