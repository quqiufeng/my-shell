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

## img_to_video_v1.sh

图片生成视频 + 配音 + 字幕（多段文案版）。使用 SFT 预设音色（中文女声），无需参考音频。

### 功能

- 将一组图片配上中文 SFT 预设女声、字幕，自动生成带配音的短视频
- 模型只加载一次，批量生成所有配音，效率高
- 字幕时间与配音精确同步（通过 ffprobe 获取实际配音时长）
- 每段配音后自动添加 0.3 秒停顿
- 字幕自动换行（1080 宽度下约 12 字/行）
- 输出视频分辨率 1080×1920（适合抖音/快手竖屏）

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| 第1个 | 图片文件夹/单张图片/空格分隔的图片路径 | 必需 |
| 第2个 | 每张图片展示秒数（实际会根据配音自动调整） | 2 |
| 第3个 | 文案（用 `\|` 分隔每段，如 "第一句\|第二句\|第三句"） | 必需 |
| 第4个 | 输出视频文件路径 | output.mp4 |
| 第5个 | 音频延迟（预留参数） | 0.6 |

### 用法

```bash
# 基础用法
./img_to_video_v1.sh '/opt/image/story/' 2.5 '第一句|第二句|第三句' output.mp4

# 完整示例 - 高山流水成语故事（6张图片+6段文案）
./img_to_video_v1.sh /opt/image/gaoshan 2.5 \
  '春秋时期俞伯牙琴艺高超常在山水之间抚琴抒情|\
一日伯牙弹琴恰逢砍柴的钟子期路过驻足倾听|\
子期听懂了琴声中的意境二人一见如故成为知己|\
伯牙弹奏高山子期赞叹道巍巍乎若泰山|\
后来钟子期不幸病逝伯牙悲痛欲绝再无知音|\
伯牙摔琴断弦终身不再抚琴高山流水比喻知音难觅' \
  /opt/image/gaoshan_v1.mp4
```

### 特点

- 模型: CosyVoice-300M-SFT
- 音色: 预设中文女声
- **不需要**参考音频
- 自动生成 ASS 字幕
- **支持 TensorRT 加速** (需先运行 build_cosy_voice_3080.sh)

### 前提条件

- 必须先运行 `bash ~/my-shell/build_cosy_voice_3080.sh` 编译 TensorRT 引擎，否则脚本无法运行
- 需要预先配置好 CosyVoice 环境（`conda activate cosyvoice`）
- 图片支持 .jpg/.jpeg/.png 格式
- 文案段数应与图片数量一致，每段至少 12 个汉字

### 原理

1. CosyVoice TTS 生成配音（批量生成，模型只加载一次）
2. 根据配音时长计算字幕时间
3. 每张图片转为视频片段（时长=配音时长+0.3秒停顿）
4. 合并配音+字幕+视频

---

## img_to_video_v2.sh

图片生成视频 + 配音 + 字幕（多段文案版，支持声音克隆）。使用 Fun-CosyVoice3-0.5B 模型，可克隆任意参考音频的声音。

### 功能

- 与 v1 相同，但支持声音克隆，可使用自定义参考音频替代预设音色
- 支持任意参考音频（3-30秒 wav 格式），克隆说话人音色
- 其他功能与 v1 完全一致（字幕同步、批量配音、竖屏输出）
- 若参考音频不是 wav 格式，脚本会自动转换

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| 第1个 | 图片文件夹/单张图片/空格分隔的图片路径 | 必需 |
| 第2个 | 每张图片展示秒数（实际会根据配音自动调整） | 2 |
| 第3个 | 文案（用 `\|` 分隔每段，如 "第一句\|第二句\|第三句"） | 必需 |
| 第4个 | 参考音频（用于克隆声音，3-30秒 wav 格式） | 必需 |
| 第5个 | 输出视频文件路径 | output.mp4 |

### 用法

