#!/usr/bin/env python3
"""
API 处理函数共享库
供 ExLlamaV2 模型脚本共用
"""

import json
import time
import re
from typing import Dict, List, Optional, Any

def parse_tool_calls(text: str) -> Optional[List[Dict]]:
    """解析工具调用，支持多种格式"""
    try:
        # 尝试解析 <tool_call> 格式
        tool_call_match = re.search(r'<tool_call>(.*?)</tool_call>', text, re.DOTALL)
        if tool_call_match:
            data = json.loads(tool_call_match.group(1).strip())
            if isinstance(data, dict) and "name" in data and "arguments" in data:
                return [{
                    "id": f"call_{int(time.time()*1000)}",
                    "type": "function",
                    "function": {
                        "name": data["name"],
                        "arguments": json.dumps(data["arguments"]) if isinstance(data["arguments"], dict) else str(data["arguments"])
                    }
                }]
        
        # 尝试解析 <tools> 格式
        tools_match = re.search(r'<tools>(.*?)</tools>', text, re.DOTALL)
        if tools_match:
            data = json.loads(tools_match.group(1).strip())
            if isinstance(data, dict) and "name" in data:
                return [{
                    "id": f"call_{int(time.time()*1000)}",
                    "type": "function",
                    "function": {
                        "name": data["name"],
                        "arguments": json.dumps(data.get("arguments", {})) if isinstance(data.get("arguments"), dict) else str(data.get("arguments", {}))
                    }
                }]
        
        # 尝试直接解析 JSON
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

def build_prompt(messages: List[Dict], tools: Optional[List] = None, default_system: str = "You are a helpful coding assistant.") -> str:
    """构建带工具的 Prompt"""
    if tools is None:
        tools = []
    
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
        prompt = f"<|im_start|>system\n{default_system}{tools_def}<|im_end|>\n" + prompt
    
    # 添加最后的 assistant 标记
    prompt += "<|im_start|>assistant\n"
    return prompt

async def generate_completion(data: Dict, generator, tokenizer, settings, max_seq_len: int, model_name: str):
    """核心生成逻辑 - 支持工具调用"""
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    max_tokens = data.get("max_tokens", max_seq_len - 1024)
    
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
            "model": data.get("model", model_name),
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
            "model": data.get("model", model_name),
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

async def responses_endpoint(request, generate_completion_func, default_model: str):
    """OpenAI Responses API 端点处理"""
    from fastapi import Request
    
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
        "model": data.get("model", default_model),
        "messages": messages,
        "tools": tools,
        "tool_choice": "auto" if tools else None,
        "max_tokens": data.get("max_output_tokens", 4096),
        "stream": False
    }
    
    # 调用生成逻辑
    result = await generate_completion_func(chat_data)
    
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
