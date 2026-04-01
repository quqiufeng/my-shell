# My Shell Scripts

本地 AI 工具脚本集合，针对 **RTX 3080 10GB** 显存优化。

## 📚 重要文档

- **[OpenCode 本地大模型配置指南](opencode.md)** - 如何配置 OpenCode 连接本地部署的 Qwen 模型 API

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
| run_qwen_coder14b_exllamav2.py | Qwen2.5-Coder-14B API 服务 (ExLlamaV2) |
| run_qwen_coder7b_exllamav2.py | Qwen2.5-Coder-7B API 服务 (ExLlamaV2) |
| run_qwen3.5-9b.sh | Qwen3.5-9B API 服务 (llama.cpp) |
| run_koboldcpp_9b.sh | Qwen3.5-9B API 服务 (KoboldCpp) |

---

## Qwen 模型性能对比 (RTX 3080 10GB)

### 模型配置对比

| 模型 | 引擎 | 量化 | Context | KV Cache | 启动脚本 | 端口 | 显存占用 |
|------|------|------|---------|----------|----------|------|----------|
| **Qwen2.5-Coder 7B** | ExLlamaV2 | Q4_K_M | **64K** | Q6 | `run_qwen_coder7b_exllamav2.py` | 11434 | ~8GB |
| **Qwen2.5-Coder 14B** | ExLlamaV2 | Q4_K_M | **12K** | Q6 | `run_qwen_coder14b_exllamav2.py` | 11434 | ~10GB |
| **Qwen3.5-9B** | llama.cpp | Q4_K_M | **64K** | q4_0 | `run_qwen3.5-9b_llama.sh` | 11434 | ~6GB |
| **Qwen3.5-9B** | KoboldCpp | Q4_K_M | **80K** | q4_0 | `run_qwen3.5-9b_koboldcpp.sh` | 11434 | ~6GB |

### 性能测试结果 (30个高难度提示词，200 tokens/次)

**测试方法**: `cd /home/dministrator/my-shell && python3 branch.py 11434 <模型名> 200`

#### 1. Qwen2.5-Coder 7B (ExLlamaV2) ⭐ 推荐
- **显存占用**: ~8GB
- **平均速度**: **78.4 tokens/s**
- **最快**: 二分查找 92.5 tokens/s
- **最慢**: 快速排序 46.2 tokens/s (首次加载)
- **典型速度**: 70-90 tokens/s

**特点**:
- ✅ **速度最快** - 比 9B 模型快 20-30%
- ✅ **上下文大** - 64K 可处理长代码文件
- ✅ **代码专用** - 针对代码生成优化
- ⚠️ 参数量较少，复杂推理能力略逊于 14B

**适用场景**: 日常开发、快速代码补全、长文件处理

#### 2. Qwen2.5-Coder 14B (ExLlamaV2)
- **显存占用**: ~10GB
- **平均速度**: **53.4 tokens/s**
- **最快**: 红黑树 59.0 tokens/s
- **最慢**: 最长公共子序列 40.4 tokens/s
- **典型速度**: 50-58 tokens/s

**特点**:
- ✅ **代码能力最强** - 14B 参数量，推理能力最佳
- ✅ 专业代码模型，代码质量高
- ⚠️ **速度较慢** - 比 7B 慢 47%
- ⚠️ **上下文小** - 仅 12K，长文件处理受限
- ⚠️ 显存占用高，接近 3080 上限

**适用场景**: 复杂算法实现、代码审查、需要高质量代码时

#### 3. Qwen3.5-9B (llama.cpp)
- **显存占用**: ~6GB
- **平均速度**: **67.5 tokens/s**
- **最快**: Dijkstra算法 77.2 tokens/s
- **最慢**: 快速排序 53.0 tokens/s
- **典型速度**: 65-75 tokens/s

**特点**:
- ✅ **兼容性好** - llama.cpp 生态完善
- ✅ **显存友好** - 仅 6GB，可与其他程序共存
- ✅ **通用能力强** - 不仅是代码，对话、推理也不错
- ⚠️ 速度比 ExLlamaV2 7B 慢

**适用场景**: 通用对话、代码生成、显存紧张时

#### 4. Qwen3.5-9B (KoboldCpp)
- **显存占用**: ~6GB
- **平均速度**: **62.0 tokens/s**
- **最快**: 最长公共子序列 67.8 tokens/s
- **最慢**: 阻塞队列 46.2 tokens/s
- **典型速度**: 60-65 tokens/s