```bash
# 使用自定义声音克隆
./img_to_video_v2.sh '/opt/image/story/' 2.5 '文案一|文案二|文案三' ./voice.wav output.mp4

# 使用默认系统音源（zero_shot_prompt.wav）
./img_to_video_v2.sh /opt/image/gaoshan 2.5 \
  '春秋时期俞伯牙琴艺高超常在山水之间抚琴抒情|\
一日伯牙弹琴恰逢砍柴的钟子期路过驻足倾听|\
子期听懂了琴声中的意境二人一见如故成为知己|\
伯牙弹奏高山子期赞叹道巍巍乎若泰山|\
后来钟子期不幸病逝伯牙悲痛欲绝再无知音|\
伯牙摔琴断弦终身不再抚琴高山流水比喻知音难觅' \
  /home/dministrator/CosyVoice/asset/zero_shot_prompt.wav \
  /opt/image/gaoshan_v2.mp4

# 不需要克隆时使用 SFT 默认音色（与 v1 相同）
./img_to_video_v2.sh '/opt/image/story/' 2.5 '第一句|第二句' none output.mp4
```

### 特点

- 模型: Fun-CosyVoice3-0.5B
- 音色: 克隆参考音频的声音
- **需要**提供参考音频 (3-30秒)
- 支持自然语言指令控制 (方言、语速等)
- **支持 TensorRT 加速** (需先运行 build_cosy_voice_3080.sh)

### 前提条件

- 必须先运行 `bash ~/my-shell/build_cosy_voice_3080.sh` 编译 TensorRT 引擎，否则脚本无法运行
- 需要预先配置好 CosyVoice 环境（`conda activate cosyvoice`）
- 参考音频建议 3-30 秒，太短克隆效果差，太长加载慢
- Fun-CosyVoice3 模型对短文本(<10字)可能生成异常音频，建议每段文案>12字
- 若不需要克隆，可传 "none" 作为参考音频，则使用默认 SFT 音色（与 v1 相同）

### 修复记录

- 短文本 (<10字) 会生成异常音频 (0.08秒)
- 解决方案: 使用 `inference_instruct2` + tts_text 前加换行符

---

## img_to_video_v3.sh

图片生成视频 + 配音 + 字幕（新流程，精确对齐版本）。使用 Fun-CosyVoice3-0.5B 模型，支持声音克隆，字幕与配音精确对齐。

### 功能

- 一次性配音：所有文案一次生成，模型只加载一次，效率高
- 固定停顿：每段配音之间添加固定 0.3 秒停顿，节奏可控
- 字幕对齐：根据配音实际时长+停顿时间生成精确对齐的字幕
- 图片停留：根据配音总时长自动计算每张图片的展示时间
- 支持声音克隆（参考音频）或默认 SFT 音色（传 "none"）

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| 第1个 | 图片文件夹/单张图片/空格分隔的图片路径 | 必需 |
| 第2个 | 每张图片展示秒数（会被配音总时长覆盖） | 2 |
| 第3个 | 文案（用 `\|` 分隔每段，**不要包含标点符号**） | 必需 |
| 第4个 | 参考音频（用于克隆声音，传 "none" 使用默认音色） | 必需 |
| 第5个 | 输出视频文件路径 | output.mp4 |

### 用法

```bash
# 基础用法（使用默认 SFT 音色）
./img_to_video_v3.sh '/opt/image/story/' 2.5 '文案一|文案二|文案三' none output.mp4

# 使用声音克隆
./img_to_video_v3.sh '/opt/image/story/' 2.5 '文案一|文案二|文案三' ./voice.wav output.mp4

# 完整示例 - 高山流水成语故事（6张图片+6段文案）
./img_to_video_v3.sh /opt/image/gaoshan 2.5 \
  '春秋时期俞伯牙琴艺高超常在山水之间抚琴抒情|\
一日伯牙弹琴恰逢砍柴的钟子期路过驻足倾听|\
子期听懂了琴声中的意境二人一见如故成为知己|\
伯牙弹奏高山子期赞叹道巍巍乎若泰山|\
后来钟子期不幸病逝伯牙悲痛欲绝再无知音|\
伯牙摔琴断弦终身不再抚琴高山流水比喻知音难觅' \
  /home/dministrator/CosyVoice/asset/zero_shot_prompt.wav \
  /opt/image/gaoshan_v3.mp4
```

### 特点

- 模型: Fun-CosyVoice3-0.5B（克隆）/ CosyVoice-300M-SFT（默认）
- 音色: 克隆参考音频 或 默认中文女声
- **模型只加载一次**，批量生成所有配音
- 字幕精确对齐（读取 `timings.txt` 中的实际时间）
- 停顿期间**不显示字幕**
- 图片停留时间自动计算（总时长 ÷ 图片数量）
- **支持 TensorRT 加速** (需先运行 build_cosy_voice_3080.sh)

