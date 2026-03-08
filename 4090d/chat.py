import streamlit as st
import requests

api_url = "http://localhost:11434/v1/chat/completions"

st.set_page_config(page_title="ExLlamaV2 Chat", page_icon="🤖")
st.title("🤖 ExLlamaV2 Qwen2.5-Coder")

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
        response = ""
        
        resp = requests.post(
            api_url,
            json={"messages": [{"role": "user", "content": prompt}], "max_tokens": 2048},
            timeout=120
        )
        
        result = resp.json()
        response = result.get("choices", [{}])[0].get("message", {}).get("content", "")
        st.code(response, language="python")
    
    st.session_state.messages.append({"role": "assistant", "content": response})
