#!/usr/bin/env python3
"""
Qwen3-14B EXL3 启动脚本 - 基于 exllamav3 examples
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
from exllamav3.generator.sampler import ComboSampler

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from api_handlers import parse_tool_calls

app = FastAPI()

MODEL_DIR = "/opt/gguf/Qwen3-14B-exl3"
MAX_SEQ_LEN = 32768
PORT = 11434
CACHE_TOKENS = 8192

print(f"Loading Qwen3-14B model from {MODEL_DIR}...")

config = Config.from_directory(MODEL_DIR)
model = Model.from_config(config)
cache = Cache(model, max_num_tokens=CACHE_TOKENS, layer_type=CacheLayer_fp16)
tokenizer = Tokenizer.from_config(config)

print("Loading model...")
model.load(progressbar=True)

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
print("🚀 Qwen3-14B 服务已启动!")
print("=" * 60)
print(f"模型: Qwen3-14B EXL3")
print(f"对内地址: http://localhost:{PORT}")
print("=" * 60)
sys.stdout.flush()


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {
                "id": "qwen3-14b-exl3",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "qwen",
                "permission": [],
                "root": "qwen3-14b-exl3",
            }
        ],
    }


SYSTEM_PROMPT = "You are a helpful assistant. Do not think step by step. Answer directly and concisely."

def format_prompt(messages):
    """Use tokenizer's built-in template with thinking disabled"""
    # Add system message to disable thinking
    system_msg = {"role": "system", "content": SYSTEM_PROMPT}
    all_messages = [system_msg] + messages
    return tokenizer.hf_render_chat_template(
        all_messages, 
        add_generation_prompt=True,
        think=False
    )


def generate_text(prompt, max_new_tokens=1024, temperature=0.0):
    """Generate using generator.generate() like official example"""
    sampler = ComboSampler(
        temperature=temperature,
        top_p=0.9,
        min_p=0.0,
        top_k=0,
        rep_p=1.0,
        rep_decay_range=1024,
    )
    
    stop_conditions = ["<|im_end|>", "<|im_start|>"]
    
    response = generator.generate(
        prompt=prompt,
        max_new_tokens=max_new_tokens,
        sampler=sampler,
        stop_conditions=stop_conditions,
        completion_only=True,
        add_bos=False,
    )
    return response


async def generate_completion(data):
    """生成逻辑"""
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    
    prompt = format_prompt(messages)
    full_text = generate_text(prompt, max_new_tokens=max_tokens)
    tool_calls = parse_tool_calls(full_text, tools)
    
    input_len = len(tokenizer.encode(prompt))
    output_len = len(tokenizer.encode(full_text))
    
    if tool_calls:
        return {
            "id": f"chatcmpl-{int(time.time()*1000)}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": data.get("model", "qwen3-14b-exl3"),
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "tool_calls": tool_calls},
                "finish_reason": "tool_calls"
            }],
            "usage": {
                "prompt_tokens": input_len,
                "completion_tokens": output_len,
                "total_tokens": input_len + output_len
            }
        }
    else:
        return {
            "id": f"chatcmpl-{int(time.time()*1000)}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": data.get("model", "qwen3-14b-exl3"),
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": full_text},
                "finish_reason": "stop"
            }],
            "usage": {
                "prompt_tokens": input_len,
                "completion_tokens": output_len,
                "total_tokens": input_len + output_len
            }
        }


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """OpenAI Chat Completions API"""
    data = await request.json()
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    model_name = data.get("model", "qwen3-14b-exl3")
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    temperature = data.get("temperature", 0.0)
    stream = data.get("stream", False)
    
    if stream:
        async def generate_stream():
            prompt = format_prompt(messages)
            
            sampler = ComboSampler(
                temperature=temperature,
                top_p=0.9,
                min_p=0.0,
                top_k=0,
                rep_p=1.0,
                rep_decay_range=1024,
            )
            
            input_ids = tokenizer.encode(prompt, add_bos=False)
            
            from exllamav3.generator import Job
            job = Job(
                input_ids=input_ids,
                max_new_tokens=max_tokens,
                sampler=sampler,
                stop_conditions=["<|im_end|>", "<|im_start|>"],
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
                                yield f"data: {json.dumps({'choices': [{'delta': {'role': 'assistant', 'tool_calls': tc}, 'finish_reason': 'tool_calls'}]})}\n\n"
                                tool_calls_sent = True
                                continue
                        
                        yield f"data: {json.dumps({'choices': [{'delta': {'content': chunk}, 'finish_reason': None}]})}\n\n"
                    
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