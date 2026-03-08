import streamlit as st
import requests
import os

api_url = "http://localhost:11434/v1/chat/completions"

INSTANCE_ID = os.environ.get('XGC_INSTANCE_ID', '未知')

st.set_page_config(page_title="ExLlamaV2 Chat", page_icon="🤖")
st.title("🤖 ExLlamaV2 Qwen2.5-Coder")

st.markdown(f"""
<div style="padding: 10px; background: #1e1e1e; border-radius: 5px; margin-bottom: 20px;">
    <b>对内地址:</b> <code>http://localhost:8501</code><br>
    <b>对外地址:</b> <code>http://{INSTANCE_ID}-8501.container.x-gpu.com</code>
</div>
""", unsafe_allow_html=True)

st.markdown("""
<style>
.stMarkdown pre, .stCodeBlock pre, .markdown-text-container pre {
    white-space: pre-wrap !important;
    word-wrap: break-word !important;
    background-color: #1e1e1e !important;
    padding: 10px !important;
    border-radius: 5px !important;
}
.stMarkdown code, .stCodeBlock code {
    background-color: #1e1e1e !important;
    padding: 2px 5px !important;
    border-radius: 3px !important;
}
</style>
""", unsafe_allow_html=True)

if "messages" not in st.session_state:
    st.session_state.messages = []

for msg in st.session_state.messages:
    with st.chat_message(msg["role"]):
        st.markdown(msg["content"])

if prompt := st.chat_input("输入消息..."):
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)
    
    # 流式输出容器
    placeholder = st.empty()
    response = ""
    
    # 传入完整对话历史
    resp = requests.post(
        api_url,
        json={"messages": st.session_state.messages, "max_tokens": 4096, "stream": True},
        stream=True,
        timeout=300
    )
    
    for line in resp.iter_lines():
        if line:
            line = line.decode('utf-8')
            if line.startswith("data: "):
                data = line[6:]
                if data.strip() == "[DONE]":
                    break
                try:
                    import json
                    d = json.loads(data)
                    content = d.get("choices", [{}])[0].get("delta", {}).get("content", "")
                    if content:
                        response += content
                        placeholder.markdown(response, unsafe_allow_html=True)
                except:
                    pass
    
    st.session_state.messages.append({"role": "assistant", "content": response})