**特点**:
- ✅ **最省内存** - KoboldCpp 内存优化最好
- ✅ **功能丰富** - 支持 Web UI、多模态
- ✅ **上下文最大** - 80K，可处理超长文本
- ⚠️ 速度略逊于 llama.cpp

**适用场景**: 长文本处理、需要 Web UI、多模态任务

### 性能总结对比

| 模型 | 引擎 | 速度 | 显存 | Context | 代码能力 | 推荐场景 |
|------|------|------|------|---------|----------|----------|
| **7B** ⭐ | ExLlamaV2 | **78.4** tok/s | 8GB | 64K | ★★★☆ | **日常开发首选** |
| **9B** | llama.cpp | 67.5 tok/s | 6GB | 64K | ★★★☆ | 通用对话 |
| **9B** | KoboldCpp | 62.0 tok/s | 6GB | **80K** | ★★★☆ | 长文本处理 |
| **14B** | ExLlamaV2 | 53.4 tok/s | 10GB | 12K | ★★★★ | 高质量代码 |

### 选择建议

1. **日常开发 (推荐)**: Qwen2.5-Coder 7B + ExLlamaV2
   - 速度最快，代码质量好，上下文够用

2. **显存紧张**: Qwen3.5-9B + KoboldCpp
   - 仅 6GB 显存，可与其他程序共存

3. **长文本处理**: Qwen3.5-9B + KoboldCpp (80K)
   - 上下文最大，适合处理长代码文件

4. **高质量代码**: Qwen2.5-Coder 14B + ExLlamaV2
   - 代码能力最强，但速度慢、上下文小

### 启动命令

```bash
# 1. Qwen2.5-Coder 7B (推荐日常开发)
cd ~/my-shell/3080 && nohup python run_qwen_coder7b_exllamav2.py > /tmp/7b.log 2>&1 &
echo "PID: $!"
# 测试: python3 branch.py 11434 "qwen2.5-coder-7b-exl2" 200

# 2. Qwen2.5-Coder 14B (高质量代码)
cd ~/my-shell/3080 && nohup python run_qwen_coder14b_exllamav2.py > /tmp/14b.log 2>&1 &
echo "PID: $!"
# 测试: python3 branch.py 11434 "qwen2.5-coder-14b-exl2" 200

# 3. Qwen3.5-9B (llama.cpp - 通用对话)
cd ~/my-shell/3080 && nohup bash run_qwen3.5-9b_llama.sh > /tmp/llama_9b.log 2>&1 &
echo "PID: $!"
# 测试: python3 branch.py 11434 "Qwen3.5-9B.Q4_K_M.gguf" 200

# 4. Qwen3.5-9B (KoboldCpp - 长文本/省内存)
cd ~/my-shell/3080 && nohup bash run_qwen3.5-9b_koboldcpp.sh > /tmp/koboldcpp_9b.log 2>&1 &
echo "PID: $!"
# 测试: python3 branch.py 11434 "koboldcpp/Qwen3.5-9B.Q4_K_M" 200
```

### API 测试命令

```bash
# 测试 7B/14B (ExLlamaV2)
python3 -c "
import requests, time
start = time.time()
r = requests.post('http://localhost:11435/v1/chat/completions',
  json={'model':'qwen2.5-coder','messages':[{'role':'user','content':'用Python实现快速排序'}],'max_tokens':100,'temperature':0.2},
  timeout=120)
tokens = r.json()['usage']['completion_tokens']
print(f'Test: {tokens/(time.time()-start):.1f} tokens/s')
"

# 测试 9B (llama.cpp)
python3 -c "
import requests, time
start = time.time()
r = requests.post('http://localhost:11434/v1/chat/completions',
  json={'model':'Qwen3.5-9B.Q4_K_M.gguf','messages':[{'role':'user','content':'用Python实现快速排序'}],'max_tokens':100,'temperature':0.2},
  timeout=120)
tokens = r.json()['usage']['completion_tokens']
print(f'Test: {tokens/(time.time()-start):.1f} tokens/s')
"
```

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

## img_to_video_v3.sh

图片生成视频脚本（配音字幕对齐版本）。

### 简介

v3 是最新的完整流程脚本，解决了 v1/v2 版本中配音和字幕不对齐的问题。

