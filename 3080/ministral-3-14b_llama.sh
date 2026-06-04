#!/bin/bash
set -euo pipefail
#
# =============================================================
# Ministral-3-14B-Instruct-2512 (llama.cpp) API 启动脚本 (RTX 3080 20GB)
# =============================================================
#
# 【模型主页】
#   unsloth 版 (推荐): https://huggingface.co/unsloth/Ministral-3-14B-Instruct-2512-GGUF
#   官方版:           https://huggingface.co/mistralai/Ministral-3-14B-Instruct-2512-GGUF
#   unsloth 指南:     https://docs.unsloth.ai/new/ministral-3
#   unsloth 量化基准: https://docs.unsloth.ai/basics/unsloth-dynamic-v2.0-gguf
#   原始 BF16:        https://huggingface.co/mistralai/Ministral-3-14B-Instruct-2512
#
# 【模型介绍】(摘自 unsloth HF 主页 2026-06-04)
#   "The largest model in the Ministral 3 family, Ministral 3 14B offers frontier
#    capabilities and performance comparable to its larger Mistral Small 3.2 24B
#    counterpart. A powerful and efficient language model with vision capabilities."
#
#   "The Ministral 3 family is designed for edge deployment, capable of running on a
#    wide range of hardware. Ministral 3 14B can even be deployed locally, capable of
#    fitting in 24GB of VRAM in FP8, and less if further quantized."
#
#   【架构组成】
#   - 13.5B Language Model
#   - 0.4B Vision Encoder (Pixtral 风格)
#   - Architecture: mistral3
#   - Total: 14B params
#
#   【核心能力】
#   - Vision:        分析图片, 视觉内容理解 (3090D/4090D/A100 等支持)
#   - Multilingual:  English, French, Spanish, German, Italian, Portuguese,
#                    Dutch, Chinese, Japanese, Korean, Arabic 等几十种
#   - System Prompt: 强遵从 system prompt
#   - Agentic:       ⭐ Best-in-class 工具调用能力, native function calling + JSON 输出
#   - Edge-Optimized:小规模下 SOTA 性能, 部署灵活
#   - License:       Apache 2.0 (可商用)
#   - Context:       256K 原生 (262144 tokens, 3080 20GB 跑 64K 已实测)
#
#   【使用场景】
#   - 私有/自定义 chat 与 AI 助手部署
#   - 高级本地 agent 任务
#   - Fine-tuning 与领域特化
#
# 【Ministral 3 系列】(3B / 8B / 14B, 三种类型: Base / Instruct / Reasoning)
#   ┌──────────┬───────────────┬─────────────┬──────────────┬──────────────┐
#   │ 规模     │ Base          │ Instruct    │ Reasoning    │ 默认精度     │
#   ├──────────┼───────────────┼─────────────┼──────────────┼──────────────┤
#   │ 3B       │ Ministral-3B  │ Ministral-3B│ Ministral-3B │ BF16/FP8/BF16│
#   │ 8B       │ Ministral-8B  │ Ministral-8B│ Ministral-8B │ BF16/FP8/BF16│
#   │ 14B      │ Ministral-14B │ Ministral-14B│Ministral-14B│ BF16/FP8/BF16│
#   └──────────┴───────────────┴─────────────┴──────────────┴──────────────┘
#   我们用的是 Ministral 3 14B Instruct (FP8 → GGUF 量化)
#
# 【Benchmark 性能】(unsloth HF 主页官方数据)
#   Reasoning (数学/代码/科学推理, 分数越高越好)
#   ┌──────────────────┬────────┬────────┬──────────┬──────────────┐
#   │ 模型             │ AIME25 │ AIME24 │ GPQA     │ LiveCodeBch  │
#   ├──────────────────┼────────┼────────┼──────────┼──────────────┤
#   │ Ministral 3 14B  │ 0.850  │ 0.898  │ 0.712    │ 0.646        │
#   │ Qwen3-14B(Think) │ 0.737  │ 0.837  │ 0.663    │ 0.593        │
#   │ Ministral 3 8B   │ 0.787  │ 0.860  │ 0.668    │ 0.616        │
#   │ Qwen3-VL-8B-Think│ 0.798  │ 0.860  │ 0.671    │ 0.580        │
#   │ Ministral 3 3B   │ 0.721  │ 0.775  │ 0.534    │ 0.548        │
#   │ Qwen3-VL-4B-Think│ 0.697  │ 0.729  │ 0.601    │ 0.513        │
#   └──────────────────┴────────┴────────┴──────────┴──────────────┘
#   14B vs Qwen3-14B: AIME25 +15.3%, AIME24 +7.3%, GPQA +7.4%, LiveCodeBench +8.9%
#
#   Instruct (对话质量, 分数越高越好)
#   ┌──────────────────┬─────────┬──────────┬─────────┬───────────┐
#   │ 模型             │ Arena   │ WildBench│ MATH    │ MM MTBench│
#   │                  │ Hard    │          │ Maj@1   │ (多模态)  │
#   ├──────────────────┼─────────┼──────────┼─────────┼───────────┤
#   │ Ministral 3 14B  │ 0.551   │ 68.5     │ 0.904   │ 8.49      │
#   │ Qwen3-14B(N-T)   │ 0.427   │ 65.1     │ 0.870   │ N/A       │
#   │ Gemma3-12B-Inst  │ 0.436   │ 63.2     │ 0.854   │ 6.70      │
#   │ Ministral 3 8B   │ 0.509   │ 66.8     │ 0.876   │ 8.08      │
#   │ Qwen3-VL-8B-Inst │ 0.528   │ 66.3     │ 0.946   │ 8.00      │
#   └──────────────────┴─────────┴──────────┴─────────┴───────────┘
#   14B vs Qwen3-14B: Arena Hard +29.0%, WildBench +5.2%, MATH +3.9%
#   ⚠️ Ministral 唯一支持多模态的 14B 级模型 (Qwen3-14B 没有 MM MTBench)
#
#   Base (预训练基础能力, 分数越高越好)
#   ┌──────────────────┬────────┬────────┬────────┬────────┬────────┬────────┐
#   │ 模型             │ Multi  │ MATH   │ AGIEval│ MMLU   │ MMLU   │ Trivia │
#   │                  │ MMLU   │ CoT-2S │ 5-shot │ Redux-5│ 5-shot │ QA-5   │
#   ├──────────────────┼────────┼────────┼────────┼────────┼────────┼────────┤
#   │ Ministral 3 14B  │ 0.742  │ 0.676  │ 0.648  │ 0.820  │ 0.794  │ 0.749  │
#   │ Qwen3-14B Base   │ 0.754  │ 0.620  │ 0.661  │ 0.837  │ 0.804  │ 0.703  │
#   │ Gemma3-12B Base  │ 0.690  │ 0.487  │ 0.587  │ 0.766  │ 0.745  │ 0.788  │
#   └──────────────────┴────────┴────────┴────────┴────────┴────────┴────────┘
#
# 【下载量统计】(unsloth HF 主页 2026-06-04)
#   - Likes:        86
#   - 月下载:       14,240
#   - 量化版本数:   22 个 (1-bit ~ 16-bit 全覆盖)
#
# 【量化版本】(RTX 3080 20GB 推荐)
#   ┌──────────┬──────────┬──────────────────────────────────────────────┐
#   │ 版本     │ 大小     │ 备注                                         │
#   ├──────────┼──────────┼──────────────────────────────────────────────┤
#   │ UD-Q4_K_XL│ 8.37GB  │ ✅ 推荐 (Unsloth Dynamic 2.0, SOTA 精度)    │
#   │ Q4_K_M   │ 8.24GB   │ 官方标准 4-bit                               │
#   │ UD-Q5_K_XL│ 9.64GB  │ 质量更好 (动态量化)                          │
#   │ Q5_K_M   │ 9.62GB   │ 官方标准 5-bit                               │
#   │ Q6_K     │ 11.1GB   │ 高质量                                       │
#   │ Q8_0     │ 14.4GB   │ 接近原质量                                   │
#   │ BF16     │ 27GB     │ 超出 3080 20GB, 需 A100/H200                │
#   └──────────┴──────────┴──────────────────────────────────────────────┘
#   完整 22 个版本 (1-bit ~ 16-bit) 见: https://huggingface.co/unsloth/Ministral-3-14B-Instruct-2512-GGUF
#
#   【unsloth Dynamic 2.0 优势】
#   - "Dynamic 2.0 achieves superior accuracy & SOTA quantization performance"
#   - UD-Q4_K_XL 比标准 Q4_K_M 精度更高, 大小几乎一样
#   - 月下载量: unsloth 14,240 vs 官方 6,694 (~2.1x, 社区更信任 unsloth)
#
# 【测试 API 数据】(2026-06-04, test_api.py 30题算法题, max_tokens=1024)
#   ┌─────────────┬──────────┬────────────┬──────────────────────────────────┐
#   │ 上下文大小  │ 平均速度 │ 总token数  │ 备注                             │
#   ├─────────────┼──────────┼────────────┼──────────────────────────────────┤
#   │ 64K         │ 61.3     │ 30720      │ batch=512, threads=6,            │
#   │             │ tok/s    │            │ cache-type-k/v=q4_0, fa=on,      │
#   │             │          │            │ temp=0.05, top_p=0.95, top_k=20  │
#   └─────────────┴──────────┴────────────┴──────────────────────────────────┘
#   速度范围: 58.6 - 64.6 tok/s
#   测试环境: NVIDIA GeForce RTX 3080 20GB (sm_86), CUDA compute 8.6
#   模型:     Ministral-3-14B-Instruct-2512-UD-Q4_K_XL.gguf
#   对比 Qwen3-14B Q4_K_M: 58.0 tok/s → 61.3 tok/s (+5.7%)
#   题目覆盖: 排序(快排/堆排/归并/拓扑), 数据结构(红黑树/B+/跳表/线段树),
#             图算法(Dijkstra/A*/MST/并查集), 动态规划, 算法(双指针/滑动窗口/
#             二分/KMP/LRU/布隆/字典树), 系统设计(数据库索引/一致性哈希/令牌桶)
# =============================================================
#
# 【上下文配置】(RTX 3080 20GB, UD-Q4_K_XL 8.37GB 模型)
#   - 64K:  推荐, 模型 ~8.4GB + KV cache q4_0 ~3.7GB, 余量 ~8GB ✅ 已实测
#   - 96K:  安全, 模型 ~8.4GB + KV cache q4_0 ~5.5GB, 余量 ~6GB
#   - 128K: 紧张, 模型 ~8.4GB + KV cache q4_0 ~7.3GB, 余量 ~4GB (未测)
#   - 256K: OOM, 原生 256K 但 3080 20GB 不够 KV cache
#   - 注: 不需要 YaRN 扩展 (原生 256K > 实际配置的 64K)
#
# 【降级建议】(若启动时 OOM)
#   - 将 CTX=65536 降为 32768 (32K)
#   - 关闭浏览器/视频播放器等显存占用程序
#   - 切换更小量化 (UD-Q4_K_XL 8.37GB → Q4_K_M 8.24GB 省 0.13GB, 实际差异小)
#
# 【优化要点】
#   - ctx-size: 65536 (64K, 3080 20GB 充足, 已实测)
#   - batch-size: 512 (保守值, 降低显存压力)
#   - ubatch-size: 512
#   - flash-attn on: 必须开启, 大幅降低长文本显存压力并提升速度
#   - threads: 6 (匹配 3500X 6核)
#   - --parallel 1: 减少 slot 开销
#   - --no-mmap + --mlock: 提升 IO 性能
#   - --no-warmup: 跳过启动 warmup, 大幅缩短启动时间
#   - --cache-type-k/v: q4_0 (核心省显存参数)
#   - --temp 0.05: 官方推荐 < 0.1 (我们用 0.05)
#   - --top-p 0.95, --top-k 20, --min-p 0.0
#
# 【采样参数】(Mistral 官方 + unsloth 推荐)
#   llama.cpp:
#     --temp 0.05  --top-p 0.95  --top-k 20  --min-p 0.0
#   vLLM:
#     temperature=0.15  (unsloth 文档示例)
#   ⚠️ 温度区间 0.05~0.15, 与 Qwen3 的 0.6 截然不同
#
# 【思考模式】(Mistral 3 通用)
#   llama.cpp 检测 chat template 显示 `thinking = 1`, 表示支持 thinking 模式
#   - 默认行为: 模型根据复杂度自动决定是否思考, 简单任务不输出
#   - 强制思考: 在 system prompt 加 "Think step by step"
#   - 强制不思考: 加 "Be concise, answer directly"
#   - 验证: 对 "Redis 是什么" 简单问题, 30题测试均无 thinking 残留
#
# 【Chat Template】
#   使用 GGUF 内置 Mistral 3 chat template (--jinja 自动加载)
#   - 格式: [SYSTEM_PROMPT]...[/SYSTEM_PROMPT][INST]...[/INST]
#   - 原生支持 tool call (OpenAI function calling 格式)
#   - 原生支持多模态图像输入 (Pixtral 风格)
#   - 兼容 OpenAI /v1/chat/completions API
#
# 【Function Calling】(关键, opencode agent 依赖)
#   测试通过: 模型正确输出 tool_calls, 格式为:
#   {"tool_calls": [{"type":"function", "function":{"name":"get_weather", "arguments":"{\"city\":\"北京\"}"}}]}
#   - vLLM 推荐参数: --enable-auto-tool-choice --tool-call-parser mistral
#   - llama.cpp: 无需特殊参数, 内置 chat template 已支持
#   - 实测 opencode agent: todowrite + bash 多步工具调用正常
#
# 【使用建议】
#   1. 温度 < 0.1 (Mistral 官方推荐, 与 Qwen3 的 0.6 截然不同)
#   2. 不要用贪心解码 (--temp 0), 会导致重复
#   3. agent 任务建议 temp=0.05, 创造性任务可提到 0.1-0.3
#   4. 复杂任务可用 system prompt 设定角色 (unsloth 文档示例)
#   5. 长上下文任务务必保留 KV cache 量化 (q4_0)
#   6. 多模态任务需用 vLLM 部署 (llama.cpp 3080 20GB 受限)
# =============================================================
#
# 【llama.cpp 启动方式】(unsloth HF 主页推荐)
#
#   # 方式 1: 直接用 -hf 拉取 (需最新 llama.cpp)
#   llama-server -hf unsloth/Ministral-3-14B-Instruct-2512-GGUF:UD-Q4_K_XL
#
#   # 方式 2: brew/winget 安装
#   brew install llama.cpp
#   llama-server -hf unsloth/Ministral-3-14B-Instruct-2512-GGUF:UD-Q4_K_XL
#
#   # 方式 3: 手动下载 GGUF 后启动 (本脚本方式)
#   wget https://huggingface.co/unsloth/Ministral-3-14B-Instruct-2512-GGUF/resolve/main/Ministral-3-14B-Instruct-2512-UD-Q4_K_XL.gguf
#   llama-server -m Ministral-3-14B-Instruct-2512-UD-Q4_K_XL.gguf ...
#
#   # 方式 4: Ollama 一键
#   ollama run hf.co/unsloth/Ministral-3-14B-Instruct-2512-GGUF:UD-Q4_K_XL
#
#   # 方式 5: Docker
#   docker model run hf.co/unsloth/Ministral-3-14B-Instruct-2512-GGUF:UD-Q4_K_XL
#
# 【vLLM 启动方式】(Mistral 官方推荐, 需 24GB+ VRAM)
#   vllm serve mistralai/Ministral-3-14B-Instruct-2512 \
#     --enable-auto-tool-choice --tool-call-parser mistral \
#     --max-model-len 262144  # 默认即 256K, 可按需缩小
#
#   # 关键参数:
#   # --enable-auto-tool-choice: 启用 tool usage
#   # --tool-call-parser mistral: 启用 Mistral tool parser
#   # --max-model-len 262144:    256K 默认, 大多数场景可缩到 32K~64K
#   # --max-num-batched-tokens:  平衡吞吐与延迟
#
# =============================================================
#
# 【本脚本启动方式】(必须用 setsid + nohup, 否则终端关闭会终止服务)
#   cd /opt/my-shell/3080
#   setsid nohup ./ministral-3-14b_llama.sh > /tmp/ministral-3-14b_llama.log 2>&1 < /dev/null &
#   echo $!  # 记录 PID
#
# 【查看日志】
#   tail -f /tmp/ministral-3-14b_llama.log
#
# 【停止服务】
#   pkill -f "llama-server.*Ministral"
#
# 【测试 API】
#   curl http://localhost:11434/v1/models
#
#   # 基础对话
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Ministral-3-14B-Instruct-2512", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50, "temperature": 0.05}'
#
#   # Tool Call 测试 (函数调用)
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{
#       "model": "Ministral-3-14B-Instruct-2512",
#       "messages": [{"role": "user", "content": "北京现在天气如何？"}],
#       "tools": [{
#         "type": "function",
#         "function": {
#           "name": "get_weather",
#           "description": "获取指定城市的天气",
#           "parameters": {
#             "type": "object",
#             "properties": {"city": {"type": "string", "description": "城市名"}},
#             "required": ["city"]
#           }
#         }
#       }],
#       "max_tokens": 512,
#       "temperature": 0.05
#     }'
#
#   # 性能测试 (30题)
#   python3 /opt/my-shell/test_api.py "Ministral-3-14B-Instruct-2512"
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/Ministral-3-14B-Instruct-2512-UD-Q4_K_XL.gguf",
#   "agent": {
#     "build": {
#       "model": "openai/Ministral-3-14B-Instruct-2512-UD-Q4_K_XL.gguf",
#       "temperature": 0.05,
#       "top_p": 0.95,
#       "top_k": 20,
#       "steps": 1000
#     }
#   },
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Ministral-3-14B-Instruct-2512-UD-Q4_K_XL.gguf": {
#           "name": "Ministral-3-14B-Instruct-2512 UD-Q4_K_XL (3080 20GB llama.cpp)",
#           "maxContextWindow": 262144,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Ministral-3-14B-Instruct-2512-UD-Q4_K_XL.gguf
#
# =============================================================

# 快速环境检查
if ! command -v nvidia-smi &> /dev/null; then
    echo "警告: nvidia-smi 未找到, 请确认 CUDA 驱动已安装"
fi
if [[ ! -x "/opt/llama.cpp/build/bin/llama-server" ]]; then
    echo "错误: /opt/llama.cpp/build/bin/llama-server 不存在或不可执行"
    echo "请先编译: /opt/my-shell/3080/build/build_llama_cpp.sh"
    exit 1
fi

export LD_LIBRARY_PATH=/data/cuda/lib64:/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}

