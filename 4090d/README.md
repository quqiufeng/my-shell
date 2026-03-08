# AI 脚本工具集

本目录包含模型编译、推理服务和 AI 生图的脚本工具。

---

## 目录结构

```
/opt/
├── llama.cpp/              # LLM 推理引擎
├── stable-diffusion.cpp/  # 图像生成引擎
├── SenseVoice.cpp/        # 语音识别引擎
├── CosyVoice/             # 语音合成 (TTS)
├── gguf/
│   ├── image/             # Z-Image 生图模型
│   ├── qwen2.5-coder-32b-instruct-q4_k_m.gguf
│   ├── Qwen3.5-9B-Q6_K.gguf
│   └── QwQ-32B-Q4_K_M.gguf
├── models/
│   └── sense-voice-gguf/ # 语音识别模型
└── *.sh                   # 脚本文件
```

---

## ExLLamaV2 框架介绍

ExLLamaV2 是一个高效的 LLM 推理框架，基于 EXL2 量化格式：

- **EXL2 量化格式**: 支持 1-8bpw 量化，大幅减少显存占用
- **投机采样 (Speculative Decoding)**: 使用小模型预测多个 token，主模型验证/修正，大幅提升推理速度
- **Flash Attention**: 支持 Flash Attention 2.5.7+ 加速
- **Paged Attention**: 高效管理 KV Cache
- **自动内存分配**: 支持 GPU 自动分割模型

---

## ✅ 已完成

### 1. 编译脚本

| 脚本 | 功能 |
|------|------|
| `build_llama_cpp.sh` | 编译 llama.cpp (LLM 推理) |
| `build_sd_cpp.sh` | 编译 stable-diffusion.cpp (图像生成) |
| `build_sense_voice.sh` | 编译 SenseVoice.cpp (语音识别) |

---

### 2. LLM 推理服务

| 脚本 | 模型 | 路径 | 功能 | 性能 |
|------|------|------|------|------|
| `run_qwen2.5-coder32b_api.sh` | Qwen2.5-Coder 32B | `/opt/gguf/qwen2.5-coder-32b-instruct-q4_k_m.gguf` | 代码生成/补全/调试 | ~40 tokens/s |
| `run_qwen3.5-9b_api.sh` | Qwen3.5-9B | `/opt/gguf/Qwen3.5-9B-Q6_K.gguf` | 通用对话 | ~94 tokens/s |
| `run_qwq32b_api.sh` | QwQ-32B | `/opt/gguf/QwQ-32B-Q4_K_M.gguf` | 推理/数学/代码（带思考能力） | ~20 tokens/s |
| `run_qwen2.5-coder-32b_exl2.py` | **Qwen2.5-Coder 32B EXL2** | `/opt/gguf/exl2_4_0` | 代码生成 (投机采样+FlashAttention) | **~175 tokens/s** |

**⚠️ 重要：安装 FlashAttention (显著提升性能 50%+)**

```bash
# 首次编译 FlashAttention (针对 RTX 4090D)
bash /opt/my-shell/4090d/build_flash_attention.sh

# 验证安装
python3 -c "import flash_attn; print(f'FlashAttention 版本: {flash_attn.__version__}')"
```

**端口**: 全部为 11434

---

### 🚀 性能优化历程 (4090D 单卡极限优化)

| 阶段 | 配置 | 速度 | 优化说明 |
|------|------|------|----------|
| 初始 | 4bit + 投机2 | ~50 tok/s | 基础配置 |
| 优化1 | 4bit + 投机4 | ~100 tok/s | 增加投机步数 |
| 优化2 | 4bit + 投机4 + FlashAttention | ~164 tok/s | 编译安装FA2 |
| **优化3** | **4bit + 投机6 + FlashAttention** | **~175 tok/s** | 极限配置 |

**优化要点**:
1. **FlashAttention 2.8.3** - 针对4090D(8.9)架构编译，显存带宽优化
2. **NUM_SPECULATIVE_TOKENS=6** - 投机采样步数从2提升到6
3. **显式配置** - `no_flash_attn=False`, `no_sdpa=False`

**硬件**: RTX 4090D 24GB | **显存**: 21.4GB / 24GB

---

### ExLLamaV2 API 服务 (run_qwen2.5-coder-32b_exl2.py)

基于 exllamav2 框架的 Qwen2.5-Coder-32B 推理服务，支持投机采样加速。

#### 硬件配置

- GPU: RTX 4090 D (24GB VRAM)
- 主模型: Qwen2.5-Coder-32B (4.0bpw EXL2)
- 草稿模型: Qwen2.5-Coder-0.5B (32K)

#### 启动方式

