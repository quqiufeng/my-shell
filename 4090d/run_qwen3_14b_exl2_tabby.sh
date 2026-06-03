#!/bin/bash
set -euo pipefail
#
# =============================================================
# Qwen3-14B exl2 @ 4.5bpw (TabbyAPI) API 启动脚本 (4090D 24GB)
# =============================================================
#
# 【模型】TheMelonGod/Qwen3-14B-exl2 (6hb-4.5bpw)
# 【显存】权重 ~7.5GB + KV cache (Q4) ~3GB = ~11GB 总占用
# 【上下文】128K (131072)
#
# 【基准测试数据】(2025-06-03, test_api.py 30题算法题, max_tokens=1024)
# ┌─────────────┬──────────┬────────────┬─────────────────────────────┐
# │ 上下文大小  │ 平均速度 │ 总token数  │ 备注                        │
# ├─────────────┼──────────┼────────────┼─────────────────────────────┤
# │ 128K        │ 84.1     │ 30720      │ batch=512, threads=16,      │
# │             │          │            │ cache_mode=Q4, exllamav2    │
# └─────────────┴──────────┴────────────┴─────────────────────────────┘
# 对比: Qwopus3.6-27B-v2-MTP GGUF 128K 44.4 tok/s, exl2 快 ~1.9x
# 测试环境: NVIDIA GeForce RTX 4090 D 24GB, CUDA compute 8.9
# 模型: Qwen3-14B-exl2-4.5bpw
# 总耗时: 365.36s (30题 × 1024 tokens)
# 速度范围: 78.1 - 86.0 tok/s
#
# 【启动方式】(必须用 setsid，否则终端关闭会终止服务)
#   cd /opt/my-shell/4090d
#   setsid nohup ./run_qwen3_14b_exl2_tabby.sh > /tmp/14b_qwen3_tabby.log 2>&1 < /dev/null &
#   echo $!  # 记录PID
#
# 【查看日志】
#   tail -f /tmp/14b_qwen3_tabby.log
#
# 【停止服务】
#   pkill -f "tabby.*qwen3_14b" || pkill -f "python3.*main.py.*tabby_qwen3"
#
# 【测试API】
#   curl http://localhost:11436/v1/models
#   curl -s http://localhost:11436/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "Qwen3-14B-exl2-4.5bpw", "messages": [{"role": "user", "content": "你好"}], "max_tokens": 50}'
#
# =============================================================
# OpenCode 配置文件 (~/.config/opencode/opencode.json)
# =============================================================
# {
#   "$schema": "https://opencode.ai/config.json",
#   "model": "openai/Qwen3-14B-exl2-4.5bpw",
#   "provider": {
#     "openai": {
#       "npm": "@ai-sdk/openai-compatible",
#       "name": "Local Models",
#       "options": {
#         "baseURL": "http://localhost:11436/v1",
#         "apiKey": "dummy"
#       },
#       "models": {
#         "Qwen3-14B-exl2-4.5bpw": {
#           "name": "Qwen3-14B exl2 4.5bpw (TabbyAPI)",
#           "maxContextWindow": 131072,
#           "maxOutputTokens": 32768
#         }
#       }
#     }
#   }
# }
#
# 【使用 opencode】
#   opencode -m openai/Qwen3-14B-exl2-4.5bpw
#
# 【Chat Template 来源】
#   /opt/my-shell/4090d/chat_template_qwen3_fixed_v19.jinja
#   来源: https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates
#   说明: 修复官方 Qwen 3.5/3.6 chat template 的多个 bug
#         - Agentic 过早停止
#         - KV Cache 失效
#         - 空 Think 污染
#         - C++ Jinja 兼容性
#
# =============================================================

# 快速环境检查
if ! command -v nvidia-smi &> /dev/null; then
    echo "警告: nvidia-smi 未找到, 请确认 CUDA 驱动已安装"
fi

MODEL_DIR="/opt/gguf/Qwen3-14B-exl2-4.5bpw"
TABBY_DIR="/opt/tabbyAPI"
CONFIG="/opt/my-shell/4090d/tabby_qwen3_14b_config.yml"

if [[ ! -d "$MODEL_DIR" ]]; then
    echo "错误: 模型目录不存在: $MODEL_DIR"
    echo "请先运行下载脚本获取模型:"
    echo "  huggingface-cli download TheMelonGod/Qwen3-14B-exl2 --revision 6hb-4.5bpw --local-dir $MODEL_DIR --local-dir-use-symlinks False"
    exit 1
fi

if [[ ! -f "$TABBY_DIR/main.py" ]]; then
    echo "错误: TabbyAPI 未安装: $TABBY_DIR/main.py 不存在"
    echo "请先克隆并安装 TabbyAPI:"
    echo "  git clone --depth 1 https://github.com/theroyallab/tabbyAPI.git $TABBY_DIR"
    echo "  cd $TABBY_DIR && pip install -e ."
    exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
    echo "错误: 配置文件不存在: $CONFIG"
    exit 1
fi

# 检查模型文件是否完整 (至少检查 safetensors)
if ! ls "$MODEL_DIR"/*.safetensors &> /dev/null; then
    echo "错误: 模型文件不完整, 缺少 .safetensors 文件"
    echo "模型可能还在下载中, 请检查: tail -f /tmp/download_qwen3_14b_exl2.log"
    exit 1
fi

echo "=============================="
echo "启动 Qwen3-14B exl2 4.5bpw (TabbyAPI) API 服务"
echo "地址: http://0.0.0.0:11436"
echo "模型: $MODEL_DIR"
echo "上下文: 128K (131072)"
echo "KV Cache: Q4"
echo "后端: exllamav2"
echo "=============================="
echo ""

cd "$TABBY_DIR"
exec python3 main.py --config "$CONFIG"