# RTX 3080 20GB 显存优化参数
# ⚠️ 请手动下载模型后确认此路径
# 下载地址 (推荐 unsloth 版): https://huggingface.co/unsloth/Ministral-3-14B-Instruct-2512-GGUF
# 下载地址 (官方版):         https://huggingface.co/mistralai/Ministral-3-14B-Instruct-2512-GGUF
MODEL_DIR="/data/models/Ministral-3-14B-Instruct-2512-UD-Q4_K_XL.gguf"
LLAMA_SERVER="/opt/llama.cpp/build/bin/llama-server"

# RTX 3080 14B 模型参数 (20GB 显存, 64K 上下文)
NGL=99              # GPU 层数 (全部加载到 GPU)
CTX=65536           # 上下文 64K (3080 20GB 充足, 已实测 61.3 tok/s)
BATCH=512           # batch size (保守值, 降低显存压力)
UBATCH=512          # micro batch size
THREADS=6           # CPU 线程数 (匹配 3500X 6核)

PORT=11434

echo "=============================="
echo "启动 Ministral-3-14B-Instruct-2512 (llama.cpp) API 服务"
echo "地址:   http://0.0.0.0:$PORT"
echo "模型:   Ministral-3-14B-Instruct-2512-UD-Q4_K_XL.gguf (8.37GB, unsloth Dynamic 2.0)"
echo "上下文: $CTX (原生 256K, 受 20GB 显存限制)"
echo "GPU 层数: $NGL"
echo "Batch Size: $BATCH"
echo "uBatch Size: $UBATCH"
echo "Threads: $THREADS"
echo "KV Cache: q4_0"
echo "温度: 0.05 (Mistral 官方推荐 < 0.1)"
echo "Tool Call: 支持 (Native Function Calling)"
echo "多模态: 架构支持 (llama.cpp 暂未启用 vision encoder)"
echo "=============================="
echo ""

