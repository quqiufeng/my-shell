# My Shell Scripts

本地 AI 工具脚本集合，针对 **RTX 3080 10GB** 显存优化。

## 环境要求

- GPU: NVIDIA RTX 3080 10GB
- 系统: WSL2 (Ubuntu)
- CUDA: 12.0

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
| img.py | Nano Banana API 图片生成 |

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