```bash
# 使用 nohup 启动
nohup python3 /opt/my-shell/4090d/run_qwen2.5-coder-32b_exl2.py > /tmp/api.log 2>&1 &

# 或使用后台运行
python3 /opt/my-shell/4090d/run_qwen2.5-coder-32b_exl2.py &
```

#### 核心参数

| 参数 | 值 | 说明 |
|------|-----|------|
| MAIN_MODEL_DIR | /opt/gguf/exl2_4_0 | 主模型路径 (32B) |
| DRAFT_MODEL_DIR | /opt/gguf/Qwen2.5-Coder-0.5B-exl2 | 草稿模型路径 (0.5B) |
| MAX_SEQ_LEN | 32768 | 最大上下文长度 (32K) |
| NUM_SPECULATIVE_TOKENS | 2 | 投机采样步数 |
| PORT | 11434 | 服务端口 |

#### 访问地址

启动后会输出：
- 对内地址: `http://localhost:11434`
- 对外地址: `http://{instance_id}-11434.container.x-gpu.com/v1/chat/completions`

#### API 调用

```bash
# 非流式调用
curl -X POST http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "用Python写快速排序"}],
    "max_tokens": 2048
  }'

# 流式调用
curl -N -X POST http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "用Python写快速排序"}],
    "max_tokens": 2048,
    "stream": true
  }'
```

#### 性能数据

10个中等难度Python编程任务测试结果：

| 任务 | chars/s |
|------|---------|
| LRU缓存类 | 150 |
| 线程安全单例 | 179 |
| 生产者消费者 | 165 |
| 斐波那契装饰器 | 280 |
| 二叉搜索树 | 125 |
| 事件总线 | 274 |
| 对象池 | 163 |
| 优先级队列 | 79 |
| 依赖注入容器 | 95 |

**平均速度: ~150-160 chars/s (约 75-80 tokens/s)**

#### 停止服务

```bash
pkill -f run_qwen2.5-coder-32b_exl2
```

---

### 3. AI 生图

| 脚本 | 功能 |
|------|------|
| `img.sh` | Z-Image Turbo 文生图 |
| `upscale.sh` | ESRGAN 超分辨率放大 (2x/4x) |
| `upscale_hires.sh` | Kohya Hires.fix 高清放大 (2x + 锐化) |

**模型文件** (`/opt/gguf/image/`):

| 文件 | 功能------|
| ` |
|------|z_image_turbo-Q8_0.gguf` | 图像生成主模型 |
| `ae.safetensors` | VAE 编码器 |
| `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` | 文本编码器 |

**性能**: 1920x1080 分辨率约 17秒/张

---

### 图像放大 (upscale.sh / upscale_hires.sh)

#### 1. upscale.sh - ESRGAN 超分辨率放大

基于 ESRGAN (Enhanced Super-Resolution GAN) 深度学习超分辨率算法，能同时恢复细节和提升分辨率。

**使用方法:**
```bash
./upscale.sh <input_image> [output_image] [scale]
```

**参数说明:**
| 参数 | 说明 | 默认值 |
|------|------|--------|
| input_image | 输入图片路径 | (必填) |
| output_image | 输出图片路径 | `<input>_upscaled.png` |
| scale | 放大倍数 (2 或 4) | 2 |

**示例:**
```bash
./upscale.sh image.png              # 2x 放大
./upscale.sh image.png out.png      # 2x 放大, 指定输出
./upscale.sh image.png out.png 4    # 4x 放大
```

**性能参考 (3080 10GB):**
| 输入 | 输出 | 耗时 |
|------|------|------|
| 1280x720 | 2560x1440 (2x) | ~16秒 |
| 640x360 | 1280x720 (2x) | ~4.5秒 |
| 640x360 | 2560x1440 (4x) | ~5秒 |

**模型选择:**
| 模型 | 特点 | 推荐场景 |
|------|------|----------|
| 2x ESRGAN | 细节保留好 | 人像、产品 |
| 4x UltraSharp | 速度快 | 快速放大 |

---

#### 2. upscale_hires.sh - Kohya Hires.fix 高清放大

结合 img2img 重绘和 ESRGAN 锐化的两步放大方式，效果更好但耗时较长。

**使用方法:**
```bash
./upscale_hires.sh <input_image> [output] [strength] [steps]
```

**参数说明:**
| 参数 | 说明 | 默认值 |
|------|------|--------|
| input_image | 输入图片路径 | (必填) |
| output | 输出图片路径 | `<input>_hires_2x.png` |
| strength | 重绘幅度 (0.1-0.8) | 0.4 |
| steps | 步数 | 12 |

**示例:**
```bash
./upscale_hires.sh image.png                    # 2x 放大
./upscale_hires.sh image.png out.png 0.4 12    # 重绘0.4, 12步
./upscale_hires.sh image.png out.png 0.3 8    # 快速模式
```

