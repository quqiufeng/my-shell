#!/usr/bin/env python3

# =============================================================================
# 性能测试数据 (2026-04-01, branch.py):
# - 测试配置: 30个高难度提示词, max_tokens=200
# - 平均速度: 51.0 tokens/s
# - 速度范围: 33.1 - 73.0 tokens/s
# - 最快测试: 字典树(73.0), 拓扑排序(65.8), 双指针(62.1)
# - 最慢测试: 数据库索引(33.1), 快速排序(39.2), B+树(39.0)
#
# 使用方法:
#   1. 启动模型: nohup python3 run_qwen2.5-coder-32b_exl2.py > /tmp/model.log 2>&1 &
#   2. 等待加载: curl http://localhost:11434/v1/models
#   3. 性能测试: cd /opt/my-shell && python3 branch.py 11434 qwen2.5-coder-32b-exl2 200
#   4. 关闭模型: pkill -f run_qwen2.5-coder-32b_exl2.py
#
# 注意: 32B速度最慢但质量最高，适合需要高质量代码的场景
# =============================================================================

# =============================================================================
# 依赖安装 (首次运行前执行)
# =============================================================================
# ⚠️ 重要: 安装 FlashAttention 可提升 50%+ 速度
# 编译安装 (针对 RTX 4090D):
#   bash /opt/my-shell/4090d/build_flash_attention.sh
#
# 验证安装:
# python3 -c "import flash_attn; print(flash_attn.__version__)"
# =============================================================================

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

app = FastAPI()

MAIN_MODEL_DIR = "/opt/gguf/exl2_4_0"
DRAFT_MODEL_DIR = "/opt/gguf/Qwen2.5-Coder-0.5B-exl2"

MAX_SEQ_LEN = 32768
PORT = 11434
NUM_SPECULATIVE_TOKENS = 6  # 最优配置: 8投机反而下降

print("Loading main model...")

config = ExLlamaV2Config(MAIN_MODEL_DIR)
config.max_seq_len = MAX_SEQ_LEN
config.no_flash_attn = False  # 确保启用FlashAttention
config.no_sdpa = False         # 禁用SDPA，强制用FlashAttention
config.no_xformers = False     # 禁用xformers
model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q4(model, lazy=True)  # Q4 KV Cache (速度最快)
model.load_autosplit(cache)

print("Loading draft model...")

draft_config = ExLlamaV2Config(DRAFT_MODEL_DIR)
draft_config.max_seq_len = MAX_SEQ_LEN
draft_config.no_flash_attn = False
draft_config.no_sdpa = False
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

@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [{
            "id": "qwen2.5-coder-32b-exl2",
            "object": "model",
            "created": 1677610602,
            "owned_by": "qwen",
            "permission": [],
            "root": "qwen2.5-coder-32b-exl2"
        }]
    }

@app.post("/v1/responses")
async def responses(request: Request):
    """OpenAI Responses API - 非流式响应"""
    data = await request.json()
    
    # 转换 input 为 messages
    messages = []
    input_data = data.get("input", "")
    if isinstance(input_data, str):
        messages = [{"role": "user", "content": input_data}]
    elif isinstance(input_data, list):
        messages = input_data
    
    # 构建 chat.completions 请求
    tools = data.get("tools", [])
    chat_data = {
        "model": data.get("model", "qwen2.5-coder-32b-exl2"),
        "messages": messages,
        "tools": tools,
        "tool_choice": "auto" if tools else None,
        "max_tokens": data.get("max_output_tokens", 4096),
        "stream": False
    }
    
    # 调用生成逻辑
    result = await generate_completion(chat_data)
    
    # 检查是否是 tool_calls
    message = result.get("choices", [{}])[0].get("message", {})
    content = message.get("content", "")
    tool_calls = message.get("tool_calls", [])
    
    # 构建 output
    output = []
    if tool_calls:
        for tc in tool_calls:
            output.append({
                "type": "function_call",
                "id": tc.get("id", ""),
                "call_id": tc.get("id", ""),
                "name": tc.get("function", {}).get("name", ""),
                "arguments": tc.get("function", {}).get("arguments", "")
            })
    elif content:
        output.append({
            "type": "message",
            "role": "assistant",
            "content": [{"type": "output_text", "text": content}]
        })
    
    return {
        "id": result.get("id", ""),
        "object": "response",
        "created_at": result.get("created", int(time.time())),
        "model": result.get("model", ""),
        "output": output,
        "usage": result.get("usage", {}),
        "status": "completed",
        "incomplete": False,
        "incomplete_details": None
    }

async def generate_completion(data):
    """核心生成逻辑"""
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    
    print(f"[REQUEST] messages count={len(messages)}, tools={len(tools)}")
    if messages:
        print(f"[REQUEST] last msg: {messages[-1].get('content', '')[:100]}")
    
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
        tokens = result['chunk_token_ids']
        
        if chunk:
            full_text += chunk
            gen_tokens = tokens.shape[1] if hasattr(tokens, 'shape') else len(tokens)
            generated += gen_tokens
        
        if eos:
            break
    
    # 检查是否是 tool call
    def parse_tool_calls(text):
        try:
            data = json.loads(text.strip())
            if isinstance(data, dict) and "name" in data and "arguments" in data:
                return [{
                    "id": f"call_{int(time.time()*1000)}",
                    "type": "function",
                    "function": {
                        "name": data["name"],
                        "arguments": json.dumps(data["arguments"]) if isinstance(data["arguments"], dict) else str(data["arguments"])
                    }
                }]
        except:
            pass
        return None
    
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

