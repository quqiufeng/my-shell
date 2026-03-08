import gradio as gr
import requests
import os

api_url = "http://localhost:11434/v1/chat/completions"
INSTANCE_ID = os.environ.get('XGC_INSTANCE_ID', 'unknown')

def chat(message, history):
    all_messages = []
    if history:
        for h in history:
            if isinstance(h, (list, tuple)) and len(h) >= 2:
                all_messages.append({"role": "user", "content": str(h[0])})
                all_messages.append({"role": "assistant", "content": str(h[1])})
    all_messages.append({"role": "user", "content": message})
    
    response = ""
    
    resp = requests.post(
        api_url,
        json={"messages": all_messages, "max_tokens": 4096, "stream": True},
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
                        yield response
                except:
                    pass

demo = gr.ChatInterface(
    chat,
    title="🤖 ExLlamaV2 Qwen2.5-Coder",
    description=f"**对内地址:** http://localhost:7860 | **对外地址:** http://{INSTANCE_ID}-7860.container.x-gpu.com",
)

if __name__ == "__main__":
    demo.launch(
        server_name="0.0.0.0", 
        server_port=7860,
        head="<script src='https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js'></script>"
    )