**放大原理:**
- Step 1: img2img 放大 (2x) - 在 latent space 进行去噪重绘
- Step 2: ImageMagick 锐化 - USM 锐化增强清晰度

**参数推荐:**
| 场景 | strength | steps | 耗时 |
|------|----------|-------|------|
| 人像保真 | 0.3 | 8-12 | ~5分钟 |
| 人像精细 | 0.4 | 12 | ~7分钟 |
| 风景重绘 | 0.4-0.5 | 12-16 | ~7分钟 |

**输入输出示例:**
| 输入尺寸 | 输出尺寸 | 放大倍数 |
|----------|----------|----------|
| 640x360 | 1280x720 | 2x |
| 1280x720 | 2560x1440 | 2x |
| 1920x1080 | 3840x2160 | 2x |

**注意:** 需要较强显卡 (建议 16GB+ 显存)，1280x720 输入约 7分钟

---

---

### 4. 语音识别 (SenseVoice)

| 脚本 | 功能 |
|------|------|
| `run_sense_voice.sh` | 语音转文字 |

**模型** (`/opt/models/sense-voice-gguf/`):

| 文件 | 功能 | 性能 |
|------|------|------|
| `sense-voice-small-q4_k.gguf` | 语音识别（支持中文、英文、日语、韩语、粤语） | RTF 0.06（16倍速实时） |

**用途**: 将音频文件转换为文字，支持多语言识别

---

### 5. 语音合成 (CosyVoice) ✅ 支持声音克隆

| 脚本 | 功能 |
|------|------|
| `run_tts.sh` | Edge TTS (在线) |
| `run_cosy_voice.sh` | CosyVoice (本地) |

**模型**:

| 模型 | 路径 | 功能 | 性能 |
|------|------|------|------|
| CosyVoice-300M-SFT | `/opt/CosyVoice/pretrained_models/CosyVoice-300M-SFT` | 预设音色合成（7种） | ~3-5秒/句 |
| Fun-CosyVoice3-0.5B | `/opt/CosyVoice/pretrained_models/Fun-CosyVoice3-0.5B` | 零样本声音克隆 | ~3-5秒/句 |

---

## CosyVoice 详解

### 1. 可用模型

#### CosyVoice-300M-SFT
- **路径**: `/opt/CosyVoice/pretrained_models/CosyVoice-300M-SFT`
- **功能**: 预设音色合成（不可克隆声音）
- **预设音色**: 中文女、中文男、日语男、粤语女、英文女、英文男、韩语女

#### Fun-CosyVoice3-0.5B
- **路径**: `/opt/CosyVoice/pretrained_models/Fun-CosyVoice3-0.5B`
- **功能**: 零样本声音克隆
- **支持**: 只需 3-30 秒音频即可克隆任意声音，支持中文、英文、日语、粤语、韩语

---

### 2. 运行 example.py 测试

```bash
# 激活环境
conda activate cosyvoice2

# 进入目录
cd /opt/CosyVoice

# 运行测试
python example.py
```

运行后会生成以下音频文件在 `/opt/CosyVoice/` 目录下：

| 文件名 | 功能说明 |
|--------|----------|
| `sft_0.wav` | SFT 预设音色合成（中文女） |
| `sft_fast_0.wav` | SFT 速度调节 - 快速 (1.5x) |
| `sft_slow_0.wav` | SFT 速度调节 - 慢速 (0.7x) |
| `zero_shot_0.wav` | 零样本声音克隆 |
| `fine_grained_control_0.wav` | 细粒度控制（呼吸声） |
| `instruct_0.wav` | 指令控制（粤语） |
| `instruct2_0.wav` | 指令控制（快速语速） |
| `hotfix_0.wav` | 发音修正（多音字） |
| `japanese_0.wav` | 日语合成 |
| `speed_fast_0.wav` | 零样本克隆 + 快速 (1.5x) |
| `speed_slow_0.wav` | 零样本克隆 + 慢速 (0.7x) |

---

### 3. example.py 每个例子详细功能

#### 用到的音频文件 (`/opt/CosyVoice/asset/`)

| 文件 | 用途 |
|------|------|
| `zero_shot_prompt.wav` | 参考音频（用于克隆声音）- 时长约 3-30 秒的人声 |
| `cross_lingual_prompt.wav` | 跨语言参考音频 |

---

#### 例子 1: cosyvoice_example() - SFT 预设音色合成

**模型**: CosyVoice-300M-SFT

**功能**: 使用预设的音色合成语音，无需参考音频

**代码**:
```python
cosyvoice = AutoModel(model_dir='/opt/CosyVoice/pretrained_models/CosyVoice-300M-SFT')
print(cosyvoice.list_available_spks())  # 打印可用音色
cosyvoice.inference_sft('文本', '音色名称')
```

