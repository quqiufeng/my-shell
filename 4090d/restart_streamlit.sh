#!/bin/bash
# Streamlit 自动重启脚本

while true; do
    if ! pgrep -f "streamlit" > /dev/null; then
        echo "$(date): Streamlit 挂了，重启中..."
        cd /opt/my-shell/4090d
        nohup streamlit run chat.py --server.port 8501 --server.address 0.0.0.0 --server.headless=true > /tmp/st.log 2>&1 &
    fi
    sleep 10
done