@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    data = await request.json()
    messages = data.get("messages", [])
    # 支持工具调用
    tools = data.get("tools", [])
    model_name = data.get("model", "qwen2.5-coder-32b-exl2")
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    stream = data.get("stream", False)
    
    print(f"[REQUEST] stream={stream}, messages count={len(messages)}, tools={len(tools)}")
    if messages:
        print(f"[REQUEST] last msg: {messages[-1].get('content', '')[:100]}")
    
    prompt = build_prompt(messages, tools)

    input_ids = tokenizer.encode(prompt)
    if isinstance(input_ids, tuple):
        input_ids = input_ids[0]

    if stream:
        def generate():
            import json
            import time
            eos = False
            generated = 0
            full_output = ""
            tool_calls_sent = False
            generator.begin_stream(input_ids, settings)
            
            while generated < max_tokens:
                result = generator.stream_ex()
                chunk = result['chunk']
                eos = result['eos']
                tokens = result['chunk_token_ids']
                
                if chunk:
                    gen_tokens = tokens.shape[1] if hasattr(tokens, 'shape') else len(tokens)
                    generated += gen_tokens
                    full_output += chunk
                    
                    if not tool_calls_sent:
                        try:
                            data = json.loads(full_output.strip())
                            if isinstance(data, dict) and "name" in data and "arguments" in data:
                                tool_call = [{
                                    "id": f"call_{int(time.time()*1000)}",
                                    "type": "function",
                                    "index": 0,
                                    "function": {
                                        "name": data["name"],
                                        "arguments": json.dumps(data["arguments"]) if isinstance(data["arguments"], dict) else str(data["arguments"])
                                    }
                                }]
                                data = {"choices": [{"delta": {"role": "assistant", "tool_calls": tool_call}, "finish_reason": "tool_calls"}]}
                                yield f"data: {json.dumps(data)}\n\n"
                                tool_calls_sent = True
                                continue
                        except:
                            pass
                        
                        data = {"choices": [{"delta": {"content": chunk}, "finish_reason": None}], "usage": {"prompt_tokens": input_ids.shape[-1], "completion_tokens": generated}}
                        yield f"data: {json.dumps(data)}\n\n"
                
                if eos:
                    # 发送带有 finish_reason 的最终消息
                    if not tool_calls_sent:
                        tool_calls = parse_tool_calls(full_output) if 'parse_tool_calls' in globals() else None
                        if tool_calls:
                            data = {"choices": [{"delta": {"role": "assistant", "tool_calls": tool_call}, "finish_reason": "tool_calls"}]}
                            yield f"data: {json.dumps(data)}\n\n"
                        else:
                            # 普通回复，发送 finish_reason: stop (OpenAI 格式要求 delta 为空对象)
                            data = {"choices": [{"delta": {}, "finish_reason": "stop"}]}
                            yield f"data: {json.dumps(data)}\n\n"
                    yield "data: [DONE]\n\n"
                    break
            
            if not eos:
                if not tool_calls_sent:
                    tool_calls = parse_tool_calls(full_output) if 'parse_tool_calls' in globals() else None
                    if tool_calls:
                        data = {"choices": [{"delta": {"role": "assistant", "tool_calls": tool_calls}, "finish_reason": "tool_calls"}]}
                        yield f"data: {json.dumps(data)}\n\n"
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
                gen_tokens = tokens.shape[1] if hasattr(tokens, 'shape') else len(tokens)
                generated += gen_tokens
            
            if eos:
                break
        
        import json
        import time
        
        def parse_tool_calls(text):
            try:
                data = json.loads(text.strip())
                if isinstance(data, dict) and "name" in data and "arguments" in data:
                    return [{
                        "id": f"call_{int(time.time()*1000)}",
                        "type": "function",
                        "function": {
                            "name": data["name"],
                            "arguments": json.dumps(data["arguments"]) if isinstance(data["arguments"], dict) else str(data["arguments"])
                        }
                    }]
            except:
                pass
            return None
        
        tool_calls = parse_tool_calls(full_text)
        
        if tool_calls:
            response = {
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
                    "prompt_tokens": input_ids.shape[-1],
                    "completion_tokens": generated,
                    "total_tokens": input_ids.shape[-1] + generated
                }
            }
        else:
            response = {
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
        
        return response


def build_prompt(messages, tools=None):
    if tools is None:
        tools = []
    if not messages:
        return ""
    
    # Qwen2.5 工具调用格式
    tools_def = ""
    if tools:
        tools_def = "\n\n# Tools\n\nYou may call one or more functions to assist with the user query.\n\nYou are provided with function signatures within <tools></tools> XML tags:\n<tools>\n"
        for tool in tools:
            name = tool.get("function", {}).get("name", "")
            desc = tool.get("function", {}).get("description", "")
            params = tool.get("function", {}).get("parameters", {})
            tools_def += f'{json.dumps({"name": name, "description": desc, "parameters": params})}\n'
        tools_def += "</tools>\n\nFor each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\n<tool_call>\n{\"name\": \"<function-name>\", \"arguments\": <args-json-object>}\n</tool_call>"
    
    prompt = ""
    system_set = False
    
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")
        
        if role == "system":
            prompt += f"<|im_start|>system\n{content}{tools_def}<|im_end|>\n"
            system_set = True
        elif role == "user":
            prompt += f"<|im_start|>user\n{content}<|im_end|>\n"
        elif role == "assistant":
            # 处理 assistant 消息，可能是字符串或列表
            if isinstance(content, str):
                prompt += f"<|im_start|>assistant\n{content}<|im_end|>\n"
            elif isinstance(content, list):
                # 处理 content 是列表的情况 (如 OpenAI 格式)
                text_content = ""
                for item in content:
                    if isinstance(item, dict):
                        if item.get("type") == "text":
                            text_content += item.get("text", "")
                        elif item.get("type") == "input_text":
                            text_content += item.get("text", "")
                if text_content:
                    prompt += f"<|im_start|>assistant\n{text_content}<|im_end|>\n"
    
    # 如果没有 system 消息，添加默认的（包含明确的停止指令）
    if not system_set:
        system_msg = """You are a helpful coding assistant.

IMPORTANT: When you finish answering the user's question, do NOT ask follow-up questions or suggest next steps. Simply end your response. The conversation should stop after your answer."""
        prompt = f"<|im_start|>system\n{system_msg}{tools_def}<|im_end|>\n" + prompt
    
    # 添加最后的 assistant 标记
    prompt += "<|im_start|>assistant\n"
    return prompt

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)