**可用的预设音色**:
- `中文女`、`中文男`
- `日语男`
- `粤语女`
- `英文女`、`英文男`
- `韩语女`

**生成的音频**: `sft_0.wav`
- 输入文本: "你好，我是通义生成式语音大模型，请问有什么可以帮您的吗？"
- 使用音色: 中文女

---

#### 例子 2: cosyvoice3_example() - Fun-CosyVoice3-0.5B

**模型**: Fun-CosyVoice3-0.5B

该模型支持以下 6 种功能：

---

##### 2.1 零样本声音克隆 (zero_shot)

**功能**: 提供一段参考音频，克隆该声音来说任意文本

**代码**:
```python
cosyvoice.inference_zero_shot('要说的文本', '提示词文本', '参考音频路径')
```

**生成的音频**: `zero_shot_0.wav`
- 输入文本: "八百标兵奔北坡，北坡炮兵并排跑，炮兵怕把标兵碰，标兵怕碰炮兵炮。"
- 参考音频: `zero_shot_prompt.wav`（用这个人的声音来说上面的绕口令）

---

##### 2.2 细粒度控制 (fine_grained_control / cross_lingual)

**功能**: 通过特殊标签控制语音细节，如添加呼吸声、停顿等

**支持的标签**:
- `[breath]` - 呼吸声
- `<|zh|>` - 中文
- `<|en|>` - 英文
- `<|ja|>` - 日语
- `<|yue|>` - 粤语
- `<|ko|>` - 韩语

**生成的音频**: `fine_grained_control_0.wav`
- 输入文本: "You are a helpful assistant.[breath]因为他们那一辈人[breath]在乡里面住的要习惯一点..."
- 效果: 在指定位置添加呼吸声

---

##### 2.3 指令控制 - 粤语 (instruct)

**功能**: 用自然语言描述想要的说话方式，模型会自动调整

**代码**:
```python
cosyvoice.inference_instruct2('文本', '指令', '参考音频')
```

**生成的音频**: `instruct_0.wav`
- 输入文本: "好少咯，一般系放嗰啲国庆啊，中秋嗰啲可能会咯。"（普通话）
- 指令: "请用广东话表达"
- 效果: 用粤语说出来

---

##### 2.4 指令控制 - 语速 (instruct)

**生成的音频**: `instruct2_0.wav`
- 输入文本: "收到好友从远方寄来的生日礼物..."
- 指令: "请用尽可能快地语速说一句话"
- 效果: 快速说出来

---

##### 2.5 发音修正 (hotfix / zero_shot)

**功能**: 修正多音字、轻声等发音

**特殊语法**: `[字][拼音]` - 指定单个字的读音

**生成的音频**: `hotfix_0.wav`
- 输入文本: "高管也通过电话、短信、微信等方式对报道[j][ǐ]予好评。"
- `[j][ǐ]` 表示"纪"字读"己"(jǐ)而不是"技"(jì)

---

##### 2.6 日语合成 (japanese / cross_lingual)

**功能**: 合成日语语音

**注意**: 日语文本需要用**片假名**输入，不能用汉字或平假名

**生成的音频**: `japanese_0.wav`
- 输入文本: 片假名日语文本
- 效果: 用日语说出来

---

##### 2.7 速度调节 (Speed Control)

**功能**: 调节语音语速

**参数**: `speed`
- `1.0` - 正常速度
- `0.5-1.0` - 慢速
- `1.0-2.0` - 快速

**SFT 速度调节**:
```python
# 快速
cosyvoice.inference_sft('文本', '中文女', speed=1.5)
# 慢速
cosyvoice.inference_sft('文本', '中文男', speed=0.7)
```

**Zero-Shot 速度调节**:
```python
# 注意：Fun-CosyVoice3 需要长文本 + <|endofprompt|> 标记
cosyvoice.inference_zero_shot(
    '长文本...',
    'You are a helpful assistant.<|endofprompt|>提示词',
    '参考音频.wav',
    speed=1.5
)
```

**生成的音频**: 
- `sft_fast_0.wav`, `sft_slow_0.wav` (SFT 模型)
- `speed_fast_0.wav`, `speed_slow_0.wav` (Fun-CosyVoice3 模型)

---

##### 2.8 保存声纹 (Save Speaker Profile)

**功能**: 保存克隆的声纹，供下次直接使用，无需再次提供参考音频

**代码**:
```python
# 保存声纹
cosyvoice.add_zero_shot_spk('提示词文本', '参考音频.wav', '声纹ID')
cosyvoice.save_spkinfo()  # 保存到文件

# 下次使用
cosyvoice.inference_zero_shot(
    '要说的文本', 
    '',  # 不需要提示词
    '',  # 不需要参考音频
    zero_shot_spk_id='声纹ID'  # 使用保存的声纹ID
)
```

