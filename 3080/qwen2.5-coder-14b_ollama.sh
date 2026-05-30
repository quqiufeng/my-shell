#!/bin/bash
#
# Ollama + Proxy 管理脚本
# 用法: ./start_ollama_proxy.sh {start|stop|status|restart}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
PROXY_SCRIPT="$PARENT_DIR/ollama_proxy.py"
PROXY_LOG="/tmp/ollama_proxy.log"

OLLAMA_PORT=11434
PROXY_PORT=11436

# 检查依赖
if ! command -v ollama &> /dev/null; then
    echo "错误: ollama 未安装"
    exit 1
fi

if [ ! -f "$PROXY_SCRIPT" ]; then
    echo "错误: 未找到代理脚本 $PROXY_SCRIPT"
    exit 1
fi

start() {
    echo "=== 启动 Ollama + Proxy ==="
    
    # 1. 启动 Ollama（systemd）
    if systemctl is-active --quiet ollama; then
        echo "[✓] Ollama 服务已在运行"
    else
        echo "[+] 启动 Ollama 服务..."
        sudo systemctl start ollama
        sleep 2
        if systemctl is-active --quiet ollama; then
            echo "[✓] Ollama 启动成功 (端口: $OLLAMA_PORT)"
        else
            echo "[✗] Ollama 启动失败"
            exit 1
        fi
    fi
    
    # 2. 启动 Proxy
    if pgrep -f "ollama_proxy.py" > /dev/null; then
        echo "[✓] Proxy 已在运行 (端口: $PROXY_PORT)"
    else
        echo "[+] 启动 Proxy 代理..."
        nohup python3 "$PROXY_SCRIPT" > "$PROXY_LOG" 2>&1 &
        sleep 1
        sleep 1
        if pgrep -f "ollama_proxy.py" > /dev/null; then
            echo "[✓] Proxy 启动成功 (端口: $PROXY_PORT -> $OLLAMA_PORT)"
        else
            echo "[✗] Proxy 启动失败"
            exit 1
        fi
    fi
    
    echo ""
    echo "服务状态:"
    status
}

stop() {
    echo "=== 停止 Ollama + Proxy ==="
    
    # 1. 停止 Proxy
    if pgrep -f "ollama_proxy.py" > /dev/null; then
        echo "[-] 停止 Proxy..."
        pkill -f "ollama_proxy.py" 2> /dev/null || true
        sleep 1
        if pgrep -f "ollama_proxy.py" > /dev/null; then
            echo "[!] Proxy 未能完全停止，强制终止..."
            pkill -9 -f "ollama_proxy.py" 2> /dev/null || true
        fi
        echo "[✓] Proxy 已停止"
    else
        echo "[✓] Proxy 未在运行"
    fi
    
    # 2. 停止 Ollama
    if systemctl is-active --quiet ollama; then
        echo "[-] 停止 Ollama 服务..."
        sudo systemctl stop ollama
        sleep 1
        if systemctl is-active --quiet ollama; then
            echo "[!] Ollama 未能完全停止"
        else
            echo "[✓] Ollama 已停止"
        fi
    else
        echo "[✓] Ollama 未在运行"
    fi
}

status() {
    echo "=== 服务状态 ==="
    
    # Ollama 状态
    if systemctl is-active --quiet ollama; then
        echo "[运行中] Ollama  (端口: $OLLAMA_PORT)"
    else
        echo "[已停止] Ollama  (端口: $OLLAMA_PORT)"
    fi
    
    # Proxy 状态
    if pgrep -f "ollama_proxy.py" > /dev/null; then
        PID=$(pgrep -f "ollama_proxy.py" | head -1)
        echo "[运行中] Proxy   (端口: $PROXY_PORT -> $OLLAMA_PORT, PID: $PID)"
    else
        echo "[已停止] Proxy   (端口: $PROXY_PORT)"
    fi
    
    echo ""
    echo "可用模型:"
    ollama list 2> /dev/null || echo "  (Ollama 未运行)"
}

restart() {
    stop
    echo ""
    start
}

# 主逻辑
case "${1:-}" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    status)
        status
        ;;
    restart)
        restart
        ;;
    *)
        echo "用法: $0 {start|stop|status|restart}"
        echo ""
        echo "命令:"
        echo "  start   - 启动 Ollama 服务和 Proxy 代理"
        echo "  stop    - 停止 Ollama 服务和 Proxy 代理"
        echo "  status  - 查看服务状态"
        echo "  restart - 重启服务"
        exit 1
        ;;
esac
