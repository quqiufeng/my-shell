#!/usr/bin/env python3
"""
Qwen2.5-Coder-14B EXL2 - 优化版本（性能与质量均衡）

【优化配置】
- 上下文: 32k (平衡速度与长文本能力)
- KV Cache: FP16 (不量化，最高速度)
- 量化: 4.25bpw (高精度)
- CUDA Graph: 启用

【性能测试数据】(2026-04-01, branch.py, RTX 4090D)
- 平均速度: 82.6 tokens/s (优化后)
- 速度范围: 65.2 - 89.4 tokens/s
- 最快测试: 编辑距离(89.4), 一致性哈希(89.4), 红黑树(89.2)
- 显存占用: ~15.5GB / 24GB

使用方法:
  1. 启动: nohup python3 run_qwen2.5-coder-14b-4.25_exl2.py > /tmp/model.log 2>&1 &
  2. 测试: cd /opt/my-shell && python3 branch.py 11434 qwen2.5-coder-14b-exl2 200
  3. 关闭: pkill -f run_qwen2.5-coder-14b-4.25_exl2.py

注意: 4.25bpw 精度高于 3.5bpw，适合对代码质量要求高的场景
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
    ExLlamaV2Cache,
    ExLlamaV2Tokenizer,
)
from exllamav2.generator import ExLlamaV2StreamingGenerator, ExLlamaV2Sampler

# 导入共享库（从上级目录）
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from api_handlers import (
    parse_tool_calls,
    build_prompt,
    build_prompt_from_jinja,
    generate_completion,
    responses_endpoint
)

app = FastAPI()

MAIN_MODEL_DIR = "/opt/gguf/Qwen2.5-Coder-14B-Instruct-exl2/4_5"
MAX_SEQ_LEN = 32768
PORT = 11434

print("Loading Qwen2.5-Coder-14B model...")
print(f"Model: {MAIN_MODEL_DIR}")
print(f"Max sequence length: {MAX_SEQ_LEN}")

config = ExLlamaV2Config(MAIN_MODEL_DIR)
config.max_seq_len = MAX_SEQ_LEN
config.no_flash_attn = False
config.no_sdpa = False
config.no_xformers = False
config.no_cuda_graph = False

model = ExLlamaV2(config)
cache = ExLlamaV2Cache(model, lazy=True)
model.load_autosplit(cache)

tokenizer = ExLlamaV2Tokenizer(config)

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
print("🚀 Qwen2.5-Coder-14B 服务已启动!")
print("=" * 60)
print(f"模型: 14B EXL2 (4.25bpw)")
print(f"对内地址: http://localhost:{PORT}")
print(f"对外地址: http://{instance_id}-{PORT}.container.x-gpu.com/v1/chat/completions")
print("=" * 60)
print(f"实际速度: ~82.6 tok/s")
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


@app.post("/v1/responses")
async def responses(request: Request):
    """OpenAI Responses API - 使用共享库"""
    return await responses_endpoint(
        request, 
        lambda data: generate_completion(data, generator, tokenizer, settings, MAX_SEQ_LEN, "qwen2.5-coder-14b-exl2"),
        "qwen2.5-coder-14b-exl2"
    )


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    """OpenAI Chat Completions API - 非流式"""
    data = await request.json()
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    model_name = data.get("model", "qwen2.5-coder-14b-exl2")
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    stream = data.get("stream", False)
    temperature = data.get("temperature", 0.0)
    
    settings.temperature = temperature
    
    if stream:
        # 流式响应
        async def generate_stream():
            prompt = build_prompt_from_jinja(messages, tools, template_name="qwen25-chat-template")
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
                    
                    # 检查是否触发了工具调用
                    if not tool_calls_sent:
                        tool_calls = parse_tool_calls(full_output)
                        if tool_calls:
                            data = {"choices": [{"delta": {"role": "assistant", "tool_calls": tool_calls}, "finish_reason": "tool_calls"}]}
                            yield f"data: {json.dumps(data)}\n\n"
                            tool_calls_sent = True
                            continue
                    
                    if not tool_calls_sent:
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
        # 非流式响应 - 使用 jinja 模板
        prompt = build_prompt_from_jinja(messages, tools, template_name="qwen25-chat-template")
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
        
        tool_calls = parse_tool_calls(full_text, tools)
        
        if tool_calls:
            return {
                "id": f"chatcmpl-{int(time.time()*1000)}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": model_name,
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
                "model": model_name,
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


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
