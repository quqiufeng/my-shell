#!/bin/bash

INSTANCE_ID=${XGC_INSTANCE_ID:-$(hostname)}

case "$1" in
    start)
        cd /opt/my-shell/4090d
        pkill -f "streamlit" 2>/dev/null
        sleep 2
        python3 -m streamlit run chat.py --server.port 8501 --server.address 0.0.0.0 --browser.gatherUsageStats=false --server.headless=true > /tmp/st.log 2>&1 &
        sleep 5
        curl -s http://localhost:8501 | head -1 > /dev/null
        
        echo ""
        echo "=============================="
        echo "Chat 服务已启动!"
        echo "=============================="
        echo "对内地址: http://localhost:8501"
        echo "对外地址: http://${INSTANCE_ID}-8501.container.x-gpu.com"
        echo "=============================="
        ;;
    stop)
        pkill -f "streamlit"
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
