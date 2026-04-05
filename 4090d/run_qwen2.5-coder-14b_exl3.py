#!/usr/bin/env python3
"""
Qwen2.5-Coder-14B EXL2 - 基于 exllamav3

使用方法:
  1. 启动: nohup python3 run_qwen2.5-coder-14b_exl3.py > /tmp/model_14b.log 2>&1 &
  2. 测试: curl http://localhost:11434/v1/models
  3. 关闭: pkill -f run_qwen2.5-coder-14b_exl3.py
"""

import sys
import time
import socket
import os
import json
import torch
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from exllamav3 import Model, Config, Cache, Tokenizer, Generator
from exllamav3.cache import CacheLayer_fp16
from exllamav3.model_init import add_args, init as model_init
from exllamav3.generator import Job
from exllamav3.generator.sampler import ComboSampler
import argparse

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from api_handlers import (
    parse_tool_calls,
    build_prompt_from_jinja,
    responses_endpoint
)

app = FastAPI()

MODEL_DIR = "/opt/gguf/Qwen2.5-Coder-14B-Instruct-exl2/4_5"
MAX_SEQ_LEN = 32768
PORT = 11434

print(f"Loading Qwen2.5-Coder-14B model from {MODEL_DIR}...")

config = Config.from_directory(MODEL_DIR)
model = Model.from_config(config)
cache = Cache(model, max_num_tokens=MAX_SEQ_LEN, layer_type=CacheLayer_fp16)
tokenizer = Tokenizer.from_config(config)

print("Loading model...")
model.load(use_per_device=None, progressbar=True)

print("Creating generator...")
generator = Generator(
    model=model,
    cache=cache,
    tokenizer=tokenizer,
)

print(f"VRAM: {torch.cuda.memory_allocated() / 1024**3:.2f} GB")

hostname = socket.gethostname()
instance_id = os.environ.get("XGC_INSTANCE_ID", hostname)

print("")
print("=" * 60)
print("🚀 Qwen2.5-Coder-14B 服务已启动! (exllamav3)")
print("=" * 60)
print(f"模型: 14B EXL2 (exllamav3)")
print(f"对内地址: http://localhost:{PORT}")
print(f"对外地址: http://{instance_id}-{PORT}.container.x-gpu.com/v1/chat/completions")
print("=" * 60)
sys.stdout.flush()


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {
                "id": "qwen2.5-coder-14b-exl3",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "qwen",
                "permission": [],
                "root": "qwen2.5-coder-14b-exl3",
            }
        ],
    }


def generate_text(prompt, max_new_tokens=1024, temperature=0.0):
    """Generate text using exllamav3 Generator"""
    input_ids = tokenizer.encode(prompt, add_bos=False)
    
    sampler = ComboSampler(
        rep_p=1.0,
        pres_p=0.0,
        freq_p=0.0,
        rep_sustain_range=1024,
        rep_decay_range=1024,
        temperature=temperature,
        min_p=0.0,
        top_k=0,
        top_p=0.9,
        temp_last=True,
        adaptive_target=1.0,
        adaptive_decay=0.9,
    )
    
    job = Job(
        input_ids=input_ids,
        max_new_tokens=max_new_tokens,
        sampler=sampler,
    )
    
    generator.enqueue(job)
    
    full_text = ""
    while generator.num_remaining_jobs():
        for r in generator.iterate():
            if r["stage"] == "streaming":
                full_text += r.get("text", "")
            if r.get("eos"):
                return full_text
    
    return full_text


async def generate_completion(data):
    """生成逻辑"""
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    
    prompt = build_prompt_from_jinja(messages, tools, template_name="qwen25-chat-template")
    
    full_text = generate_text(prompt, max_new_tokens=max_tokens)
    tool_calls = parse_tool_calls(full_text, tools)
    
    if tool_calls:
        return {
            "id": f"chatcmpl-{int(time.time()*1000)}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": data.get("model", "qwen2.5-coder-14b-exl3"),
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "tool_calls": tool_calls},
                "finish_reason": "tool_calls"
            }],
            "usage": {
                "prompt_tokens": len(tokenizer.encode(prompt)),
                "completion_tokens": len(tokenizer.encode(full_text)),
                "total_tokens": len(tokenizer.encode(prompt)) + len(tokenizer.encode(full_text))
            }
        }
    else:
        return {
            "id": f"chatcmpl-{int(time.time()*1000)}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": data.get("model", "qwen2.5-coder-14b-exl3"),
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": full_text},
                "finish_reason": "stop"
            }],
            "usage": {
                "prompt_tokens": len(tokenizer.encode(prompt)),
                "completion_tokens": len(tokenizer.encode(full_text)),
                "total_tokens": len(tokenizer.encode(prompt)) + len(tokenizer.encode(full_text))
            }
        }


@app.post("/v1/responses")
async def responses(request: Request):
    """OpenAI Responses API"""
    return await responses_endpoint(
        request,
        generate_completion,
        "qwen2.5-coder-14b-exl3"
    )


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """OpenAI Chat Completions API"""
    data = await request.json()
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    model_name = data.get("model", "qwen2.5-coder-14b-exl3")
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    temperature = data.get("temperature", 0.0)
    stream = data.get("stream", False)
    
    if stream:
        async def generate_stream():
            prompt = build_prompt_from_jinja(messages, tools, template_name="qwen25-chat-template")
            input_ids = tokenizer.encode(prompt, add_bos=False)
            
            sampler = ComboSampler(
                rep_p=1.0,
                pres_p=0.0,
                freq_p=0.0,
                rep_sustain_range=1024,
                rep_decay_range=1024,
                temperature=temperature,
                min_p=0.0,
                top_k=0,
                top_p=0.9,
                temp_last=True,
                adaptive_target=1.0,
                adaptive_decay=0.9,
            )
            
            job = Job(
                input_ids=input_ids,
                max_new_tokens=max_tokens,
                sampler=sampler,
            )
            
            generator.enqueue(job)
            full_output = ""
            tool_calls_sent = False
            
            while generator.num_remaining_jobs():
                for r in generator.iterate():
                    if r["stage"] == "streaming":
                        chunk = r.get("text", "")
                        full_output += chunk
                        
                        if not tool_calls_sent:
                            tc = parse_tool_calls(full_output)
                            if tc:
                                data = {"choices": [{"delta": {"role": "assistant", "tool_calls": tc}, "finish_reason": "tool_calls"}]}
                                yield f"data: {json.dumps(data)}\n\n"
                                tool_calls_sent = True
                                continue
                        
                        data = {"choices": [{"delta": {"content": chunk}, "finish_reason": None}]}
                        yield f"data: {json.dumps(data)}\n\n"
                    
                    if r.get("eos"):
                        if not tool_calls_sent:
                            yield f"data: {json.dumps({'choices': [{'delta': {}, 'finish_reason': 'stop'}]})}\n\n"
                        yield "data: [DONE]\n\n"
                        return
            
            if not tool_calls_sent:
                yield "data: [DONE]\n\n"
        
        return StreamingResponse(generate_stream(), media_type="text/event-stream")
    else:
        return await generate_completion({
            "messages": messages,
            "tools": tools,
            "model": model_name,
            "max_tokens": max_tokens
        })


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)