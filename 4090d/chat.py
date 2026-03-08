import streamlit as st
import requests
import os
import socket

# 动态获取外网地址
hostname = socket.gethostname()
instance_id = os.environ.get('XGC_INSTANCE_ID', hostname)
api_url = "http://localhost:11434/v1/chat/completions"

st.set_page_config(page_title="ExLlamaV2 Chat", page_icon="🤖")

st.title("🤖 ExLlamaV2 Qwen2.5-Coder")
st.markdown(f"**API**: `{api_url}`")

if "messages" not in st.session_state:
    st.session_state.messages = []

for msg in st.session_state.messages:
    with st.chat_message(msg["role"]):
        st.markdown(msg["content"])

if prompt := st.chat_input("输入消息..."):
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)
    
    with st.chat_message("assistant"):
        with st.spinner("生成中..."):
            resp = requests.post(
                api_url,
                json={"messages": [{"role": "user", "content": prompt}], "max_tokens": 2048},
                timeout=120
            )
            result = resp.json()
            response = result.get("choices", [{}])[0].get("message", {}).get("content", "")
            st.markdown(response)
    
    st.session_state.messages.append({"role": "assistant", "content": response})
