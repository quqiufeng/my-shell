#!/bin/bash
set -euo pipefail
#
# =============================================================
# Qwen3-14B-Claude-4.5-Opus-Distill (KoboldCpp) API 启动脚本 (4090D 24GB)
# =============================================================
#
# 【基准测试数据】(2025-04-15, test_api.py 30题算法题, max_tokens=1024)
# ┌─────────────┬──────────┬────────────┬─────────────────────────────┐
# │ 上下文大小  │ 平均速度 │ 总token数  │ 备注                        │
# ├─────────────┼──────────┼────────────┼─────────────────────────────┤
# │ 128K        │ ~69.5    │ -          │ batch=512, threads=14,      │
# │             │          │            │ quantkv=2, fa=on            │
# │ 80K         │ 74-75    │ -          │ batch=512, threads=14       │
# └─────────────┴──────────┴────────────┴─────────────────────────────┘
# 对比: llama.cpp 128K 约 79.4 tok/s
# 测试环境: NVIDIA GeForce RTX 4090 D 24GB, CUDA compute 8.9
#
# 【优化要点】
#   - contextsize: 131072 (128K, 依赖 quantkv=2 省显存)
#   - quantkv 2: KV cache q4 量化, 24GB 跑 128K 的关键
#   - flashattention: 必须开启
#   - batchsize: 512 (128K 下的平衡值)
# =============================================================
#
# 【启动方式】
#   cd /opt/my-shell/4090d
#   setsid nohup ./run_qwen3-14b-claude-45-opus-distill_koboldcpp.sh > /tmp/claude45opus_koboldcpp.log 2>&1 < /dev/null &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/claude45opus_koboldcpp.log
#
# 【停止服务】
#   pkill -f koboldcpp.py
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
# 【性能测试】
#   cd /opt/my-shell
#   python3 test_api.py
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# 路径: ~/.config/opencode/opencode.json
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf": {
#           "name": "Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf",
#           "maxContextWindow": 81920,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf
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

export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/root/miniconda3/pkgs/libstdcxx-15.2.0-h39759b7_7/lib:/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}

MODEL_DIR="/opt/gguf/Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf"
KOBOLDCPP_DIR="/opt/koboldcpp"

GPULAYERS=99
CONTEXTSIZE=131072
BATCHSIZE=512
THREADS=14
BLASTHREADS=14

echo "=============================="
echo "启动 Qwen3-14B-Claude-4.5-Opus-Distill Q4_K_M (KoboldCpp) API 服务"
echo "地址: http://0.0.0.0:11434"
echo "上下文: 128K ($CONTEXTSIZE)"
echo "GPU层数: $GPULAYERS"
echo "Batch Size: $BATCHSIZE"
echo "Threads: $THREADS"
echo "Flash Attention: on"
echo "KV Cache: quantkv=2 (q4)"
echo "Jinja模板: 自动检测 (qwen3)"
echo "=============================="

cd "$KOBOLDCPP_DIR"

python koboldcpp.py \
  "$MODEL_DIR" \
  11434 \
  --host 0.0.0.0 \
  --gpulayers $GPULAYERS \
  --contextsize $CONTEXTSIZE \
  --batchsize $BATCHSIZE \
  --threads $THREADS \
  --blasthreads $BLASTHREADS \
  --flashattention \
  --quiet \
  --usemlock \
  --nommap \
  --quantkv 2 \
  --jinja \
  --chat-template-kwargs '{"enable_thinking":false}' &

sleep 10

INSTANCE_ID=${XGC_INSTANCE_ID:-$(hostname)}

echo ""
echo "=============================="
echo "服务已启动!"
echo "=============================="
echo "对内地址: http://localhost:11434"
echo "对外地址: http://${INSTANCE_ID}-11434.container.x-gpu.com/v1/"
echo "=============================="
echo ""
echo "调试命令:"
echo "curl -s http://localhost:11434/v1/chat/completions \\"
echo '  -H "Content-Type: application/json" \'
echo '  -d '"'"'{"model": "Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'"'"''
echo ""
echo "性能参数:"
echo "  模型: Qwen3-14B-Claude-4.5-Opus-Distill.q4_k_m.gguf"
echo "  框架: KoboldCpp"
echo "  上下文: 128K"
echo "  最大输出: 32K"
echo "  GPU层数: $GPULAYERS"
echo "  Batch Size: $BATCHSIZE"
echo "  Threads: $THREADS"
echo "  Flash Attention: on"
echo "  KV Cache: quantkv=2 (q4)"
echo "  Chat模板: jinja自动检测 (qwen3)"
echo "  思考模式: 关闭 (enable_thinking=false)"