### 核心特性

- **一次配音**：所有文案一次生成，模型只加载一次，效率高
- **固定停顿**：每段配音之间添加 0.3 秒停顿，节奏可控
- **字幕对齐**：根据配音实际时长生成精确对齐的字幕
- **图片停留**：根据配音总时长自动计算每张图片的展示时间

### 参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| 第1个 | 图片文件夹/图片路径 | 必需 |
| 第2个 | 每张图片展示秒数（会被配音总时长覆盖） | 2 |
| 第3个 | 文案（用 `|` 分隔多段，**不要包含标点**） | 必需 |
| 第4个 | 参考音频（用于克隆声音） | 必需 |
| 第5个 | 输出文件名 | output.mp4 |

### 用法

```bash
# 必须去掉文案中的标点符号，用|分隔
./img_to_video_v3_3080.sh './story/' 2 '文案一|文案二|文案三' './voice.wav' output.mp4
```

### 完整示例

```bash
# 生成成语故事高山流水
./img_to_video_v3_3080.sh '/opt/image/' 2 \
    '战国时期俞伯牙是著名的琴师琴艺高超|一天伯牙在山间弹琴遇到砍柴的钟子期|子期听出伯牙琴中之意两人成为知音|伯牙弹高山子期曰巍巍乎若泰山|子期病逝后伯牙再无知音可寻|伯牙摔琴断弦高山流水比喻知音难觅' \
    '/home/dministrator/CosyVoice/asset/zero_shot_prompt.wav' \
    '/opt/image/gaoshan_v3.mp4'
```

### 前提条件

必须先运行 `bash ~/my-shell/build_cosy_voice_3080.sh` 编译 TensorRT 引擎。

---

## 实现原理

### 整体流程

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

### 技术细节

#### 1. 配音生成 (tts_batch_v3.py)

```python
# 关键代码
for seg in audio_segments[1:]:
    merged = torch.cat([merged, pause, seg], dim=1)

# pause = 0.3秒静音
pause_samples = int(0.3 * sample_rate)
pause = torch.zeros((1, pause_samples))
```

- 合并时在每段之间插入 0.3 秒静音
- 保存每段的开始时间、结束时间到 `timings.txt`

#### 2. 时间信息文件格式

```
1: 0.00 3.92 3.92
2: 4.22 8.54 4.32
3: 8.84 12.92 4.08
...
```

格式：`序号: 开始时间 结束时间 配音时长`

#### 3. 字幕对齐

根据 timings.txt 精确生成字幕时间：

```bash
# 第1段：0-3.92秒
# 第2段：4.22-8.54秒（4.22 = 3.92 + 0.3停顿）
# 第3段：8.84-12.92秒（8.84 = 8.54 + 0.3停顿）
```

**关键点**：停顿期间不显示字幕，因为下一段字幕的开始时间还没到

#### 4. 图片停留时间

```bash
# 总配音时长 / 图片数量
PER_IMAGE = TOTAL_DURATION / IMAGE_COUNT
```

### 为什么要用 v3

| 特性 | v1 | v2 | v3 |
|------|-----|-----|-----|
| 模型加载次数 | 每段一次 | 每段一次 | **一次** |
| 配音停顿 | TTS自动 | TTS自动 | **固定0.3秒** |
| 字幕对齐 | 估算 | 估算 | **精确** |
| 图片停留 | 固定参数 | 固定参数 | **自动计算** |
| 适用场景 | 快速预览 | 声音克隆 | **成品制作** |

### 常见问题

#### Q: 文案中的标点符号会影响配音吗？

**会**。v3 会自动去除文案中的所有标点符号，只保留文字。因为标点符号会导致 TTS 生成不均匀的停顿，影响对齐效果。

#### Q: 为什么第二段字幕开始时间不是紧接着第一段结束？

因为中间有 0.3 秒的停顿时间。这段时间配音是静音的，字幕不显示。

#### Q: 如何调整停顿时间？

修改 `tts_batch_v3.py` 中的 `pause_samples = int(0.3 * sample_rate)`，将 0.3 改为其他值。

#### Q: 配音总时长是多少？

取决于文案长度和语速。每段大约 3-5 秒，6 段约 24-26 秒（含 1.5 秒停顿）。

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

## 原理简述

### llama.cpp 启动参数

```bash
llama-server -c 131072 ...
```