---

##### 2.9 随机种子 (Reproducibility)

**功能**: 设置随机种子，保证每次生成结果一致

```python
from cosyvoice.utils.common import set_all_random_seed

set_all_random_seed(42)  # 设置种子
cosyvoice.inference_sft('文本', '中文女')  # 每次运行结果相同
```

---

### 4. CosyVoice 实际使用方法

#### 1. 预设音色合成 (SFT) - 最简单

不需要参考音频，直接选择内置音色：

```python
import sys
sys.path.append('/opt/CosyVoice/third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio

# 加载模型
cosyvoice = AutoModel(model_dir='/opt/CosyVoice/pretrained_models/CosyVoice-300M-SFT')

# 查看可用音色
print(cosyvoice.list_available_spks())
# 输出: ['中文女', '中文男', '日语男', '粤语女', '英文女', '英文男', '韩语女']

# 合成语音
for i, j in enumerate(cosyvoice.inference_sft('你好，我是通义生成式语音大模型', '中文女', stream=False)):
    torchaudio.save('output.wav', j['tts_speech'], cosyvoice.sample_rate)
```

---

#### 2. 声音克隆 (Zero-Shot) - 核心功能

只需要 3-30 秒的人声音频即可克隆：

```python
import sys
sys.path.append('/opt/CosyVoice/third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio

# 加载模型
cosyvoice = AutoModel(model_dir='/opt/CosyVoice/pretrained_models/Fun-CosyVoice3-0.5B')

# 声音克隆
# 参数: (要说的文本, 提示词, 参考音频路径)
for i, j in enumerate(cosyvoice.inference_zero_shot(
    '今天天气真好，我们出去走走吧',
    '今天天气真好，我们出去走走吧',  # 提示词文本
    './asset/zero_shot_prompt.wav',  # 参考音频（你要克隆的声音）
    stream=False
)):
    torchaudio.save('cloned_voice.wav', j['tts_speech'], cosyvoice.sample_rate)
```

---

#### 3. 指定语言合成 (跨语言)

用标签指定输出语言：

```python
# 中文
cosyvoice.inference_cross_lingual('<|zh|>今天天气真好', './asset/zero_shot_prompt.wav')
# 英文
cosyvoice.inference_cross_lingual('<|en|>The weather is nice today', './asset/zero_shot_prompt.wav')
# 日语
cosyvoice.inference_cross_lingual('<|ja|>今日はいい天気ですね', './asset/zero_shot_prompt.wav')
# 粤语
cosyvoice.inference_cross_lingual('<|yue|>今日天气几好喔', './asset/zero_shot_prompt.wav')
# 韩语
cosyvoice.inference_cross_lingual('<|ko|>오늘 날씨가 좋네요', './asset/zero_shot_prompt.wav')
```

---

#### 4. 添加呼吸声

```python
# 在文本中插入 [breath] 标签
cosyvoice.inference_cross_lingual(
    '<|zh|>[breath]大家好[breath]今天我们来介绍[breath]一个新的产品',
    './asset/zero_shot_prompt.wav'
)
```

---

#### 5. 指令控制 (控制说话方式)

```python
# 用自然语言描述想要的说话方式
cosyvoice.inference_instruct2(
    '今天天气真好',  # 要说的文本
    '请用悲伤的语气说出来',  # 指令
    './asset/zero_shot_prompt.wav'
)

# 更多指令示例:
# - "请用开心的语气说"
# - "请用愤怒的语气说"
# - "请用温柔的语气说"
# - "请用很快的语速说"
# - "请用很慢的语速说"
# - "请用广东话表达"
# - "请用日语表达"
```

---

#### 6. 发音修正 (多音字)

```python
# 语法: [字][拼音]
# [j][ǐ] 表示"纪"字读"己"而不是"技"

cosyvoice.inference_zero_shot(
    '高管也通过电话对报道[j][ǐ]予好评。',
    '高管也通过电话对报道纪予好评。',
    './asset/zero_shot_prompt.wav'
)
```

---

#### 7. 日语合成 (片假名)

```python
# 日语必须用片假名输入
# 可以用在线工具转换: https://www.kishan.jp/henkan.php

japanese_text = 'レキシ テキ セカイ ニ オイ テ ワ'

cosyvoice.inference_cross_lingual(
    f'<|ja|>{japanese_text}',
    './asset/zero_shot_prompt.wav'
)
```

---

### 5. CosyVoice 安装配置详情

#### 创建 conda 环境
```bash
conda create -n cosyvoice2 python=3.10 -y
conda activate cosyvoice2
```

