#!/bin/bash
set -euo pipefail
#
# =============================================================
# Qwopus3.5-27B-v3 (KoboldCpp 1.114) API 启动脚本 (4090D 24GB)
# =============================================================
#
# 【Chat Template 来源】https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates
#
# 【KoboldCpp 专用优化】
#   - 编译版本: koboldcpp_cublas.so (CUDA 12, 已编译)
#   - 启动方式: python3 koboldcpp.py (无需 conda/micromamba)
#   - Flash Attention: 默认开启, 无需显式指定
#   - mmap: 默认关闭, 无需 --nommap
# =============================================================
#
# 【基准测试数据】(参考, 待实测)
# ┌─────────────┬──────────┬────────────┬─────────────────────────────┐
# │ 上下文大小  │ 平均速度 │ 总token数  │ 备注                        │
# ├─────────────┼──────────┼────────────┼─────────────────────────────┤
# │ 128K        │ ~33.0    │ ~19456     │ batch=512, threads=14,      │
# │             │          │            │ quantkv=q4_0, fa=on         │
# └─────────────┴──────────┴────────────┴─────────────────────────────┘
# 对比: llama.cpp 128K 约 39.9 tok/s, KoboldCpp 预计慢 ~17%
# 测试环境: NVIDIA GeForce RTX 4090 D 24GB, CUDA compute 8.9
# 模型: Qwopus3.5-27B-v3-Q4_K_S.gguf
#
# 【关键优化参数】
#   - contextsize: 131072 (128K)
#   - gpulayers: 99 (全载GPU)
#   - batchsize: 512 (27B在128K下的平衡值)
#   - threads: 14 (KoboldCpp对27B的最佳线程数)
#   - blasththreads: 14 (批处理线程)
#   - quantkv: q4_0 (KV cache量化, 24GB跑128K的关键)
#   - usemlock: 防止模型被交换到磁盘
#   - highpriority: 提升进程优先级
#   - jinja: 启用jinja聊天模板
#   - skiplauncher: 跳过GUI启动器, 直接启动服务
#   - quiet: 静默模式
# =============================================================
#
# 【启动方式】
#   cd /opt/my-shell/4090d
#   setsid nohup ./run_qwopus3.5-27b-v3_koboldcpp.sh > /tmp/27b_qwopus_koboldcpp.log 2>&1 < /dev/null &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/27b_qwopus_koboldcpp.log
#
# 【停止服务】
#   pkill -f "koboldcpp.py.*Qwopus3.5-27B-v3"
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwopus3.5-27B-v3-Q4_K_S.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
# 【性能测试】
#   cd /opt/my-shell
#   MODEL="openai/Qwopus3.5-27B-v3-Q4_K_S.gguf" python3 test_api.py
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/Qwopus3.5-27B-v3-Q4_K_S.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Qwopus3.5-27B-v3-Q4_K_S.gguf": {
#           "name": "Qwopus3.5-27B-v3 Q4_K_S (KoboldCpp)",
#           "maxContextWindow": 131072,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Qwopus3.5-27B-v3-Q4_K_S.gguf
#
# =============================================================

# 快速环境检查
if ! command -v nvidia-smi &> /dev/null; then
    echo "警告: nvidia-smi 未找到, 请确认 CUDA 驱动已安装"
fi
if [[ ! -f "/opt/koboldcpp/koboldcpp.py" ]]; then
    echo "错误: /opt/koboldcpp/koboldcpp.py 不存在"
    exit 1
fi
if [[ ! -f "/opt/koboldcpp/koboldcpp_cublas.so" ]]; then
    echo "错误: /opt/koboldcpp/koboldcpp_cublas.so 不存在 (需要重新编译)"
    exit 1
fi

# 设置库路径, 确保能加载 CUDA 共享库
export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/root/miniconda3/pkgs/libstdcxx-15.2.0-h39759b7_7/lib:/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}

MODEL="/opt/gguf/Qwopus3.5-27B-v3-Q4_K_S.gguf"
KOBOLDCPP_DIR="/opt/koboldcpp"
CHAT_TEMPLATE="/opt/my-shell/4090d/qwopus35-27b-chat-template.jinja"

# KoboldCpp 1.114 优化参数 (27B @ 4090D 24GB)
GPULAYERS=99
CONTEXTSIZE=131072
BATCHSIZE=512
THREADS=14
BLASTHREADS=14

echo "=============================="
echo "启动 Qwopus3.5-27B-v3 Q4_K_S (KoboldCpp 1.114) API 服务"
echo "地址: http://0.0.0.0:11434"
echo "模型: $MODEL"
echo "上下文: 128K ($CONTEXTSIZE)"
echo "GPU层数: $GPULAYERS"
echo "Batch Size: $BATCHSIZE"
echo "Threads: $THREADS"
echo "BLAS Threads: $BLASTHREADS"
echo "KV Cache: q4_0 (Flash Attention默认开启)"
echo "mlock: enabled"
echo "Priority: high"
echo "=============================="
echo ""

cd "$KOBOLDCPP_DIR"

exec python3 koboldcpp.py \
  "$MODEL" \
  11434 \
  --host 0.0.0.0 \
  --gpulayers $GPULAYERS \
  --contextsize $CONTEXTSIZE \
  --batchsize $BATCHSIZE \
  --threads $THREADS \
  --blasthreads $BLASTHREADS \
  --usemlock \
  --highpriority \
  --quantkv q4_0 \
  --jinja \
  --jinjatemplate "$CHAT_TEMPLATE" \
  --skiplauncher \
  --quiet
