#!/bin/bash

case "$1" in
    start)
        cd /opt/my-shell/4090d
        pkill -f "streamlit" 2>/dev/null
        sleep 2
        python3 -m streamlit run chat.py --server.port 8501 --server.address 0.0.0.0 --browser.gatherUsageStats=false --server.headless=true > /tmp/st.log 2>&1 &
        sleep 5
        curl -s http://localhost:8501 | head -1
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
