# My Shell Scripts

本地 AI 工具脚本集合，针对 **RTX 3080 10GB** 显存优化。

## 环境要求

- GPU: NVIDIA RTX 3080 10GB
- 系统: WSL2 (Ubuntu)
- CUDA: 12.0

---

## conda.sh (Conda 初始化脚本)

### 说明

- **原位置**: `~/anaconda3/etc/profile.d/conda.sh`
- **拷贝位置**: `~/my-shell/conda.sh`

### 功能

Conda 环境初始化脚本，用于在 shell 中激活 conda 功能。

### 用途

所有需要使用 conda 环境的脚本都会调用此文件：

```bash
# 方式1: 直接 source
source ~/anaconda3/etc/profile.d/conda.sh
conda activate cosyvoice

# 方式2: 使用拷贝的版本
source ~/my-shell/conda.sh
conda activate cosyvoice
```

### 为什么拷贝到本目录

为了保持脚本的自包含性，确保在任何目录下执行脚本时都能正确找到 conda 初始化逻辑。

---

## 脚本列表

| 脚本 | 功能 |
|------|------|
| img_3080.sh | 图片生成 (文生图) |
| upscale_3080.sh | ESRGAN 快速放大 |
| upscale_hires_3080.sh | Kohya Hires 高清放大 |
| run_qwen_3080.sh | Qwen 本地对话 |
| run_qwen_api_3080.sh | Qwen API 服务 |
| build_sd_cpp_3080.sh | 编译 stable-diffusion.cpp |
| build_llama_cpp_3080.sh | 编译 llama.cpp |
| img_to_video_v1_3080.sh | 图片生成视频 (SFT预设音色) |
| img_to_video_v2_3080.sh | 图片生成视频 (声音克隆) |
| test_cosyvoice.sh | CosyVoice 功能测试 |
| build_cosy_voice_3080.sh | 编译 CosyVoice 环境 |
| build_sense_voice_3080.sh | 编译 SenseVoice.cpp |

---

## img_3080.sh

图片生成脚本，使用 Z-Image Turbo 模型。

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| 第1个 | 提示词 (prompt) | 必需 |
| 第2个 | 输出文件名 | 自动生成 |
| 第3个 | 宽度 | 1920 |
| 第4个 | 高度 | 1080 |

### 用法

```bash
./img_3080.sh "a beautiful landscape"

./img_3080.sh "a beautiful woman portrait" portrait.png 1280 720
```

### 模型信息

- 模型: Z-Image Turbo (z_image_turbo-Q8_0.gguf)
- 适用: 写实人像、风景、产品
- 不适合: 动漫、卡通

---

## upscale_3080.sh

ESRGAN 快速放大脚本，适合预览。

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| 第1个 | 输入图片 | 必需 |
| 第2个 | 输出图片 | 自动生成 |
| 第3个 | 放大倍数 (2 或 4) | 2 |

### 用法

```bash
./upscale_3080.sh image.png

./upscale_3080.sh image.png out.png 4
```

### 性能

| 方法 | 输入 | 输出 | 耗时 |
|------|------|------|------|
| 直接生成 | - | 2560x1440 | ~217秒 |
| 2x ESRGAN | 1280x720 | 2560x1440 | ~16秒 |
| 4x UltraSharp | 640x360 | 2560x1440 | ~5秒 |

---

## upscale_hires_3080.sh

Kohya Hires. fix 高清放大脚本，效果最好。

### 重要

- 耗时较长 (约 6-10 分钟)
- 使用 nohup 后台执行
- 日志保存到 .log 文件

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| 第1个 | 输入图片 | 必需 |
| 第2个 | 输出图片 | 自动生成 |
| 第3个 | 重绘强度 (0.1-0.8) | 0.4 |
| 第4个 | 步数 | 12 |

### 用法

```bash
./upscale_hires_3080.sh input.png

./upscale_hires_3080.sh input.png output.png 0.4 12
```

### 原理

两步走:
1. img2img 放大: 在 latent space 进行去噪重绘
2. ImageMagick 锐化: USM 锐化增强清晰度

### 效果对比

| 方法 | 耗时 | 效果 |
|------|------|------|
| ESRGAN 单独 | ~20秒 | 一般 |
| img2img + 锐化 (本脚本) | ~7分钟 | ★★★★★ |

---

## run_qwen_3080.sh

Qwen3.5-9B 本地对话脚本。

### 参数

| 参数 | 说明 |
|------|------|
| 第1个 | 提示词 (可选) |

### 用法

```bash
./run_qwen_3080.sh

./run_qwen_3080.sh "你好"
```

### 配置

- 模型: Qwen3.5-9B-Q6_K.gguf
- GPU 层数: 40
- 上下文: 20480
- Batch Size: 512

---

## run_qwen_api_3080.sh

启动 Qwen3.5-9B API 服务 (OpenAI 兼容)。

### 用法

```bash
./run_qwen_api_3080.sh
```

### 地址

- 本地: http://localhost:11434

### 端口转发 (Windows PowerShell 管理员)

```powershell
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=11434 connectaddress=172.23.212.172 connectport=11434
```

---

## build_sd_cpp_3080.sh

编译 stable-diffusion.cpp (CUDA 版本)。

### 用法

```bash
./build_sd_cpp_3080.sh
```

### 产出

- ~/stable-diffusion.cpp/bin/sd-cli
- ~/stable-diffusion.cpp/bin/sd-server

---

## build_llama_cpp_3080.sh

编译 llama.cpp (CUDA 版本)。

### 用法

```bash
./build_llama_cpp_3080.sh
```

### 产出

- ~/llama.cpp/build/bin/llama-cli
- ~/llama.cpp/build/bin/llama-server

---

## img_to_video_v1.sh

