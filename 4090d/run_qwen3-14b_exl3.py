#!/usr/bin/env python3
"""
Qwen3-14B EXL3 启动脚本 - 基于 exllamav3 examples

性能测试数据 (14B @ 4bpw, 4090D 24GB):
  - Cache: 16384 tokens
  - 速度: ~67 tok/s
  - VRAM: ~12GB

测试用例:
  ("快速排序", "用Python实现快速排序，要求支持自定义比较函数，并添加详细注释说明时间复杂度和空间复杂度"),
  ("线程安全", "解释什么是线程安全，用Python示例说明竞态条件和死锁问题，并提供解决方案"),
  ("二分查找", "写一个通用的二分查找函数，支持查找第一个/最后一个匹配元素，处理边界情况"),
  ("数据库索引", "解释B+树索引原理，对比哈希索引和全文索引的适用场景，分析索引失效情况"),
  ("Python性能优化", "详细分析Python代码性能瓶颈，介绍Cython、Numba、多进程等优化方案并给出示例"),
  ("归并排序", "用Python实现归并排序，要求支持链表排序，分析递归和迭代的实现差异"),
  ("HTTP/HTTPS", "详细解释HTTP与HTTPS的区别，包括TLS握手过程、证书验证机制、中间人攻击防护"),
  ("LRU缓存", "用Python实现线程安全的LRU缓存，使用OrderedDict和双向链表两种方法，分析时间复杂度"),
  ("堆排序", "用Python实现堆排序，包括构建堆、调整堆的详细过程，分析不稳定排序的原因"),
  ("Dijkstra算法", "用Python实现Dijkstra最短路径算法，支持优先队列优化，处理负权边情况"),
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
CACHE_TOKENS = 65536

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
    max_batch_size=32,
    max_chunk_size=512,
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
    
    def get_token_len(ids):
        if isinstance(ids, torch.Tensor):
            return ids.shape[-1] if ids.dim() > 0 else 1
        elif isinstance(ids, tuple):
            return ids[0].shape[-1] if hasattr(ids[0], 'shape') and ids[0].dim() > 0 else len(ids[0])
        return len(ids) if hasattr(ids, '__len__') else 1
    
    input_ids = tokenizer.encode(prompt)
    output_ids = tokenizer.encode(full_text)
    input_len = get_token_len(input_ids)
    output_len = get_token_len(output_ids)
    
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