# =============================================================================
# 性能测试代码 - 用于评估模型推理性能
# 使用方法: 每次运行下面的 python -c 命令跑一个提示词，连续运行15次
# 每次 python -c 只跑一个，防止超时
# =============================================================================

# 性能测试 - 高难度Python代码生成任务
# 共15个测试，每次运行一条命令

# 测试1: 红黑树
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个红黑树数据结构'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试2: B+树
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个B+树'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试3: A*寻路
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个A*寻路算法'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试4: 布隆过滤器
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个布隆过滤器'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试5: LRU-K缓存
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个LRU-K缓存淘汰算法'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试6: 阻塞队列
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个线程安全的阻塞队列'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试7: CAS队列
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个无锁CAS队列'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试8: 外排序
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个支持亿级数据排序的外排序算法'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试9: 协程调度器
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个协程调度器'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试10: vector容器
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个STL风格的vector容器'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试11: 堆排序
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个堆排序'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试12: Dijkstra
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个图的最短路径Dijkstra算法'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试13: 布隆过滤器(重复)
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个布隆过滤器'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试14: 令牌桶
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个实现限流令牌桶算法'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"

# 测试15: 一致性哈希
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个一致性哈希算法'}]},'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); print(f\"{time.time()-t:.2f}s | {len(r.json()['choices'][0]['message']['content'])} | {len(r.json()['choices'][0]['message']['content'])/(time.time()-t):.1f}\")"


# =============================================================================
# 优化记录:
# - 2026-03-08: 初始版本
#   - NUM_SPECULATIVE_TOKENS = 4 (从2调整)
#   - 模型: exl2_4_0 (4bit量化)
#   - 草稿模型: Qwen2.5-Coder-0.5B-exl2
#   - 测试结果: ~100-110 tok/s
#
# 可优化方向:
# 1. NUM_SPECULATIVE_TOKENS: 尝试 3-6 (当前4)
# 2. KV Cache: 尝试 Q6/Q8 (当前Q4) - 需要更多VRAM
# 3. 草稿模型: 尝试更大尺寸的草稿模型 (如1.5B)
# 4. Batch Size: 调整批处理大小
# 5. Flash Attention: 确保启用
# 6. TensorRT: 当前不支持
# =============================================================================


# =============================================================================
# 投机采样接受率测试
# 使用方法: 每次运行一条命令
# =============================================================================

# 测试1: 红黑树 (带接受率)
# python3 -c "import requests, time; url='http://localhost:11434'; data={'messages':[{'role':'user','content':'用Python实现一个红黑树数据结构'}],'max_tokens':800}; t=time.time(); r=requests.post(url+'/v1/chat/completions',json=data,timeout=60); d=r.json()['choices'][0]['message']['content']; print(f\"{time.time()-t:.2f}s | {len(d)} | {len(d)/(time.time()-t):.1f} tok/s\")"

# =============================================================================
# FlashAttention-2 确认方法
# 运行以下命令检查是否安装:
# python3 -c "from flash_attn import flash_attn_func; print('FlashAttention 已安装')"
# =============================================================================
