#!/bin/bash
set -euo pipefail
#
# =============================================================
# Gemma 4 12B IT (llama.cpp) API 启动脚本 (RTX 3080 20GB)
# =============================================================
#
# 【模型主页】https://huggingface.co/unsloth/gemma-4-12b-it-GGUF
#
# 【模型介绍】
#   Gemma 4 12B 是 Google DeepMind 发布的第四代 Gemma 系列通用模型
#   基础模型: google/gemma-4-12B-it, Architecture: gemma4 (dense)
#
#   --- 架构参数 ---
#   - 总参数: 11.95B
#   - 层数: 48
#   - 注意力: 混合机制 (sliding window 1024 + 全局 attention, 末层总是全局)
#   - Heads: 16
#   - Embedding: 3840
#   - Feed Forward: 15360
#   - 词表: 262K
#   - 上下文: 131072 tokens (128K, gemma4.context_length)
#   - RoPE: Proportional RoPE (p-RoPE)
#   - KV cache 优化: 全局层 Unified Keys/Values
#
#   --- 多模态 (Encoder-Free Unified) ---
#   - Text: ✅ 原生
#   - Image: ✅ 任意宽高比, 变分辨率 (70/140/280/560/1120 token 预算)
#   - Audio: ✅ ASR + 翻译, 最长 30 秒
#   - Video: ✅ 帧序列, 最长 60 秒 (1fps)
#   - 架构: encoder-free, 图像块和音频波形直接通过线性层投影到 LLM embedding 空间
#   - 单个 decoder-only transformer 处理所有模态
#
#   --- 核心能力 ---
#   - 推理: 高度可配置思考模式 (<|think|> token)
#   - 长上下文: 128K 原生
#   - 工具调用: ✅ 原生 function calling, 支持 agent 工作流
#   - 代码: 显著提升 (LiveCodeBench v6 72.0%, Codeforces ELO 1659)
#   - 多语言: 35+ 主流语言, 140+ 训练语言
#   - system role: ✅ 原生支持 (与 Gemma 3 不同, 之前不支持 system)
#   - 思考: 内置推理, 先思考后回答
#
#   --- 量化版本 (Unsloth Dynamic 2.0) ---
#   - 2-bit: UD-IQ2_M 4.21GB, UD-Q2_K_XL 4.66GB
#   - 3-bit: UD-IQ3_XXS 4.64GB, Q3_K_S 5.14GB, Q3_K_M 5.69GB, UD-Q3_K_XL 6.02GB
#   - 4-bit: IQ4_XS 6.38GB, Q4_K_S 6.76GB, IQ4_NL 6.72GB, Q4_0 6.74GB,
#           Q4_1 7.4GB, Q4_K_M 7.12GB, UD-Q4_K_XL 7.37GB
#   - 5-bit: Q5_K_S 8.2GB, Q5_K_M 8.41GB, UD-Q5_K_XL 8.61GB
#   - 6-bit: Q6_K 9.79GB, UD-Q6_K_XL 10.7GB
#   - 8-bit: Q8_0 12.7GB, UD-Q8_K_XL 13.6GB
#   - 16-bit: BF16 23.8GB
#   - 本仓库使用: Q4_K_M (7.12GB, 质量/大小最佳平衡)
#
#   --- 评估亮点 (与 Gemma 3 27B 对比) ---
#   MMLU Pro:        77.2%  (Gemma 3 27B: 67.6%, +9.6%)
#   AIME 2026:       77.5%  (Gemma 3 27B: 20.8%, +56.7%)
#   LiveCodeBench:   72.0%  (Gemma 3 27B: 29.1%, +42.9%)
#   GPQA Diamond:    78.8%  (Gemma 3 27B: 42.4%, +36.4%)
#   Tau2 (avg):      69.0%  (Gemma 3 27B: 16.2%, +52.8%)
#   Codeforces ELO:  1659   (Gemma 3 27B: 110,   +1549)
#   BigBench EH:     53.0%  (Gemma 3 27B: 19.3%, +33.7%)
#   MMMU Pro:        69.1%  (Gemma 3 27B: 49.7%, +19.4%)
#   MRCR 128K:       43.4%  (Gemma 3 27B: 13.5%, +29.9%)
#
#   --- 训练数据 ---
#   - 来源: Web 文档 (140+ 语言) + 代码 + 数学 + 图像 + 音频
#   - 截止日期: 2025 年 1 月
#   - 过滤: CSAM + 敏感数据 + 内容质量
#
#   --- 用途建议 ---
#   - 内容创作: 文本生成、对话、摘要、图像理解、音频处理
#   - 研究: NLP/VLM 实验
#   - 教育: 语言学习
#   - 智能体: function calling, 工具使用, 自主任务执行
#
#   --- 限制 ---
#   - 训练数据偏差: 反映训练语料中的社会文化偏差
#   - 长上下文/复杂任务: 性能随复杂度下降
#   - 事实准确性: 可能生成过时或错误的事实
#   - 语言歧义: 难以处理讽刺、比喻等细微差异
#
#   --- 许可证 ---
#   Apache 2.0 (可商用, 详见 https://ai.google.dev/gemma/docs/gemma_4_license)
#   作者: Google DeepMind
#   基础模型: https://huggingface.co/google/gemma-4-12B
#
# 【本仓库 GGUF 文件说明】
#   /data/models/gemma-4-12b-it-Q4_K_M.gguf (7.12GB)
#   - 纯文本版本 (无 mmproj, 不支持 vision/audio 多模态)
#   - 用于 chat/code/agent 等文本任务
#   - 如需多模态, 需下载 mmproj 文件 (单独)
#
# 【量化版本】(RTX 3080 20GB 推荐)
#   - Q4_K_M: 7.12GB (推荐, 留足显存用于 KV cache)
#   - Q5_K_M: 8.41GB (质量更好)
#   - Q6_K:   9.79GB (高质量)
#   - Q8_0:   12.7GB  (20GB 紧张, 不推荐)
#
# 【基准测试数据】(2026-06-04, test_api.py 19题算法题, max_tokens=1024)
# ┌─────────────┬──────────┬────────────┬──────────────────────────────┐
# │ 上下文大小  │ 平均速度 │ 总token数  │ 备注                         │
# ├─────────────┼──────────┼────────────┼──────────────────────────────┤
# │ 128K        │ 65.3     │ 30720      │ batch=512, threads=6,        │
# │             │ tok/s    │            │ cache-type-k/v=q4_0, fa=on   │
# └─────────────┴──────────┴────────────┴──────────────────────────────┘
# 速度范围: 59.8 - 67.1 tok/s (非常稳定)
# 总耗时: 470.40s (19题 × ~1024 tokens)
# 测试环境: NVIDIA GeForce RTX 3080 20GB, CUDA compute 8.6
# 模型: gemma-4-12b-it-Q4_K_M.gguf
# 对比: Qwen3-14B-Q4_K_M.gguf 128K 59.3 tok/s, Gemma 4 12B 快 ~10%
# =============================================================
#
# 【上下文配置】(RTX 3080 20GB)
#   - 128K: 推荐, 模型 ~7.12GB + KV cache (q4_0) ~1.5GB = ~8.6GB, 余量 ~11GB
#   - 如果不开启 KV cache 量化, 128K 会需要 ~12GB KV cache, 紧张
# 【降级建议】(若启动时 OOM)
#   - 将 -c 131072 降为 65536 (64K) 或 32768 (32K)
#   - 关闭浏览器/视频播放器等显存占用程序
#
# 【优化要点】
#   - ctx-size: 131072 (128K, 3080 20GB 跑 7.12GB 模型极限值, 依赖KV cache量化)
#   - batch-size: 512 (保守值, 降低显存压力)
#   - ubatch-size: 512
#   - flash-attn on: 必须开启, 大幅降低长文本显存压力并提升速度
#   - threads: 6 (匹配 3500X 6核)
#   --parallel 1 --slots 1: 减少slot开销
#   --prio 2: 高优先级
#   --mlock + --no-mmap
#   --no-warmup: 跳过启动warmup, 大幅缩短启动时间
#   --cache-type-k/v: q4_0 (核心省显存参数, 20GB 跑 128K 的关键)
#   --temp 1.0: Gemma 4 推荐温度
#   --top-p 0.95
#   --top-k 64: Gemma 4 推荐值
#   --min-p 0
#
# 【思考模式切换】(Gemma 4 特性)
#   通过 system prompt 中的 <|think|> token 控制:
#   - 含 <|think|>: 启用思考, 模型先推理再回答
#   - 不含 <|think|>: 禁用思考, 直接回答
#
#   llama-server /v1/chat/completions 启用思考示例:
#   {"messages": [
#     {"role": "system", "content": "<|think|>\nYou are a helpful assistant."},
#     {"role": "user",   "content": "计算 123 * 456"}
#   ]}
#
#   禁用思考:
#   {"messages": [
#     {"role": "system", "content": "You are a helpful assistant."},
#     {"role": "user",   "content": "你好"}
#   ]}
#
# 【多模态支持】(本 GGUF 暂不支持, 需要 mmproj)
#   llama-server 多模态启动需加:
#     --mmproj /path/to/mmproj.gguf
#   当前本地 GGUF 仅有文本, 不支持图像/音频输入
# =============================================================
#
# 【启动方式】(必须用 setsid，否则终端关闭会终止服务)
#   cd /opt/my-shell/3080
#   setsid nohup ./gemma-4-12b_llama.sh > /tmp/gemma-4-12b_llama.log 2>&1 < /dev/null &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/gemma-4-12b_llama.log
#
# 【停止服务】
#   pkill -f "llama-server.*gemma-4-12b"
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#
#   # 基础对话 (禁用思考)
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "gemma-4-12b-it-Q4_K_M.gguf",
#       "messages": [
#         {"role": "system", "content": "You are a helpful assistant."},
#         {"role": "user", "content": "你好"}
#       ],
#       "max_tokens": 100
#     }'
#
#   # 思考模式测试
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "gemma-4-12b-it-Q4_K_M.gguf",
#       "messages": [
#         {"role": "system", "content": "<|think|>\nYou are a helpful assistant."},
#         {"role": "user", "content": "计算 123 * 456"}
#       ],
#       "max_tokens": 1024
#     }'
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/gemma-4-12b-it-Q4_K_M.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "gemma-4-12b-it-Q4_K_M.gguf": {
#           "name": "Gemma 4 12B IT Q4_K_M (3080 20GB)",
#           "maxContextWindow": 131072,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/gemma-4-12b-it-Q4_K_M.gguf
#
# =============================================================

# 快速环境检查
if ! command -v nvidia-smi &> /dev/null; then
    echo "警告: nvidia-smi 未找到, 请确认 CUDA 驱动已安装"
fi
if [[ ! -x "/opt/llama.cpp/build/bin/llama-server" ]]; then
    echo "错误: /opt/llama.cpp/build/bin/llama-server 不存在或不可执行"
    exit 1
fi

export LD_LIBRARY_PATH=/data/cuda/lib64:/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}

