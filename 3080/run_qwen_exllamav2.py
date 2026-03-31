#!/usr/bin/env python3

import sys
import time
import socket
import os
import json
import torch
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from exllamav2.model import ExLlamaV2
from exllamav2.config import ExLlamaV2Config
from exllamav2.cache import ExLlamaV2Cache_Q4
from exllamav2.tokenizer.tokenizer import ExLlamaV2Tokenizer
from exllamav2.generator.streaming import ExLlamaV2StreamingGenerator
from exllamav2.generator.sampler import ExLlamaV2Sampler

app = FastAPI()

MODEL_DIR = "/opt/image/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled"
MAX_SEQ_LEN = 32768
PORT = 11435

print("Loading model...")

config = ExLlamaV2Config(MODEL_DIR)
config.max_seq_len = MAX_SEQ_LEN
config.no_flash_attn = False
config.no_sdpa = False
model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q4(model, lazy=True)
model.load_autosplit(cache)

tokenizer = ExLlamaV2Tokenizer(config)

generator = ExLlamaV2StreamingGenerator(
    model=model,
    cache=cache,
    tokenizer=tokenizer,
)

settings = ExLlamaV2Sampler.Settings()
settings.temperature = 0.0
settings.token_repetition_penalty = 1.0

print(f"VRAM: {torch.cuda.memory_allocated() / 1024**3:.2f} GB")
sys.stdout.flush()

hostname = socket.gethostname()
ip = socket.gethostbyname(hostname)

print("")
print("==============================")
print("ExLlamaV2 服务已启动! (3080)")
print("==============================")
print(f"模型: Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled")
print(f"地址: http://localhost:{PORT}")
print(f"IP: {ip}")
print("==============================")
sys.stdout.flush()


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {
                "id": "qwen3.5-9b-reasoning",
                "object": "model",
                "created": 1677610602,
                "owned_by": "qwen",
                "permission": [],
                "root": "qwen3.5-9b-reasoning",
            }
        ],
    }


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    data = await request.json()
    messages = data.get("messages", [])
    max_tokens = data.get("max_tokens", 4096)
    stream = data.get("stream", False)

    print(f"[REQUEST] stream={stream}, messages={len(messages)}")

    prompt = build_prompt(messages)
    input_ids = tokenizer.encode(prompt)
    if isinstance(input_ids, tuple):
        input_ids = input_ids[0]

    if stream:

        def generate():
            eos = False
            generated = 0
            full_output = ""
            first_chunk = True
            generator.begin_stream(input_ids, settings)

            while generated < max_tokens:
                result = generator.stream_ex()
                chunk = result["chunk"]
                eos = result["eos"]
                tokens = result["chunk_token_ids"]

                if chunk:
                    gen_tokens = (
                        tokens.shape[1] if hasattr(tokens, "shape") else len(tokens)
                    )
                    generated += gen_tokens
                    full_output += chunk

                    data = {
                        "choices": [
                            {"delta": {"content": chunk}, "finish_reason": None}
                        ]
                    }
                    yield f"data: {json.dumps(data)}\n\n"

                if eos:
                    data = {"choices": [{"delta": {}, "finish_reason": "stop"}]}
                    yield f"data: {json.dumps(data)}\n\n"
                    yield "data: [DONE]\n\n"
                    break

            if not eos:
                yield f"data: {json.dumps({'choices': [{'delta': {}, 'finish_reason': 'stop'}]})}\n\n"
                yield "data: [DONE]\n\n"

        return StreamingResponse(generate(), media_type="text/event-stream")
    else:
        full_text = ""
        eos = False
        generated = 0
        generator.begin_stream(input_ids, settings)

        while generated < max_tokens:
            result = generator.stream_ex()
            chunk = result["chunk"]
            eos = result["eos"]
            tokens = result["chunk_token_ids"]

            if chunk:
                full_text += chunk
                gen_tokens = (
                    tokens.shape[1] if hasattr(tokens, "shape") else len(tokens)
                )
                generated += gen_tokens

            if eos:
                break

        return {
            "id": f"chatcmpl-{int(time.time() * 1000)}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": "qwen3.5-9b-reasoning",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": full_text},
                    "finish_reason": "stop",
                }
            ],
            "usage": {
                "prompt_tokens": input_ids.shape[-1]
                if hasattr(input_ids, "shape")
                else len(input_ids),
                "completion_tokens": generated,
                "total_tokens": (
                    input_ids.shape[-1]
                    if hasattr(input_ids, "shape")
                    else len(input_ids)
                )
                + generated,
            },
        }


def build_prompt(messages):
    if not messages:
        return ""

    prompt = ""
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")

        if role == "system":
            prompt += f"<|im_start|>system\n{content}<|im_end|>\n"
        elif role == "user":
            prompt += f"<|im_start|>user\n{content}<|im_end|>\n"
        elif role == "assistant":
            if isinstance(content, str):
                prompt += f"<|im_start|>assistant\n{content}<|im_end|>\n"

    prompt += "<|im_start|>assistant\n"
    return prompt


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