### 前提条件

- 必须先运行 `bash ~/my-shell/build_cosy_voice_3080.sh` 编译 TensorRT 引擎，否则脚本无法运行
- 需要预先配置好 CosyVoice 环境（`conda activate cosyvoice`）
- 文案不要包含标点符号，会影响配音节奏和字幕对齐
- 图片支持 .jpg/.jpeg/.png 格式

### 实现原理

```
1. 生成配音 (tts_batch_v3.py)
   ├── 一次加载 CosyVoice 模型
   ├── 批量生成所有文案配音
   ├── 每段之间添加 0.3 秒静音停顿
   └── 保存时间信息到 timings.txt

2. 合并配音
   └── 直接使用 merged.wav（已含停顿）

3. 生成字幕
   ├── 读取 timings.txt 中的精确时间
   ├── 字幕开始 = 累计时间
   └── 字幕结束 = 开始 + 配音时长

4. 生成视频
   ├── 计算配音总时长
   ├── 每张图停留 = 总时长 / 图片数量
   └── 合成视频
```

---

## v1 / v2 / v3 对比

| 特性 | v1 (SFT 预设) | v2 (声音克隆) | v3 (精确对齐) |
|------|---------------|---------------|---------------|
| **模型** | CosyVoice-300M-SFT | Fun-CosyVoice3-0.5B | Fun-CosyVoice3-0.5B |
| **参考音频** | 不需要 | 需要 (3-30秒 wav) | 需要 (传 "none" 用默认) |
| **模型加载** | 每段一次 | 每段一次 | **一次** |
| **配音停顿** | ffmpeg 添加 0.3s | ffmpeg 添加 0.3s | **TTS 生成时插入 0.3s** |
| **字幕对齐** | 估算（配音时长+0.3s） | 估算（配音时长+0.3s） | **精确（timings.txt）** |
| **图片停留** | 配音时长+0.3s | 配音时长+0.3s | **总时长÷图片数** |
| **适用场景** | 快速生成、统一风格 | 个性化、模仿声音 | **成品制作、精确对齐** |

---

## Qwen API 上下文配置指南

### 问题背景

使用 OpenCode 连接本地 Qwen 模型时，可能会遇到错误：

```
request (19974 tokens) exceeds the available context size (16384 tokens), try increasing it
```

这是因为 llama.cpp 服务端的上下文大小与 OpenCode 配置不匹配。

### llama.cpp 启动参数与实际上下文的关系

| 启动参数 `-c` | 实际 Slot 上下文 | 说明 |
|---------------|-----------------|------|
| 65536 | 16384 | 默认值 |
| 131072 | 32768 | 2倍 |
| 262144 | 65536 | 4倍 |

**重要**：由于 Qwen3.5-9B 模型原始训练上下文是 16K，需要通过 `-c` 参数扩展。实际上下文约为参数值的 **1/4**。

### OpenCode 配置文件参数

配置文件位置：`~/.config/opencode/opencode.json`

```json
{
  "model": "llama.cpp/qwen3.5-9b",
  "provider": {
    "llama.cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "qwen3.5-9b": {
          "name": "qwen3.5-9b",
          "maxContextWindow": 131072,
          "maxOutputTokens": 65536,
          "options": {
            "num_ctx": 131072
          }
        }
      }
    }
  }
}
```

### 参数对应关系

| OpenCode 配置 | llama.cpp 参数 | 说明 |
|---------------|----------------|------|
| `maxContextWindow` | `-c` (ctx-size) | 最大上下文窗口 |
| `options.num_ctx` | `-c` (ctx-size) | 传递给 API 的上下文大小 |
| `maxOutputTokens` | `--n-predict` | 最大输出 tokens |

### 解决 Token 限制的方法

#### 方法 1：修改 llama.cpp 启动参数

编辑启动脚本 `3080/run_qwen_api.sh`：

```bash
# 修改 -c 参数值
-c 131072  # 对应 32K 上下文
# 或
-c 262144  # 对应 64K 上下文
```

重启服务：

```bash
pkill -f llama-server
./3080/run_qwen_api.sh
```

#### 方法 2：修改 OpenCode 配置