| `-c` 参数值 | 实际 Slot 上下文 |
|------------|-----------------|
| 65536 | 16K |
| 131072 | 32K |
| 262144 | 64K |

**原理**：Qwen3.5-9B 原始训练上下文是 16K，`-c` 参数用于扩展上下文，实际可用约为参数的 **1/4**。

### OpenCode 配置参数

```json
{
  "model": "llama.cpp/qwen3.5-9b",
  "provider": {
    "llama.cpp": {
      "options": { "baseURL": "http://localhost:11434/v1" },
      "models": {
        "qwen3.5-9b": {
          "maxContextWindow": 131072,
          "maxOutputTokens": 65536,
          "options": { "num_ctx": 131072 }
        }
      }
    }
  }
}
```

| 配置项 | 作用 |
|--------|------|
| `maxContextWindow` | 声明最大上下文窗口 |
| `options.num_ctx` | 传递给 API 的实际上下文参数 |
| `maxOutputTokens` | 最大输出 tokens |

### 解决思路

1. 修改 llama.cpp 启动参数 `-c` 扩展上下文
2. 修改 OpenCode 配置 `num_ctx` 匹配服务端
3. 两者需同时匹配，否则会报 `exceeds context size` 错误

---

## DCP 动态上下文压缩插件

### 简介

[DCP (Dynamic Context Pruning)](https://github.com/Opencode-DCP/opencode-dynamic-context-pruning) 是 OpenCode 的上下文压缩插件，可以自动减少对话历史的 token 占用，优化长会话性能。

### 安装步骤

#### 1. 添加插件到配置

编辑 `~/.config/opencode/opencode.json`：

```json
{
  "plugin": ["@tarquinen/opencode-dcp@latest"],
  ...
}
```

#### 2. 创建 DCP 配置文件

创建 `~/.config/opencode/dcp.jsonc`：

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/Opencode-DCP/opencode-dynamic-context-pruning/master/dcp.schema.json",
  "enabled": true,
  "debug": false,
  "pruneNotification": "detailed",
  "pruneNotificationType": "chat",
  "tools": {
    "settings": {
      "nudgeEnabled": true,
      "nudgeFrequency": 10,
      "contextLimit": 100000
    },
    "distill": { "permission": "allow" },
    // ⚠️ 必须禁用 compress！否则会损坏 tool call JSON 格式
    "compress": { "permission": "deny" },
    "prune": { "permission": "allow" }
  },
  "strategies": {
    "deduplication": { "enabled": true },
    "supersedeWrites": { "enabled": true },
    "purgeErrors": { "enabled": true, "turns": 4 }
  }
}
```

#### 3. 重启 OpenCode

```bash
# 重新启动 opencode
opencode
```

### 使用命令

| 命令 | 功能 |
|------|------|
| `/dcp` | 显示可用命令 |
| `/dcp context` | 查看当前会话 token 使用情况 |
| `/dcp stats` | 查看累计压缩统计 |
| `/dcp sweep` | 手动触发压缩 |

### 压缩效果

实际测试效果（Qwen3.5-9B 模型，64K 上下文）：

| 阶段 | Prompt Tokens | 缓存相似度 |
|------|---------------|------------|
| 第1次请求 | 10,720 | - |
| 第2次请求 | 530 | 97.6% |
| 第3次请求 | 326 | 98.5% |
| 第4次请求 | 162 | 98.9% |

**效果总结**：
- Prompt 从 10K 压缩到 162 tokens（**节省 ~98%**）
- 缓存相似度高达 98.9%
- DCP 自动执行去重、清除错误、压缩历史
- 界面显示：`▣ DCP | ~3K tokens saved total`

### 工作原理

#### 工具
- **Distill** - 将关键内容提炼成摘要后删除原始内容
- **Compress** - 将大段对话压缩成单个摘要
- **Prune** - 删除已完成或冗余的工具内容

#### 自动策略
- **Deduplication** - 去除重复的工具调用（如多次读取同一文件）
- **Supersede Writes** - 删除已被后续读取覆盖的写操作内容
- **Purge Errors** - 4 轮后删除错误工具的输入内容

### 注意事项

- DCP 对子代理 (subagents) 禁用
- 压缩会改变消息内容，影响 Prompt 缓存命中
- 适合按请求计费的 Provider（如 GitHub Copilot、Google Antigravity）
