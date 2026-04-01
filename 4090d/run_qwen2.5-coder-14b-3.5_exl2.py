#!/usr/bin/env python3
"""
Qwen2.5-Coder-14B EXL2 - 极速版本（无投机解码）

性能测试数据 (2026-04-01, branch.py):
- 测试配置: 30个高难度提示词, max_tokens=200
- 平均速度: 81.9 tokens/s
- 速度范围: 60.0 - 92.1 tokens/s
- 最快测试: 字典树(92.1), KMP算法(92.0), 阻塞队列(91.8)
- 最慢测试: 快速排序(60.0), 线程安全(69.0), 动态规划(76.9)

使用方法:
  1. 启动模型: nohup python3 run_qwen2.5-coder-14b-3.5_exl2.py > /tmp/model.log 2>&1 &
  2. 等待加载: curl http://localhost:11435/v1/models
  3. 性能测试: cd /opt/my-shell && python3 branch.py 11435 qwen2.5-coder-14b-exl2 200
  4. 关闭模型: pkill -f run_qwen2.5-coder-14b-3.5_exl2.py
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
MAX_SEQ_LEN = 32768  # 32k context for long code files
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
print("预期速度: 60-70 tok/s (32k ctx, 4090D limit)")
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
        "model": data.get("model", "qwen2.5-coder-14b-exl2"),
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
    """核心生成逻辑 - 支持工具调用"""
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
            "model": data.get("model", "qwen2.5-coder-14b-exl2"),
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
            "model": data.get("model", "qwen2.5-coder-14b-exl2"),
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
    model_name = data.get("model", "qwen2.5-coder-14b-exl2")
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    stream = data.get("stream", False)
    temperature = data.get("temperature", 0.0)
    
    settings.temperature = temperature
    
    prompt = build_prompt(messages, tools)
    
    input_ids = tokenizer.encode(prompt)
    if isinstance(input_ids, tuple):
        input_ids = input_ids[0]

    if stream:
        def generate():
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
                        try:
                            data_json = json.loads(full_output.strip())
                            if isinstance(data_json, dict) and "name" in data_json and "arguments" in data_json:
                                tool_call = [{
                                    "id": f"call_{int(time.time()*1000)}",
                                    "type": "function",
                                    "index": 0,
                                    "function": {
                                        "name": data_json["name"],
                                        "arguments": json.dumps(data_json["arguments"]) if isinstance(data_json["arguments"], dict) else str(data_json["arguments"])
                                    }
                                }]
                                resp_data = {"choices": [{"delta": {"role": "assistant", "tool_calls": tool_call}, "finish_reason": "tool_calls"}]}
                                yield f"data: {json.dumps(resp_data)}\n\n"
                                tool_calls_sent = True
                                continue
                        except:
                            pass
                        
                        resp_data = {"choices": [{"delta": {"content": chunk}, "finish_reason": None}], "usage": {"prompt_tokens": input_ids.shape[-1], "completion_tokens": generated}}
                        yield f"data: {json.dumps(resp_data)}\n\n"
                
                if eos:
                    if not tool_calls_sent:
                        resp_data = {"choices": [{"delta": {}, "finish_reason": "stop"}]}
                        yield f"data: {json.dumps(resp_data)}\n\n"
                    yield "data: [DONE]\n\n"
                    break
            
            if not eos and not tool_calls_sent:
                yield "data: [DONE]\n\n"

        return StreamingResponse(generate(), media_type="text/event-stream")
    else:
        # 使用 generate_completion 函数处理非流式请求
        return await generate_completion({
            "messages": messages,
            "tools": tools,
            "model": model_name,
            "max_tokens": max_tokens
        })


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
    
    # 如果没有 system 消息，添加默认的
    if not system_set:
        system_msg = "You are Qwen2.5-Coder-14B, a helpful coding assistant."
        prompt = f"<|im_start|>system\n{system_msg}{tools_def}<|im_end|>\n" + prompt
    
    # 添加最后的 assistant 标记
    prompt += "<|im_start|>assistant\n"
    return prompt


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
