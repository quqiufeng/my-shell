#!/bin/bash
#
# 【模型信息】
# 模型: Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled (GGUF Q4_K_M)
# 框架: KoboldCpp
# 显存占用: ~6GB (RTX 3080 10GB)
# 上下文: 80K (81920 tokens)
#
# 【性能测试数据 - 30个高难度提示词】
# 平均速度: 62.0 tokens/s
# 最快: 最长公共子序列 67.8 tokens/s
# 最慢: 阻塞队列 46.2 tokens/s
# 典型速度: 60-65 tokens/s
#
# 【测试方法】
# cd /home/dministrator/my-shell
# python3 branch.py 11434 "koboldcpp/Qwen3.5-9B.Q4_K_M" 200
#
# 【对比其他框架】
# KoboldCpp: 62.0 tokens/s (当前)
# llama.cpp: 67.5 tokens/s
# ExLlamaV2 7B: 78.4 tokens/s
#
# 【KoboldCpp 优势】
# - 比 llama.cpp 更省内存
# - 支持更多功能（Web UI、多模态）
# - 速度接近 llama.cpp

MODEL_DIR="/opt/image/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled/Qwen3.5-9B.Q5_K_S.gguf"
KOBOLDCPP_DIR="/opt/koboldcpp"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

echo "=============================="
echo "启动 Qwen3.5-9B-Claude (KoboldCpp)"
echo "地址: http://0.0.0.0:11434"
echo "模型: Qwen3.5-9B.Q5_K_S.gguf"
echo "框架: KoboldCpp (比 llama.cpp 更省内存)"
echo "=============================="
echo ""
echo "⚠️ Windows 端口转发命令 (在 Windows PowerShell 管理员运行):"
echo "# 删除旧转发:"
echo "netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=11434"
echo ""
echo "# 添加新转发 (转发到 WSL2):"
echo "netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=11434 connectaddress=172.23.212.172 connectport=11434"
echo ""
echo "# 查看转发状态:"
echo "netsh interface portproxy show all"
echo "=============================="
echo ""

cd "$KOBOLDCPP_DIR"

python koboldcpp.py \
  --model "$MODEL_DIR" \
  --port 11434 \
  --host 0.0.0.0 \
  --gpulayers 35 \
  --contextsize 81920 \
  --flashattention \
  --quiet

# 参数说明:
# --gpulayers 35: GPU 层数
# --contextsize 81920: 上下文长度 (80K)
# --flashattention: 启用 Flash Attention
# --quiet: 减少日志输出
