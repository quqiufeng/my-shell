#!/usr/bin/env python3
"""
Qwen2.5-Coder-32B EXL2 - 高质量版本（投机解码）

【优化配置】
- 主模型: 32B EXL2 4.0bpw + Q4 KV Cache
- 草稿模型: 0.5B EXL2 (投机解码)
- 上下文: 32k (平衡长文本与显存)
- 投机Token: 6 (最优值)
- FlashAttention: 启用

【性能测试数据】(2026-04-01, branch.py, RTX 4090D)
- 平均速度: 51.1 tokens/s
- 速度范围: 33.1 - 73.6 tokens/s
- 显存占用: ~20-22GB / 24GB

使用方法:
  1. 启动: nohup python3 run_qwen2.5-coder-32b_exl2.py > /tmp/model.log 2>&1 &
  2. 测试: cd /opt/my-shell && python3 branch.py 11434 qwen2.5-coder-32b-exl2 200
  3. 关闭: pkill -f run_qwen2.5-coder-32b_exl2.py

注意: 32B模型质量最高，适合复杂算法设计和高质量代码生成
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
from exllamav2 import ExLlamaV2, ExLlamaV2Config, ExLlamaV2Cache_Q4, ExLlamaV2Tokenizer, ExLlamaV2Cache
from exllamav2.generator import ExLlamaV2StreamingGenerator, ExLlamaV2Sampler

# 导入共享库（从上级目录）
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from api_handlers import (
    parse_tool_calls,
    build_prompt,
    responses_endpoint
)

app = FastAPI()

MAIN_MODEL_DIR = "/opt/gguf/exl2_4_0"
DRAFT_MODEL_DIR = "/opt/gguf/Qwen2.5-Coder-0.5B-exl2"

MAX_SEQ_LEN = 32768
PORT = 11434
NUM_SPECULATIVE_TOKENS = 6

print("Loading main model...")

config = ExLlamaV2Config(MAIN_MODEL_DIR)
config.max_seq_len = MAX_SEQ_LEN
config.no_flash_attn = False
config.no_sdpa = False
config.no_xformers = False
model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q4(model, lazy=True)
model.load_autosplit(cache)

print("Loading draft model...")

draft_config = ExLlamaV2Config(DRAFT_MODEL_DIR)
draft_config.max_seq_len = MAX_SEQ_LEN
draft_config.no_flash_attn = False
draft_config.no_sdpa = False
draft_model = ExLlamaV2(draft_config)
draft_cache = ExLlamaV2Cache(draft_model)
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
settings.top_p = 0.9
settings.token_repetition_penalty = 1.0

print(f"VRAM: {torch.cuda.memory_allocated() / 1024**3:.2f} GB")

hostname = socket.gethostname()
instance_id = os.environ.get("XGC_INSTANCE_ID", hostname)

print("")
print("=" * 60)
print("🚀 Qwen2.5-Coder-32B 服务已启动!")
print("=" * 60)
print(f"模型: 32B EXL2 (4.0bpw) + 0.5B 草稿模型")
print(f"对内地址: http://localhost:{PORT}")
print(f"对外地址: http://{instance_id}-{PORT}.container.x-gpu.com/v1/chat/completions")
print("=" * 60)
print(f"实际速度: ~51 tok/s")
print("=" * 60)
sys.stdout.flush()


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {
                "id": "qwen2.5-coder-32b-exl2",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "qwen",
                "permission": [],
                "root": "qwen2.5-coder-32b-exl2",
            }
        ],
    }


async def generate_completion_32b(data):
    """32B 专用生成逻辑 - 支持投机解码"""
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    
    prompt = build_prompt(messages, tools)
    
    input_ids = tokenizer.encode(prompt)
    if isinstance(input_ids, tuple):
        input_ids = input_ids[0]
    
    full_text = ""
    eos = False
    generated = 0
    generator.begin_stream(input_ids, settings)
    
    while generated < max_tokens:
        result = generator.stream_ex()
        chunk = result['chunk']
        eos = result['eos']
        tokens = result.get('chunk_token_ids', None)
        
        if chunk:
            full_text += chunk
            if tokens is not None:
                gen_tokens = tokens.shape[1] if hasattr(tokens, 'shape') else len(tokens)
                generated += gen_tokens
            else:
                generated += 1
        
        if eos:
            break
    
    tool_calls = parse_tool_calls(full_text)
    
    if tool_calls:
        return {
            "id": f"chatcmpl-{int(time.time()*1000)}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": data.get("model", "qwen2.5-coder-32b-exl2"),
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "tool_calls": tool_calls},
                "finish_reason": "tool_calls"
            }],
            "usage": {
                "prompt_tokens": input_ids.shape[-1] if hasattr(input_ids, 'shape') else len(input_ids),
                "completion_tokens": generated,
                "total_tokens": (input_ids.shape[-1] if hasattr(input_ids, 'shape') else len(input_ids)) + generated
            }
        }
    else:
        return {
            "id": f"chatcmpl-{int(time.time()*1000)}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": data.get("model", "qwen2.5-coder-32b-exl2"),
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": full_text},
                "finish_reason": "stop"
            }],
            "usage": {
                "prompt_tokens": input_ids.shape[-1] if hasattr(input_ids, 'shape') else len(input_ids),
                "completion_tokens": generated,
                "total_tokens": (input_ids.shape[-1] if hasattr(input_ids, 'shape') else len(input_ids)) + generated
            }
        }


@app.post("/v1/responses")
async def responses(request: Request):
    """OpenAI Responses API"""
    return await responses_endpoint(
        request,
        generate_completion_32b,
        "qwen2.5-coder-32b-exl2"
    )


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """OpenAI Chat Completions API"""
    data = await request.json()
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    model_name = data.get("model", "qwen2.5-coder-32b-exl2")
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    stream = data.get("stream", False)
    
    if stream:
        # 流式响应
        async def generate_stream():
            prompt = build_prompt(messages, tools)
            input_ids = tokenizer.encode(prompt)
            if isinstance(input_ids, tuple):
                input_ids = input_ids[0]
            
            eos = False
            generated = 0
            full_output = ""
            tool_calls_sent = False
            generator.begin_stream(input_ids, settings)
            
            while generated < max_tokens:
                result = generator.stream_ex()
                chunk = result['chunk']
                eos = result['eos']
                tokens = result.get('chunk_token_ids', None)
                
                if chunk:
                    if tokens is not None:
                        gen_tokens = tokens.shape[1] if hasattr(tokens, 'shape') else len(tokens)
                        generated += gen_tokens
                    else:
                        generated += 1
                    full_output += chunk
                    
                    if not tool_calls_sent:
                        tool_calls = parse_tool_calls(full_output)
                        if tool_calls:
                            data = {"choices": [{"delta": {"role": "assistant", "tool_calls": tool_calls}, "finish_reason": "tool_calls"}]}
                            yield f"data: {json.dumps(data)}\n\n"
                            tool_calls_sent = True
                            continue
                        
                        data = {"choices": [{"delta": {"content": chunk}, "finish_reason": None}], "usage": {"prompt_tokens": input_ids.shape[-1], "completion_tokens": generated}}
                        yield f"data: {json.dumps(data)}\n\n"
                
                if eos:
                    if not tool_calls_sent:
                        data = {"choices": [{"delta": {}, "finish_reason": "stop"}]}
                        yield f"data: {json.dumps(data)}\n\n"
                    yield "data: [DONE]\n\n"
                    break
            
            if not eos and not tool_calls_sent:
                yield "data: [DONE]\n\n"
        
        return StreamingResponse(generate_stream(), media_type="text/event-stream")
    else:
        # 非流式响应
        return await generate_completion_32b(
            {"messages": messages, "tools": tools, "model": model_name, "max_tokens": max_tokens}
        )


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