在 `~/.config/opencode/opencode.json` 中设置：

```json
{
  "model": "llama.cpp/qwen3.5-9b",
  "provider": {
    "llama.cpp": {
      "options": { "baseURL": "http://localhost:11434/v1" },
      "models": {
        "qwen3.5-9b": {
          "name": "qwen3.5-9b",
          "maxContextWindow": 131072,
          "maxOutputTokens": 65536,
          "options": { "num_ctx": 131072 }
        }
      }
    }
  }
}
```

#### 方法 3：运行时指定模型

```bash
opencode -m llama.cpp/qwen3.5-9b
```

### 验证配置

检查 llama.cpp 服务实际上下文：

```bash
curl -s http://localhost:11434/slots | grep -o '"n_ctx":[0-9]*'
```

检查 OpenCode 配置是否生效：

```bash
opencode debug config
```

### 备份配置

```bash
cp ~/.config/opencode/opencode.json ~/my-shell/opencode.json
```

---

## img.sh - AI 图像生成脚本

基于 stable-diffusion.cpp 的图像生成工具，针对 RTX 3080 10GB 显存优化。

### 功能

- 使用 SD Turbo 模型快速生成高质量图片
- 支持自定义分辨率、采样方法、CFG Scale
- 自动添加质量前缀词提升生成质量
- 支持负面提示词过滤不良内容
- 集成 FreeU、SAG、自动增强等高级特性

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| $1 | 提示词 (Prompt) | "A beautiful landscape" |
| $2 | 输出文件路径 | ~/TIMESTAMP_MD5.png |
| $3 | 宽度 | 1280 |
| $4 | 高度 | 720 |

### 环境变量

```bash
SAMPLING_METHOD=euler CFG_SCALE=3.2 STEPS=25 ./img.sh "一只猫"
```

### 用法

```bash
# 基础用法
./3080/img.sh "A beautiful landscape"

# 指定输出路径和分辨率
./3080/img.sh "A sunset" /mnt/e/app/sunset.png 1280 720

# 使用环境变量覆盖参数
SAMPLING_METHOD=dpm++ CFG_SCALE=4.0 STEPS=30 ./3080/img.sh "A cat"
```

### 原理

1. 使用 `myimg-cli` (stable-diffusion.cpp 封装) 加载模型
2. 通过 Qwen3-4B 模型理解提示词
3. 使用 z_image_turbo-Q5_K_M.gguf 扩散模型生成图片
4. 应用 FreeU、SAG 等技术提升质量
5. 输出 PNG 格式图片

### 依赖

- `~/my-img/build/myimg-cli`
- `/opt/image/model/z_image_turbo-Q5_K_M.gguf`
- `/opt/image/model/ae.safetensors` (VAE)
- `/opt/image/model/Qwen3-4B-Instruct-2507-Q4_K_M.gguf` (提示词理解)
- ONNX Runtime

---

## run_qwen3.5-9b_llama.sh - llama.cpp API 服务启动脚本

启动 Qwen3.5-9B 模型的 llama.cpp API 服务，提供 OpenAI 兼容的 API 接口。

### 功能

- 在 RTX 3080 10GB 上运行 Qwen3.5-9B (Q5_K_S) 模型
- 提供 OpenAI 兼容的 `/v1/chat/completions` API
- 支持 128K 上下文长度
- 使用 Flash Attention 和 KV Cache 量化优化显存

### 参数

无命令行参数，所有配置在脚本内定义：

| 配置项 | 值 | 说明 |
|--------|-----|------|
| GPU 层数 | 33 | 全部加载到 GPU |
| 上下文 | 131072 | 128K |
| Batch Size | 1024 | 批量大小 |
| KV Cache | q4_0 | KV 缓存量化 |
| 端口 | 11434 | API 服务端口 |

### 用法

```bash
# 启动服务
cd ~/my-shell/3080
setsid ./run_qwen3.5-9b_llama.sh > /tmp/9b_llama_3080.log 2>&1 &
echo $!  # 记录 PID

# 查看日志
tail -f /tmp/9b_llama_3080.log

# 测试 API
curl http://localhost:11434/v1/models

# 停止服务
pkill -f llama-server
```

### 原理

