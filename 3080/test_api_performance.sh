#!/bin/bash
# =============================================================================
# 大模型 API 性能测试脚本（3080 10GB）
# 分别测试 llama.cpp 和 KoboldCpp
# =============================================================================

set -e

API_URL="http://localhost:11434/v1/chat/completions"
MODELS_URL="http://localhost:11434/v1/models"

echo "=========================================="
echo "API 性能测试（3080 10GB）"
echo "=========================================="
echo ""

# 检查 test_api.py
if [ ! -f "$HOME/my-shell/test_api.py" ]; then
    echo "错误: test_api.py 不存在"
    exit 1
fi

# 函数：等待 API 就绪
wait_for_api() {
    local name=$1
    echo "等待 $name API 就绪..."
    for i in {1..30}; do
        if curl -s "$MODELS_URL" > /dev/null 2>&1; then
            echo "✅ $name API 已就绪"
            return 0
        fi
        echo "  等待中... ($i/30)"
        sleep 2
    done
    echo "❌ $name API 启动超时"
    return 1
}

# 函数：运行测试
run_test() {
    local model=$1
    echo ""
    echo "=========================================="
    echo "测试 $model"
    echo "=========================================="
    
    # 测试 API 可用性
    curl -s "$MODELS_URL" | head -20
    echo ""
    
    # 运行性能测试
    python3 "$HOME/my-shell/test_api.py" "$model" "$API_URL"
}

# 函数：停止服务
stop_service() {
    echo ""
    echo "停止服务..."
    pkill -f "llama-server" 2>/dev/null || true
    pkill -f "koboldcpp.py" 2>/dev/null || true
    sleep 2
    echo "✅ 服务已停止"
}

# =============================================================================
# 测试 1: llama.cpp
# =============================================================================
echo ""
echo "【测试 1/2】llama.cpp 启动..."
stop_service

cd /home/dministrator/my-shell/3080
nohup ./run_qwen3.5-9b_llama.sh > /tmp/9b_llama_test.log 2>&1 &
LLAMA_PID=$!
echo "✅ llama.cpp 已启动 (PID: $LLAMA_PID)"

wait_for_api "llama.cpp"
run_test "Qwopus3.5-9B-v3.Q5_K_S.gguf"
stop_service

# =============================================================================
# 测试 2: KoboldCpp
# =============================================================================
echo ""
echo "【测试 2/2】KoboldCpp 启动..."
stop_service

cd /home/dministrator/my-shell/3080
nohup ./run_qwen3.5-9b_koboldcpp.sh > /tmp/9b_koboldcpp_test.log 2>&1 &
KOBOLD_PID=$!
echo "✅ KoboldCpp 已启动 (PID: $KOBOLD_PID)"

wait_for_api "KoboldCpp"
run_test "koboldcpp/Qwopus3.5-9B-v3.Q5_K_S"
stop_service

# =============================================================================
# 结果汇总
# =============================================================================
echo ""
echo "=========================================="
echo "测试完成！"
echo "=========================================="
echo "日志文件："
echo "  llama.cpp: /tmp/9b_llama_test.log"
echo "  KoboldCpp: /tmp/9b_koboldcpp_test.log"