#### 安装 PyTorch (关键!)
```bash
pip install torch==2.3.1 torchvision==0.18.0 torchaudio==2.3.1 -i https://mirrors.aliyun.com/pypi/simple/
```

#### 安装 CUDA 运行时 (不冲突)
```bash
conda install -c nvidia cuda-runtime=12.1 -y
```

#### 安装依赖包
```bash
# 核心依赖
pip install transformers==4.39.3 huggingface_hub==0.36.2 \
    onnxruntime-gpu openai-whisper \
    hyperpyyaml omegaconf pyarrow pyworld soundfile librosa \
    tqdm modelscope conformer diffusers hydra-core lightning \
    gdown matplotlib wget x-transformers \
    -i https://mirrors.aliyun.com/pypi/simple/

# 官方 requirements.txt (使用 --no-deps 避免冲突)
pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/ --no-deps
```

#### 下载模型
```bash
cd /opt/CosyVoice
python -c "
from modelscope import snapshot_download
snapshot_download('FunAudioLLM/Fun-CosyVoice3-0.5B-2512', local_dir='pretrained_models/Fun-CosyVoice3-0.5B')
snapshot_download('iic/CosyVoice-300M-SFT', local_dir='pretrained_models/CosyVoice-300M-SFT')
"
```

#### 运行测试
```bash
cd /opt/CosyVoice
python example.py
```

**注意：文本需要足够长！至少 10 个字，否则会报错。**

---

## 常用命令

```bash
# 查看 GPU
nvidia-smi

# 生成图片
./img.sh "A beautiful landscape"

# 语音识别
./run_sense_voice.sh audio.wav

# 启动 LLM 服务
./run_qwen3.5-9b_api.sh

# 启动 CosyVoice
conda activate cosyvoice2
cd /opt/CosyVoice && python example.py
```

---

## 性能参考

| 模型 | 功能 | 速度 |
|------|------|------|
| Z-Image Turbo | 文生图 | ~17秒/张 (1920x1080) |
| Qwen2.5-Coder-32B (llama.cpp) | 代码生成 | ~40 tokens/s |
| **Qwen2.5-Coder-32B (exllamav2)** | 代码生成 | **~80 tokens/s** |
| Qwen3.5-9B | 通用对话 | ~94 tokens/s |
| QwQ-32B | 推理/思考 | ~20 tokens/s |
| SenseVoice | 语音识别 | RTF 0.06 (16倍速) |
| CosyVoice | 语音合成 | ~3-5秒/句 |

---

## 所有模型文件汇总

| 类型 | 模型名 | 路径 |
|------|--------|------|
| LLM | Qwen2.5-Coder-32B | `/opt/gguf/qwen2.5-coder-32b-instruct-q4_k_m.gguf` |
| LLM | Qwen3.5-9B | `/opt/gguf/Qwen3.5-9B-Q6_K.gguf` |
| LLM | QwQ-32B | `/opt/gguf/QwQ-32B-Q4_K_M.gguf` |
| 图像 | Z-Image Turbo | `/opt/gguf/image/z_image_turbo-Q8_0.gguf` |
| 图像 | VAE | `/opt/gguf/image/ae.safetensors` |
| 图像 | 文本编码器 | `/opt/gguf/image/Qwen3-4B-Instruct-2507-Q4_K_M.gguf` |
| 语音识别 | SenseVoice-Small | `/opt/models/sense-voice-gguf/sense-voice-small-q4_k.gguf` |
| 语音合成 | CosyVoice-300M-SFT | `/opt/CosyVoice/pretrained_models/CosyVoice-300M-SFT` |
| 语音合成 | Fun-CosyVoice3-0.5B | `/opt/CosyVoice/pretrained_models/Fun-CosyVoice3-0.5B` |

---

## 6. 视频配音 + 字幕

给已有视频添加配音和字幕。

```bash
./video_dub.sh <视频文件> <文案> <参考音频> [输出视频]
```

**参数说明：**
| 参数 | 说明 | 必填 |
|------|------|------|
| 视频文件 | 原视频路径（mp4/avi/mov等） | ✅ |
| 文案 | 要说的内容（用空格分隔） | ✅ |
| 参考音频 | 参考音色音频（3-30秒） | ✅ |
| 输出视频 | 输出视频路径（默认 output.mp4） | ❌ |

**示例：**
```bash
./video_dub.sh video.mp4 '第一句 第二句 第三句' ./voice.wav output.mp4
```

---

## 7. 图片生成视频 + 配音 + 字幕

把多张图片合成视频，支持配音、字幕、转场效果。

```bash
./img_to_video_v1.sh <图片> <每张秒数> <文案> [输出视频]
```

