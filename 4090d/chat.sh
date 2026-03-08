#!/bin/bash

INSTANCE_ID=${XGC_INSTANCE_ID:-$(hostname)}

case "$1" in
    start)
        cd /opt/my-shell/4090d
        pkill -f "chat.py" 2>/dev/null
        sleep 2
        python3 chat.py > /tmp/gradio.log 2>&1 &
        sleep 5
        
        echo ""
        echo "=============================="
        echo "Chat 服务已启动!"
        echo "=============================="
        echo "对内地址: http://localhost:7860"
        echo "对外地址: http://${INSTANCE_ID}-7860.container.x-gpu.com"
        echo "=============================="
        ;;
    stop)
        pkill -f "chat.py"
        echo "已停止"
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    *)
        echo "用法: $0 {start|stop|restart}"
        ;;
esac
