#!/usr/bin/env python3
import sys
import time
import socket
import os
import torch
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from exllamav2 import ExLlamaV2, ExLlamaV2Config, ExLlamaV2Cache_Q4, ExLlamaV2Tokenizer, ExLlamaV2Cache
from exllamav2.generator import ExLlamaV2StreamingGenerator, ExLlamaV2Sampler

app = FastAPI()

MAIN_MODEL_DIR = "/opt/gguf/exl2_4_0"
DRAFT_MODEL_DIR = "/opt/gguf/Qwen2.5-Coder-0.5B-exl2"

MAX_SEQ_LEN = 32768
PORT = 11434
NUM_SPECULATIVE_TOKENS = 2

print("Loading main model...")

config = ExLlamaV2Config(MAIN_MODEL_DIR)
config.max_seq_len = MAX_SEQ_LEN
model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q4(model, lazy=True)  # 优化: Q4 KV Cache
model.load_autosplit(cache)

print("Loading draft model...")

draft_config = ExLlamaV2Config(DRAFT_MODEL_DIR)
draft_config.max_seq_len = MAX_SEQ_LEN
draft_model = ExLlamaV2(draft_config)
draft_cache = ExLlamaV2Cache(draft_model)  # 草稿模型用默认 cache
draft_model.load_autosplit(draft_cache)

tokenizer = ExLlamaV2Tokenizer(config)

generator = ExLlamaV2StreamingGenerator(
    model=model,
    cache=cache,
    tokenizer=tokenizer,
    draft_model=draft_model,
    draft_cache=draft_cache,
    num_speculative_tokens=NUM_SPECULATIVE_TOKENS,
)

settings = ExLlamaV2Sampler.Settings()
settings.temperature = 0.0
settings.token_repetition_penalty = 1.0

print(f"VRAM: {torch.cuda.memory_allocated()/1024**3:.2f} GB")
import sys
sys.stdout.flush()

hostname = socket.gethostname()
instance_id = os.environ.get('XGC_INSTANCE_ID', hostname)
ip = socket.gethostbyname(hostname)

print("")
print("==============================")
print("服务已启动!")
print("==============================")
print(f"对内地址: http://localhost:{PORT}")
print(f"对外地址: http://{instance_id}-{PORT}.container.x-gpu.com/v1/chat/completions")
print(f"IP: {ip}")
print("==============================")
sys.stdout.flush()

@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    data = await request.json()
    messages = data.get("messages", [])
    prompt = messages[-1]["content"] if messages else ""
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    stream = data.get("stream", False)
    
    input_ids = tokenizer.encode(prompt)

    if stream:
        def generate():
            eos = False
            generated = 0
            generator.begin_stream(input_ids, settings)
            
            while generated < max_tokens:
                result = generator.stream_ex()
                chunk = result['chunk']
                eos = result['eos']
                tokens = result['chunk_token_ids']
                
                if chunk:
                    generated += tokens.shape[1]
                    yield f"data: {{\"choices\": [ {{\"delta\": {{\"content\": \"{chunk}\"}}, \"finish_reason\": null}} ] }}\n\n"
                
                if eos:
                    yield "data: [DONE]\n\n"
                    break
            
            if not eos:
                yield "data: [DONE]\n\n"

        return StreamingResponse(generate(), media_type="text/event-stream")
    else:
        full_text = ""
        eos = False
        generated = 0
        generator.begin_stream(input_ids, settings)
        
        while generated < max_tokens:
            result = generator.stream_ex()
            chunk = result['chunk']
            eos = result['eos']
            tokens = result['chunk_token_ids']
            
            if chunk:
                full_text += chunk
                generated += tokens.shape[1]
            
            if eos:
                break
        
        import json
        return {"choices": [{"message": {"content": full_text}, "finish_reason": "stop"}]}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