图片生成视频脚本 (SFT 预设音色版本)。

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| 第1个 | 图片文件夹/图片路径 | 必需 |
| 第2个 | 每张图片展示秒数 | 2 |
| 第3个 | 文案 (用 `|` 分隔多段) | 必需 |
| 第4个 | 输出文件名 | output.mp4 |

### 用法

```bash
# 单文案
./img_to_video_v1_3080.sh './story/' 2 '古时候有个书生'

# 多段文案
./img_to_video_v1_3080.sh './story/' 2 '第一句|第二句|第三句' output.mp4
```

### 特点

- 模型: CosyVoice-300M-SFT
- 音色: 预设中文女声
- **不需要**参考音频
- 自动生成 ASS 字幕
- **支持 TensorRT 加速** (需先运行 build_cosy_voice_3080.sh)

### ⚠️ 前提条件

必须先运行 `bash ~/my-shell/build_cosy_voice_3080.sh` 编译 TensorRT 引擎，否则脚本无法运行。

### 原理

1. CosyVoice TTS 生成配音
2. 每张图片转为视频片段
3. 合并配音+字幕+视频

---

## img_to_video_v2.sh

图片生成视频脚本 (声音克隆版本)。

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| 第1个 | 图片文件夹/图片路径 | 必需 |
| 第2个 | 每张图片展示秒数 | 2 |
| 第3个 | 文案 (用 `|` 分隔多段) | 必需 |
| 第4个 | 参考音频 (用于克隆声音) | 必需 |
| 第5个 | 输出文件名 | output.mp4 |

### 用法

```bash
./img_to_video_v2_3080.sh './story/' 2 '第一句|第二句|第三句' ./voice.wav output.mp4
```

### 特点

- 模型: Fun-CosyVoice3-0.5B
- 音色: 克隆参考音频的声音
- **需要**提供参考音频 (3-30秒)
- 支持自然语言指令控制 (方言、语速等)
- **支持 TensorRT 加速** (需先运行 build_cosy_voice_3080.sh)

### ⚠️ 前提条件

必须先运行 `bash ~/my-shell/build_cosy_voice_3080.sh` 编译 TensorRT 引擎，否则脚本无法运行。

### 修复记录

- 短文本 (<10字) 会生成异常音频 (0.08秒)
- 解决方案: 使用 `inference_instruct2` + tts_text 前加换行符

---

## test_cosyvoice.sh

CosyVoice 功能测试脚本。

### 用法

```bash
bash ~/my-shell/test_cosyvoice.sh
```

### 测试内容

1. **zero_shot** - 零样本语音克隆
2. **cross_lingual** - 跨语言合成
3. **instruct2** - 指令控制 (方言、语速)
4. **fine_grained_control** - 细粒度控制 (呼吸声、笑声)
5. **add_zero_shot_spk** - 保存音色供后续使用

### 输出

生成文件: `/tmp/cosyvoice_test*.wav`

---

## build_cosy_voice_3080.sh

CosyVoice 环境搭建脚本 (语音合成 TTS)。

### ⚠️ 重要：必须先运行此脚本

**v1 和 v2 脚本依赖 TensorRT 加速，必须先运行此脚本完成以下操作：**

1. 安装 FFmpeg 系统依赖
2. 创建 conda 环境 (Python 3.10)
3. 安装 CUDA 12.1、cuDNN 8.9 (conda)
4. 安装 TensorRT 8.6.1 (pip)
5. 下载预训练模型到 /opt/image
6. **编译 TensorRT 引擎** (关键步骤)

### 用法

```bash
bash ~/my-shell/build_cosy_voice_3080.sh
```

### TensorRT 引擎说明

编译后的引擎文件位置：

| 模型 | 路径 | 大小 |
|------|------|------|
| CosyVoice-300M-SFT | `/opt/image/CosyVoice-300M-SFT/flow.decoder.estimator.fp16.mygpu.plan` | ~202MB |
| Fun-CosyVoice3-0.5B | `/opt/image/Fun-CosyVoice3-0.5B/flow.decoder.estimator.fp16.mygpu.plan` | ~640MB |

**引擎只需编译一次**，之后运行 v1/v2 会自动使用缓存的引擎加速推理。

### 环境变量

激活 conda:
```bash
conda activate cosyvoice
```

### 依赖包

- hyperpyyaml
- onnxruntime
- openai-whisper
- transformers
- x-transformers
- pyarrow
- pyworld
- torchcodec
- torchaudio
- pytorch-lightning
- torchmetrics

### 模型位置

- `/opt/image/CosyVoice-300M-SFT`
- `/opt/image/Fun-CosyVoice3-0.5B`

---

## build_sense_voice_3080.sh

SenseVoice.cpp 编译脚本 (语音识别 STT)。

### 用法

```bash
bash ~/my-shell/build_sense_voice_3080.sh
```

### 产出

- `~/SenseVoice.cpp/bin/sense-voice-*`

### 功能

- 语音 → 文字 (Speech-to-Text)
- 多语言支持
- 音频文件转写

---

## img.py

Nano Banana API 图片生成模块 (调用 Google Gemini)。

### 依赖

```bash
pip install requests python-dotenv
```

### 环境变量

在 .env 文件中设置:

```bash
Nano_Banana_API_KEY=your_api_key
```

### 用法

```python
from img import generate_flashcard_background

generate_flashcard_background(theme="Harry Potter", filename="card.png")
```

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| theme | 提示词内容 | 必需 |
| style | 额外样式 | - |
| aspect | 纵横比 | 9:16 |
| size | 分辨率 | 1K |
| pro | Pro 模式 | True |

---

## 常用命令

```bash
nvidia-smi
ps aux | grep sd-cli
tail -f output.log
```