1. 使用 llama.cpp 的 `llama-server` 二进制文件
2. 加载 Qwopus3.5-9B-v3.Q5_K_S.gguf 模型
3. 启用 CUDA 加速 (`-ngl 33`)
4. 使用 Flash Attention 提升推理速度
5. KV Cache 量化 (q4_0) 控制显存占用约 8GB

### 性能

- RTX 3080 10GB 上约 **75 tok/s** (Q5_K_S, BATCH=1024)
- 显存占用约 8136 MiB

### 依赖

- `~/llama.cpp/build/bin/llama-server`
- `/opt/image/Qwopus3.5-9B-v3-GGUF/Qwopus3.5-9B-v3.Q5_K_S.gguf`
- CUDA 12.0+

---

## run_qwen3.5-9b_koboldcpp.sh - KoboldCpp API 服务启动脚本

使用 KoboldCpp 框架启动 Qwen3.5-9B API 服务，作为 llama.cpp 的替代方案。

### 功能

- 提供与 llama.cpp 相同的 OpenAI 兼容 API
- 支持 KoboldCpp 特有的功能（如智能缓存）
- 显存占用略低 (~7.5GB vs ~8.0GB)

### 参数

| 配置项 | 值 | 说明 |
|--------|-----|------|
| GPU 层数 | 33 | 全部加载到 GPU |
| 上下文 | 131072 | 128K |
| Batch Size | 1024 | 批量大小 |
| KV Cache | q4_0 | KV 缓存量化 |
| 端口 | 11434 | API 服务端口 |

### 用法

```bash
# 启动服务
cd ~/my-shell/3080
setsid ./run_qwen3.5-9b_koboldcpp.sh > /tmp/9b_koboldcpp_3080.log 2>&1 &
echo $!  # 记录 PID

# 停止服务
pkill -f koboldcpp.py
```

### 性能对比

| 框架 | 速度 | 显存占用 | 推荐度 |
|------|------|----------|--------|
| llama.cpp | ~75 tok/s | ~8.0GB | ⭐⭐⭐⭐⭐ |
| KoboldCpp | ~57 tok/s | ~7.5GB | ⭐⭐⭐ |

### 依赖

- `/opt/koboldcpp/koboldcpp.py`
- Python 3
- 模型文件同 llama.cpp

---

## test_api_performance.sh - API 性能测试脚本

自动测试 llama.cpp 和 KoboldCpp 的性能表现。

### 功能

- 自动启动 llama.cpp 和 KoboldCpp 服务
- 使用 `test_api.py` 进行标准化性能测试
- 对比两种框架的推理速度
- 自动清理服务进程

### 用法

```bash
cd ~/my-shell/3080
./test_api_performance.sh
```

### 测试流程

1. 停止现有服务
2. 启动 llama.cpp → 测试性能 → 停止服务
3. 启动 KoboldCpp → 测试性能 → 停止服务
4. 输出对比结果

### 依赖

- `~/my-shell/test_api.py` (性能测试脚本)
- 两个启动脚本 (`run_qwen3.5-9b_llama.sh`, `run_qwen3.5-9b_koboldcpp.sh`)

---

## video_subtitle_voice.sh - 视频配音字幕生成工具

为现有短视频添加 AI 配音和同步字幕。

### 功能

- 根据文案自动生成配音（支持声音克隆或默认音色）
- 字幕与配音精确同步（使用 tts_batch_v3.py 的 timings.txt）
- 保留原视频画面，叠加配音和字幕
- 支持文案直接传入或从文件读取

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| $1 | 输入视频文件 | 必填 |
| $2 | 文案（\|分隔）或 .txt 文件路径 | 必填 |
| $3 | 参考音频（用于克隆） | 视频同目录下 voice.wav |
| $4 | 输出视频路径 | 原视频名_subtitled.mp4 |

### 用法

```bash
# 方式1：直接传入文案
./3080/video_subtitle_voice.sh ~/video/orgin.mp4 '第一句|第二句|第三句'

# 方式2：从文件读取文案
./3080/video_subtitle_voice.sh ~/video/orgin.mp4 ~/video/script.txt

# 指定参考音频（声音克隆）
./3080/video_subtitle_voice.sh ~/video/orgin.mp4 '文案' ~/video/voice.wav

# 使用默认 SFT 音色（不克隆）
./3080/video_subtitle_voice.sh ~/video/orgin.mp4 '文案' none
```

### 原理