# RTX 3080 20GB 显存优化参数
MODEL_DIR="/data/models/gemma-4-12b-it-Q4_K_M.gguf"
LLAMA_SERVER="/opt/llama.cpp/build/bin/llama-server"

# RTX 3080 12B 模型参数 (20GB 显存, 128K 上下文)
NGL=99              # GPU层数 (全部加载到GPU)
CTX=131072          # 上下文 128K (3080 20GB 跑 7.12GB 模型, 依赖KV cache量化)
BATCH=512           # batch size (保守值, 长跑比 1024 更稳, 散热压力小)
UBATCH=512          # micro batch size
THREADS=6           # CPU线程数 (匹配 3500X 6核)

PORT=11434

echo "=============================="
echo "启动 Gemma 4 12B IT Q4_K_M (llama.cpp) API 服务"
echo "地址: http://0.0.0.0:$PORT"
echo "模型: gemma-4-12b-it-Q4_K_M.gguf"
echo "上下文: $CTX"
echo "GPU层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
echo "KV Cache: q4_0"
echo "思考模式: 支持 (<|think|> token in system prompt)"
echo "Tool Call: 支持"
echo "模态: 文本 (无 mmproj, 不支持 vision/audio)"
echo "=============================="
echo ""

# 检查模型文件是否存在
if [[ ! -f "$MODEL_DIR" ]]; then
    echo "错误: 模型文件不存在: $MODEL_DIR"
    echo ""
    echo "请手动下载 Gemma 4 12B GGUF 模型:"
    echo "  https://huggingface.co/unsloth/gemma-4-12b-it-GGUF"
    echo ""
    echo "推荐下载 Q4_K_M 量化版本 (~7.12GB):"
    echo "  gemma-4-12b-it-Q4_K_M.gguf"
    echo ""
    echo "下载完成后, 请修改此脚本中的 MODEL_DIR 路径"
    exit 1
fi

# 使用 GGUF 内置的 Gemma 4 chat template
# Gemma 4 chat template 由 llama.cpp 内置支持 (--jinja 自动识别)
exec $LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --host 0.0.0.0 \
  --port $PORT \
  --jinja \
  -ngl $NGL \
  -c $CTX \
  --batch-size $BATCH \
  --ubatch-size $UBATCH \
  --flash-attn on \
  --threads $THREADS \
  --threads-batch $THREADS \
  --prio 2 \
  --no-mmap \
  --mlock \
  --no-warmup \
  --parallel 1 \
  --temp 1.0 \
  --top-p 0.95 \
  --top-k 64 \
  --min-p 0.0 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --timeout 300 \
  --metrics