# 检查模型文件是否存在
if [[ ! -f "$MODEL_DIR" ]]; then
    echo "错误: 模型文件不存在: $MODEL_DIR"
    echo ""
    echo "请手动下载 Ministral-3-14B-Instruct-2512-GGUF 模型:"
    echo "  推荐 unsloth 版: https://huggingface.co/unsloth/Ministral-3-14B-Instruct-2512-GGUF"
    echo "  官方版:          https://huggingface.co/mistralai/Ministral-3-14B-Instruct-2512-GGUF"
    echo ""
    echo "推荐下载 unsloth UD-Q4_K_XL 量化版本 (~8.37GB):"
    echo "  Ministral-3-14B-Instruct-2512-UD-Q4_K_XL.gguf"
    echo ""
    echo "下载命令 (unsloth 版 UD-Q4_K_XL):"
    echo "  wget https://huggingface.co/unsloth/Ministral-3-14B-Instruct-2512-GGUF/resolve/main/Ministral-3-14B-Instruct-2512-UD-Q4_K_XL.gguf"
    echo ""
    echo "下载完成后, 请修改此脚本中的 MODEL_DIR 路径"
    exit 1
fi

exec $LLAMA_SERVER \
  -m "$MODEL_DIR" \
  --alias "Ministral-3-14B-Instruct-2512" \
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
  --temp 0.05 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.0 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --defrag-thold 0.1 \
  --timeout 300 \
  --metrics

# 使用 GGUF 内置的 Mistral 3 chat template (原生支持 Tool Call / Function Calling)