1. 解析文案（支持 \| 分隔的字符串或 .txt 文件）
2. 使用 `tts_batch_v3.py` 生成配音（模型只加载一次）
3. 从 `timings.txt` 读取精确时间信息
4. 生成 ASS 字幕文件（自动换行、精确时间对齐）
5. 使用 ffmpeg 合成：原视频 + 配音 + 字幕

### 特点

- 段间停顿 0.3 秒
- 字幕自动换行（每行约 13 字）
- 配音音量增益 1.5 倍
- 临时文件自动清理

### 依赖

- CosyVoice 环境（`conda activate cosyvoice`）
- `tts_batch_v3.py`
- ffmpeg

---

## audio_to_subtitle.sh - 音频转字幕工具

根据配音文件生成时间对齐的 ASS 字幕文件。

### 功能

- 读取分段配音文件（1.wav, 2.wav...）
- 计算每段配音时长
- 生成带精确时间戳的 ASS 字幕
- 支持自定义段间停顿

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| $1 | 配音文件夹（含 1.wav, 2.wav...） | 必填 |
| $2 | 段间停顿（秒） | 0.3 |
| $3 | 文案（\|分隔） | 必填 |
| $4 | 输出字幕文件路径 | 必填 |

### 用法

```bash
./3080/audio_to_subtitle.sh "/opt/image/audios/" 0.3 "第一句|第二句|第三句" /opt/image/subtitle.ass
```

### 原理

1. 使用 ffprobe 获取每段配音时长
2. 累加时间计算字幕起止时间
3. 自动换行（每行约 12 字）
4. 输出标准 ASS 格式字幕文件

---

## generate_script.py - 视频字幕文案生成工具

调用本地 Qwen 模型，根据产品介绍素材自动生成短视频字幕文案。

### 功能

- 根据视频时长自动计算文案段数和字数
- 读取产品介绍素材（info.txt）
- 调用本地 Qwen API 生成文案
- 自动过滤英文、数字、标点符号
- 去重和长度校验

### 参数

| 参数 | 说明 |
|------|------|
| 参数1 | 视频文件路径（用于计算时长） |
| 参数2 | 素材文件路径（产品介绍文本） |
| `--output` | 输出文案文件路径（可选） |

### 用法

```bash
# 基础用法
python3 ~/my-shell/3080/generate_script.py ~/video/orgin.mp4 ~/video/info.txt

# 保存到文件
python3 ~/my-shell/3080/generate_script.py ~/video/orgin.mp4 ~/video/info.txt --output ~/video/script.txt

# 生成后直接用于视频合成
SCRIPT=$(python3 ~/my-shell/3080/generate_script.py ~/video/orgin.mp4 ~/video/info.txt | tail -1)
./3080/video_subtitle_voice.sh ~/video/orgin.mp4 "$SCRIPT"
```

### 原理

1. 使用 ffprobe 获取视频时长
2. 按语速 3.1 字/秒计算总字数和段数
3. 构建 prompt 调用本地 Qwen API (`localhost:11434`)
4. 处理 reasoning 模型的输出（提取最终文案）
5. 清理：去掉英文、数字、标点，去重
6. 验证每段长度（10-40 字）

### 文案要求

- 无标点符号
- 无英文字母和数字
- 用 `|` 分隔段落
- 顺序：品牌介绍 → 核心卖点 → 功能特点 → 行动号召

### 依赖

- 本地 llama.cpp 服务（`./run_qwen3.5-9b_llama.sh`）
- Python 3 + requests
- ffmpeg (ffprobe)

---

## 脚本关系图

```
图像生成: img.sh → stable-diffusion.cpp → PNG 图片
           ↓
文案生成: generate_script.py → Qwen API (localhost:11434) → 字幕文案
           ↓
视频合成: img_to_video_v1/v2/v3.sh → CosyVoice TTS + ffmpeg → 带配音字幕视频
           ↓
后期处理: video_subtitle_voice.sh → 为现有视频添加配音字幕
           ↓
字幕工具: audio_to_subtitle.sh → 根据配音生成 ASS 字幕

模型服务: run_qwen3.5-9b_llama.sh → llama.cpp API (推荐)
          run_qwen3.5-9b_koboldcpp.sh → KoboldCpp API (备选)
          test_api_performance.sh → 性能测试对比
```

---