**图片支持：**
| 格式 | 示例 |
|------|------|
| 空格分隔 | `'img1.jpg img2.jpg img3.jpg'` |
| 文件夹 | `'./images/'` 或 `/path/to/folder` |
| HTTP | `'https://xxx.com/1.jpg https://yyy.com/2.jpg'` |

**示例：**
```bash
# v1：文件夹 + 多段文案（用|分隔）
./img_to_video_v1.sh '/opt/story/' 2 '第一句|第二句|第三句' output.mp4
```

**功能：**
- 自动生成配音（SFT预设音色）
- 硬字幕（黄色字白色边框）
- 淡入淡出转场效果

---

### 两个版本的区别

| 版本 | 脚本 | 配音方式 | 适用场景 |
|------|------|----------|----------|
| **v1** | `img_to_video_v1.sh` | SFT预设音色（中文女） | 速度快，稳定 |
| **v2** | `img_to_video_v2.sh` | 声音克隆（需参考音频） | 需要特定音色 |

---

### v1 版本 (img_to_video_v1.sh)

**使用方法：**
```bash
./img_to_video_v1.sh <图片文件夹> <每张秒数> <文案> [输出文件]
```

**参数说明：**
| 参数 | 说明 | 必填 |
|------|------|------|
| 图片文件夹 | 图片所在文件夹路径（完整路径，如 /opt/story/） | ✅ |
| 每张秒数 | 每张图片显示多少秒（建议2-3秒） | ✅ |
| 文案 | 要说的内容（v1用|分隔多段，v2用空格连接） | ✅ |
| 参考音频 | 参考音色音频（v2需要，3-30秒） | v1❌ v2✅ |
| 输出文件 | 输出视频路径（默认 output.mp4） | ❌ |

**文案格式：**
```
# v1多段文案：用 | 分隔，每段对应一张图片
'第一句|第二句|第三句|第四句|...'

# v2整段文案：用空格连接（不是|）
'第一句 第二句 第三句 第四句 ...'
```

**示例：**
```bash
# 10张图片，2秒/张
./img_to_video_v1.sh '/opt/story/' 2 '古时候有个贫困的书生名叫匡衡|他家里很穷晚上买不起油灯|但他依然想尽办法要坚持读书|他发现邻居家的灯光可以从墙缝透过来|于是他在墙上钻了一个小孔借光读书|就是这样他每天借着那微弱的光线苦读|无论严寒酷暑他都坚持不懈|功夫不负有心人他终于学有所成|后来匡衡做了齐国的宰相|这就是照壁借光的由来' output.mp4
```

---

### v2 版本 (img_to_video_v2.sh)

**使用方法：**
```bash
./img_to_video_v2.sh <图片文件夹> <每张秒数> <文案> <参考音频> [输出文件]
```

**参数说明：**
| 参数 | 说明 | 必填 |
|------|------|------|
| 图片文件夹 | 图片所在文件夹路径（完整路径，如 /opt/story/） | ✅ |
| 每张秒数 | 每张图片显示多少秒（建议2-3秒） | ✅ |
| 文案 | 完整文案（用空格连接，不是\|） | ✅ |
| 参考音频 | 参考音色音频（3-30秒，用于克隆声音） | ✅ |
| 输出文件 | 输出视频路径（默认 output.mp4） | ❌ |

**注意：**
- v2每段文案需要≥10个字
- v2生成较慢（每段单独调用模型）
- **⚠️ 修复：Fun-CosyVoice3对短文本会生成异常音频(0.08秒)，解决方案：使用inference_instruct2 + tts_text前加换行符**

**示例：**
```bash
# 10张图片，2秒/张，声音克隆
./img_to_video_v2.sh '/opt/story/' 2 '古时候有个贫困的书生名叫匡衡他家里很穷晚上买不起油灯...' /opt/CosyVoice/asset/zero_shot_prompt.wav output.mp4
```

---

### 相关文件

| 文件 | 说明 |
|------|------|
| `/opt/img_to_video_v1.sh` | 图片转视频 v1（SFT预设音色） |
| `/opt/img_to_video_v2.sh` | 图片转视频 v2（声音克隆） |
| `/opt/video_dub.sh` | 视频配音字幕脚本 |
| `/opt/img.sh` | AI图片生成脚本 |

---

## OpenCode 提示词

### 提示词1：生成图片

请帮我生成10张"照壁借光"成语故事图片：

- 分辨率：1080x1920（竖屏）
- 风格：中国古风水墨画漫画风格
- 保存到 /opt/story/ 目录（img1.png - img10.png）
- 10张图片提示词：
  1. 古代贫困书生的简陋茅草屋，室内昏暗
  2. 深夜书房少年专注阅读古书
  3. 古代书生沉思表情
  4. 古代土墙钻孔月光透入
  5. 微弱光线透过小孔书生借光读书
  6. 寒冬夜晚雪花飘飞借光勤奋攻读
  7. 日出时分书生勤奋攻读
  8. 科举放榜书生中榜喜报传来
  9. 古代官员身着官服意气风发
  10. 照壁借光四个大字书法古代书房

