#!/bin/bash
#
# =============================================================
# Qwen3.5-9B (KoboldCpp) API 启动脚本 (4090D 24GB) - 优化版
# =============================================================
#
# 【性能数据】(4090D 24GB, 256K上下文, Q4_K_M模型)
#   速度: ~90-95 tokens/s
#   测试命令: python3 test_api.py
#   测试结果: 约90-95 tok/s (高难度算法题)
# =============================================================
#
# 【启动方式】
#   cd /opt/my-shell/4090d
#   nohup ./run_qwen3.5-9b_koboldcpp.sh > /tmp/9b_koboldcpp.log 2>&1 &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/9b_koboldcpp.log
#
# 【停止服务】
#   pkill -f koboldcpp.py
#
# 【测试API】
#   curl http://localhost:11434/v1/models
#   curl -s http://localhost:11434/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwopus3.5-9B-v3.Q4_K_M.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
# 【性能测试】
#   cd /opt/my-shell
#   python3 test_api.py
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/Qwopus3.5-9B-v3.Q4_K_M.gguf",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11434/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Qwopus3.5-9B-v3.Q4_K_M.gguf": {
#           "name": "Qwen3.5-9B-KoboldCpp Q4 (4090D)",
#           "maxContextWindow": 262144,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Qwopus3.5-9B-v3.Q4_K_M.gguf
#
# =============================================================

export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/root/miniconda3/pkgs/libstdcxx-15.2.0-h39759b7_7/lib:/usr/lib/wsl/lib:$LD_LIBRARY_PATH

# 4090D 优化参数
MODEL_DIR="/opt/gguf/Qwopus3.5-9B-v3.Q4_K_M.gguf"
KOBOLDCPP_DIR="/opt/koboldcpp"

# 4090D 24GB 显存可以支持更大上下文
GPULAYERS=99          # 全部加载到GPU
CONTEXTSIZE=262144    # 256K 上下文 (4090D 24GB 支持)
BATCHSIZE=4096        # 更大的batch size
THREADS=16            # 更多线程
BLASTHREADS=16        # BLAS线程

echo "=============================="
echo "启动 Qwen3.5-9B Q4_K_M (KoboldCpp) API 服务"
echo "地址: http://0.0.0.0:11434"
echo "上下文: 256K ($CONTEXTSIZE)"
echo "GPU层数: $GPULAYERS"
echo "Batch Size: $BATCHSIZE"
echo "Threads: $THREADS"
echo "Flash Attention: on"
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
  --nommap &

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
echo '  -d '"'"'{"model": "Qwopus3.5-9B-v3.Q4_K_M.gguf", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'"'"''
echo ""
echo "性能参数:"
echo "  模型: Qwopus3.5-9B-v3.Q4_K_M.gguf"
echo "  框架: KoboldCpp"
echo "  上下文: 256K"
echo "  最大输出: 32K"
echo "  GPU层数: $GPULAYERS"
echo "  Batch Size: $BATCHSIZE"
echo "  Threads: $THREADS"
echo "  Flash Attention: on"
echo "  思考模式: 关闭 (enable_thinking=false)"
