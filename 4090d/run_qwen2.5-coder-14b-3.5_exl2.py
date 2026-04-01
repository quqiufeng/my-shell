#!/usr/bin/env python3
"""
Qwen2.5-Coder-14B EXL2 - 极速版本（无投机解码）
预期速度: 150-200 tok/s
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
from exllamav2 import (
    ExLlamaV2,
    ExLlamaV2Config,
    ExLlamaV2Cache_Q4,
    ExLlamaV2Tokenizer,
)
from exllamav2.generator import ExLlamaV2StreamingGenerator, ExLlamaV2Sampler

app = FastAPI()

MAIN_MODEL_DIR = "/opt/gguf/Qwen2.5-Coder-14B-Instruct-exl2/3_5"
MAX_SEQ_LEN = 4096  # Reduced from 65k for speed
PORT = 11435

print("Loading Qwen2.5-Coder-14B model...")
print(f"Model: {MAIN_MODEL_DIR}")
print(f"Max sequence length: {MAX_SEQ_LEN}")

config = ExLlamaV2Config(MAIN_MODEL_DIR)
config.max_seq_len = MAX_SEQ_LEN
config.no_flash_attn = False
config.no_sdpa = False
config.no_xformers = False
config.no_cuda_graph = False  # Enable CUDA Graph for speed

model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q4(model, lazy=True)
model.load_autosplit(cache)

tokenizer = ExLlamaV2Tokenizer(config)

# 纯模型，无投机解码
generator = ExLlamaV2StreamingGenerator(
    model=model,
    cache=cache,
    tokenizer=tokenizer,
)

settings = ExLlamaV2Sampler.Settings()
settings.temperature = 0.0
settings.top_p = 0.9
settings.token_repetition_penalty = 1.0

print(f"VRAM: {torch.cuda.memory_allocated() / 1024**3:.2f} GB")
sys.stdout.flush()

hostname = socket.gethostname()
instance_id = os.environ.get("XGC_INSTANCE_ID", hostname)

print("")
print("=" * 60)
print("🚀 Qwen2.5-Coder-14B 极速服务已启动!")
print("=" * 60)
print(f"模型: 14B EXL2 (3.5bpw)")
print(f"对内地址: http://localhost:{PORT}")
print(f"对外地址: http://{instance_id}-{PORT}.container.x-gpu.com/v1/chat/completions")
print("=" * 60)
print("预期速度: 100-130 tok/s (4090D limit)")
print("=" * 60)
sys.stdout.flush()


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {
                "id": "qwen2.5-coder-14b-exl2",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "qwen",
                "permission": [],
                "root": "qwen2.5-coder-14b-exl2",
            }
        ],
    }


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    data = await request.json()
    messages = data.get("messages", [])
    model_name = data.get("model", "qwen2.5-coder-14b-exl2")
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    stream = data.get("stream", False)
    temperature = data.get("temperature", 0.0)

    settings.temperature = temperature

    prompt = build_prompt(messages)
    input_ids = tokenizer.encode(prompt)
    if isinstance(input_ids, tuple):
        input_ids = input_ids[0]

    if stream:

        def generate():
            eos = False
            generated = 0
            generator.begin_stream(input_ids, settings)

            while generated < max_tokens and not eos:
                result = generator.stream_ex()
                chunk = result["chunk"]
                eos = result["eos"]

                if chunk:
                    data = {
                        "choices": [
                            {"delta": {"content": chunk}, "finish_reason": None}
                        ],
                        "usage": {
                            "prompt_tokens": input_ids.shape[-1],
                            "completion_tokens": generated,
                        },
                    }
                    yield f"data: {json.dumps(data)}\n\n"
                    generated += 1

                if eos:
                    data = {"choices": [{"delta": {}, "finish_reason": "stop"}]}
                    yield f"data: {json.dumps(data)}\n\n"
                    yield "data: [DONE]\n\n"
                    break

            if not eos:
                yield "data: [DONE]\n\n"

        return StreamingResponse(generate(), media_type="text/event-stream")
    else:
        full_text = ""
        eos = False
        generated = 0
        start_time = time.time()
        generator.begin_stream(input_ids, settings)

        while generated < max_tokens and not eos:
            result = generator.stream_ex()
            chunk = result["chunk"]
            eos = result["eos"]

            if chunk:
                full_text += chunk
                generated += 1

        elapsed = time.time() - start_time
        speed = generated / elapsed if elapsed > 0 else 0

        return {
            "id": f"chatcmpl-{int(time.time() * 1000)}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": model_name,
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": full_text},
                    "finish_reason": "stop",
                }
            ],
            "usage": {
                "prompt_tokens": input_ids.shape[-1],
                "completion_tokens": generated,
                "total_tokens": input_ids.shape[-1] + generated,
            },
        }


def build_prompt(messages):
    prompt = ""
    system_set = False

    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")

        if role == "system":
            prompt += f"<|im_start|>system\n{content}<|im_end|>\n"
            system_set = True
        elif role == "user":
            prompt += f"<|im_start|>user\n{content}<|im_end|>\n"
        elif role == "assistant":
            prompt += f"<|im_start|>assistant\n{content}<|im_end|>\n"

    if not system_set:
        system_msg = "You are Qwen2.5-Coder-14B, a helpful coding assistant."
        prompt = f"<|im_start|>system\n{system_msg}<|im_end|>\n" + prompt

    prompt += "<|im_start|>assistant\n"
    return prompt


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