执行命令示例：
```bash
./img.sh "中国古风水墨画风格漫画，古代贫困书生的简陋茅草屋" 1080 1920 /opt/story/img1.png
# ... 重复10次
```

---

### 提示词2：用 v2 脚本生成视频（声音克隆版）

请帮我用 img_to_video_v2.sh 脚本生成"照壁借光"短视频：

- 图片文件夹：/opt/story/
- 每张图片：2秒
- 10段文案（用|分隔，每段对应一张图片）：
  ```
  古时候有个贫困的书生名叫匡衡|他家里很穷晚上买不起油灯|但他依然想尽办法要坚持读书|他发现邻居家的灯光可以从墙缝透过来|于是他在墙上钻了一个小孔借光读书|就是这样他每天借着那微弱的光线苦读|无论严寒酷暑他都坚持不懈|功夫不负有心人他终于学有所成|后来匡衡做了齐国的宰相|这就是照壁借光的由来
  ```
- 参考音色：/opt/CosyVoice/asset/zero_shot_prompt.wav
- 输出：/opt/tmp/zhao_bi.mp4
| `/opt/CosyVoice/asset/zero_shot_prompt.wav` | 示例参考音频 |

---

## 8. 调试记录：v1/v2 问题与修复

### 问题1：Fun-CosyVoice3 短文本生成异常音频（0.08秒）

**现象**：Fun-CosyVoice3 模型对短文本（<10字）生成的音频只有 0.08 秒，异常短。

**原因**：模型内部处理短文本时出现 bug。

**解决方案**（很诡异的方法）：
1. 使用 `inference_instruct2` 代替 `inference_zero_shot`
2. 在 `tts_text` 前加换行符 `\n`，物理上分隔指令 token 和文本

**修复代码**（img_to_video_v2.sh）：
```python
# 修复前（会生成0.08秒异常音频）
for j in cosyvoice.inference_zero_shot(tts_text, prompt, prompt_wav, stream=False):

# 修复后（正常）
prompt = '<|endofprompt|>'  # prompt_text 改为空
tts_text = '\n' + text      # tts_text 前加换行符
for j in cosyvoice.inference_instruct2(tts_text, prompt, prompt_wav, stream=False):
```

---

### 问题2：字幕/配音/视频时间线不同步

**现象**：字幕和配音时间对不上。

**原因**：各部分计算的停顿时间不一致。

**解决方案**：统一时间计算逻辑
- **字幕**：配音时长 + 0.3秒停顿
- **视频片段**：配音时长 + 0.3秒停顿
- **音频**：每段末尾加 0.3秒静音 (`apad=pad_dur=0.3`)

这样三者总时长一致，时间线同步。

---

### 问题3：v1 和 v2 的优化参数

| 版本 | 模型 | 优化参数 |
|------|------|----------|
| v1 | CosyVoice-300M-SFT | `load_jit=True, load_trt=True, fp16=True` |
| v2 | Fun-CosyVoice3-0.5B | `load_trt=True, fp16=True` |

**注意**：Fun-CosyVoice3 不支持 jit，只支持 TensorRT。

---

### 测试命令

```bash
# v1 测试（SFT预设音色）
time /opt/img_to_video_v1.sh '/opt/image/' 2 '古时候有个贫困的书生名叫匡衡|他家里很穷晚上买不起油灯|但他依然想尽办法要坚持读书|他发现邻居家的灯光可以从墙缝透过来|于是他在墙上钻了一个小孔借光读书|就是这样他每天借着那微弱的光线苦读|无论严寒酷暑他都坚持不懈|功夫不负有心人他终于学有所成|后来匡衡做了齐国的宰相|这就是凿壁借光的由来' /opt/tmp/kanbiao_v1.mp4

# v2 测试（声音克隆）
time /opt/img_to_video_v2.sh '/opt/image/' 2 '古时候有个贫困的书生名叫匡衡|他家里很穷晚上买不起油灯|但他依然想尽办法要坚持读书|他发现邻居家的灯光可以从墙缝透过来|于是他在墙上钻了一个小孔借光读书|就是这样他每天借着那微弱的光线苦读|无论严寒酷暑他都坚持不懈|功夫不负有心人他终于学有所成|后来匡衡做了齐国的宰相|这就是凿壁借光的由来' /opt/CosyVoice/asset/zero_shot_prompt.wav /opt/tmp/kanbiao_v2.mp4
```
