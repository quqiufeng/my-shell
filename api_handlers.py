#!/usr/bin/env python3
"""
API 处理函数共享库
基于 Qwen35Chat 库 (exllamav3)

提供 ExLlamaV3 模型脚本共用
"""

import json
import time
import re
from typing import Dict, List, Optional, Any, Callable
from functools import partial

from chat import Qwen35Chat, Qwen35Server


def parse_tool_calls(text: str, tools: Optional[List] = None) -> Optional[List[Dict]]:
    """
    解析工具调用，支持多种格式

    Args:
        text: 模型输出的文本
        tools: 工具定义列表，用于验证函数名是否匹配
    """
    if tools is None:
        tools = []

    tool_names = {t.get("function", {}).get("name") for t in tools}

    def is_valid_call(func_name: str) -> bool:
        """如果提供了 tools 列表，则验证函数名是否在列表中"""
        if not tool_names:
            return True
        return func_name in tool_names

    try:
        # Qwen2.5 的 <response>{JSON}</response> 格式
        response_json_match = re.search(
            r"<response>\s*(\{.*?\})\s*</response>", text, re.DOTALL
        )
        if response_json_match:
            data = json.loads(response_json_match.group(1))
            if isinstance(data, dict) and "name" in data and "arguments" in data:
                if is_valid_call(data["name"]):
                    return [
                        {
                            "id": f"call_{int(time.time() * 1000)}",
                            "type": "function",
                            "function": {
                                "name": data["name"],
                                "arguments": json.dumps(data["arguments"])
                                if isinstance(data["arguments"], dict)
                                else str(data["arguments"]),
                            },
                        }
                    ]

        # Qwen2.5 的 <response><function-call> 格式
        response_match = re.search(
            r"<response>\s*<function-call>\s*<name>(\w+)</name>\s*<arguments>(.*?)</arguments>\s*</function-call>\s*</response>",
            text,
            re.DOTALL,
        )
        if response_match:
            func_name = response_match.group(1)
            if is_valid_call(func_name):
                arguments_str = response_match.group(2)
                arguments = {}
                for arg_match in re.finditer(
                    r"<(\w+)>(.*?)</\1>", arguments_str, re.DOTALL
                ):
                    arg_name = arg_match.group(1)
                    arg_value = arg_match.group(2).strip()
                    try:
                        arguments[arg_name] = json.loads(arg_value)
                    except:
                        arguments[arg_name] = arg_value
                return [
                    {
                        "id": f"call_{int(time.time() * 1000)}",
                        "type": "function",
                        "function": {
                            "name": func_name,
                            "arguments": json.dumps(arguments),
                        },
                    }
                ]

        # Qwen2.5 的 <xml><function-call> 格式
        xml_match = re.search(
            r"<xml>\s*<function-call>\s*<name>(\w+)</name>\s*<arguments>(.*?)</arguments>\s*</function-call>\s*</xml>",
            text,
            re.DOTALL,
        )
        if xml_match:
            func_name = xml_match.group(1)
            if is_valid_call(func_name):
                arguments_str = xml_match.group(2)
                arguments = {}
                for arg_match in re.finditer(
                    r"<(\w+)>(.*?)</\1>", arguments_str, re.DOTALL
                ):
                    arg_name = arg_match.group(1)
                    arg_value = arg_match.group(2).strip()
                    try:
                        arguments[arg_name] = json.loads(arg_value)
                    except:
                        arguments[arg_name] = arg_value
                return [
                    {
                        "id": f"call_{int(time.time() * 1000)}",
                        "type": "function",
                        "function": {
                            "name": func_name,
                            "arguments": json.dumps(arguments),
                        },
                    }
                ]

        # Qwen2.5 的 <xml>{JSON}</xml> 格式
        xml_json_match = re.search(r"<xml>\s*(\{.*?\})\s*</xml>", text, re.DOTALL)
        if xml_json_match:
            data = json.loads(xml_json_match.group(1))
            if isinstance(data, dict) and "name" in data and "arguments" in data:
                if is_valid_call(data["name"]):
                    return [
                        {
                            "id": f"call_{int(time.time() * 1000)}",
                            "type": "function",
                            "function": {
                                "name": data["name"],
                                "arguments": json.dumps(data["arguments"])
                                if isinstance(data["arguments"], dict)
                                else str(data["arguments"]),
                            },
                        }
                    ]

        # 尝试解析 <function=NAME><parameter=KEY>VALUE</parameter>...</function> 格式
        func_match = re.search(r"<function=(\w+)>(.*?)</function>", text, re.DOTALL)
        if func_match:
            func_name = func_match.group(1)
            if is_valid_call(func_name):
                arguments_str = func_match.group(2)
                arguments = {}
                for arg_match in re.finditer(
                    r"<parameter=(\w+)>(.*?)</parameter>", arguments_str, re.DOTALL
                ):
                    arg_name = arg_match.group(1)
                    arg_value = arg_match.group(2).strip()
                    try:
                        arguments[arg_name] = json.loads(arg_value)
                    except:
                        arguments[arg_name] = arg_value
                if arguments:
                    return [
                        {
                            "id": f"call_{int(time.time() * 1000)}",
                            "type": "function",
                            "function": {
                                "name": func_name,
                                "arguments": json.dumps(arguments),
                            },
                        }
                    ]

        # 尝试解析 <tool_call> 格式
        tool_call_match = re.search(r"<tool_call>(.*?)</tool_call>", text, re.DOTALL)
        if tool_call_match:
            data = json.loads(tool_call_match.group(1).strip())
            if isinstance(data, dict) and "name" in data and "arguments" in data:
                return [
                    {
                        "id": f"call_{int(time.time() * 1000)}",
                        "type": "function",
                        "function": {
                            "name": data["name"],
                            "arguments": json.dumps(data["arguments"])
                            if isinstance(data["arguments"], dict)
                            else str(data["arguments"]),
                        },
                    }
                ]

        # 尝试解析 <tools> 格式
        tools_match = re.search(r"<tools>(.*?)</tools>", text, re.DOTALL)
        if tools_match:
            data = json.loads(tools_match.group(1).strip())
            if isinstance(data, dict) and "name" in data:
                if is_valid_call(data["name"]):
                    return [
                        {
                            "id": f"call_{int(time.time() * 1000)}",
                            "type": "function",
                            "function": {
                                "name": data["name"],
                                "arguments": json.dumps(data.get("arguments", {}))
                                if isinstance(data.get("arguments"), dict)
                                else str(data.get("arguments", {})),
                            },
                        }
                    ]

        # 尝试直接解析 JSON（需要有 tools 定义才处理）
        if tool_names and text.strip().startswith("{"):
            data = json.loads(text.strip())
            if isinstance(data, dict) and "name" in data and "arguments" in data:
                if is_valid_call(data["name"]):
                    return [
                        {
                            "id": f"call_{int(time.time() * 1000)}",
                            "type": "function",
                            "function": {
                                "name": data["name"],
                                "arguments": json.dumps(data["arguments"])
                                if isinstance(data["arguments"], dict)
                                else str(data["arguments"]),
                            },
                        }
                    ]
    except:
        pass
    return None


def build_prompt(
    messages: List[Dict],
    tools: Optional[List] = None,
    default_system: str = "You are a helpful assistant.",
) -> str:
    """
    构建带工具的 Prompt（手动拼接方式）

    适用于 Qwen2.5 等原生支持 chat template 的模型。
    ExLlamaV3 的 tokenizer 会自动使用模型内置模板，不需要外部指定。
    """
    if tools is None:
        tools = []

    tools_def = ""
    if tools:
        tools_def = "\n\n# Tools\n\nYou may call one or more functions to assist with the user query.\n\nYou are provided with function signatures within <tools></tools> XML tags:\n<tools>\n"
        for tool in tools:
            name = tool.get("function", {}).get("name", "")
            desc = tool.get("function", {}).get("description", "")
            params = tool.get("function", {}).get("parameters", {})
            tools_def += f"{json.dumps({'name': name, 'description': desc, 'parameters': params})}\n"
        tools_def += '</tools>\n\nFor each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\n<tool_call>\n{"name": "<function-name>", "arguments": <args-json-object>}\n</tool_call>'

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

    if not system_set:
        prompt = f"<|im_start|>system\n{default_system}{tools_def}<|im_end|>\n" + prompt

    prompt += "<|im_start|>assistant\n"
    return prompt


class Qwen35APIHandler:
    """Qwen3.5 API 处理句柄"""

    def __init__(
        self,
        model_dir: str,
        max_seq_len: int = 131072,
        cache_tokens: int = 65536,
        max_batch_size: int = 1,
        max_chunk_size: int = 2048,
        model_name: str = "qwen3.5-exl3",
        default_system_prompt: str = "You are a helpful assistant. Do not think step by step. Answer directly and concisely.",
        cache_type: str = "quant",
    ):
        self.model_name = model_name
        self.max_seq_len = max_seq_len
        self.default_system_prompt = default_system_prompt

        self.chat = Qwen35Chat(
            model_dir=model_dir,
            max_seq_len=max_seq_len,
            cache_tokens=cache_tokens,
            max_batch_size=max_batch_size,
            max_chunk_size=max_chunk_size,
            cache_type=cache_type,
        )

    def load(self, progressbar: bool = True):
        """加载模型"""
        self.chat.load(progressbar=progressbar)

    def unload(self):
        """卸载模型"""
        self.chat.unload()

    async def generate_completion(self, data: Dict) -> Dict:
        """
        核心生成逻辑 - 支持工具调用

        Args:
            data: 包含 messages, tools, max_tokens 等字段的字典

        Returns:
            OpenAI Chat Completion 格式的响应
        """
        messages = data.get("messages", [])
        tools = data.get("tools", [])
        max_tokens = data.get("max_tokens", self.max_seq_len - 1024)
        temperature = data.get("temperature", 0.0)
        system_prompt = data.get("system_prompt", self.default_system_prompt)

        prompt = self.chat.format_prompt(messages, system_prompt)
        full_text = self.chat.generate_text(
            prompt,
            max_new_tokens=max_tokens,
            temperature=temperature,
        )

        input_len = self.chat.get_token_count(prompt)
        output_len = self.chat.get_token_count(full_text)

        tool_calls = parse_tool_calls(full_text, tools)

        if tool_calls:
            return {
                "id": f"chatcmpl-{int(time.time() * 1000)}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": data.get("model", self.model_name),
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "tool_calls": tool_calls},
                        "finish_reason": "tool_calls",
                    }
                ],
                "usage": {
                    "prompt_tokens": input_len,
                    "completion_tokens": output_len,
                    "total_tokens": input_len + output_len,
                },
            }
        else:
            return {
                "id": f"chatcmpl-{int(time.time() * 1000)}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": data.get("model", self.model_name),
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": full_text},
                        "finish_reason": "stop",
                    }
                ],
                "usage": {
                    "prompt_tokens": input_len,
                    "completion_tokens": output_len,
                    "total_tokens": input_len + output_len,
                },
            }

    async def generate_completion_stream(self, data: Dict):
        """
        流式生成逻辑

        Yields:
            SSE 格式的数据块
        """
        messages = data.get("messages", [])
        max_tokens = data.get("max_tokens", self.max_seq_len - 1024)
        temperature = data.get("temperature", 0.0)
        system_prompt = data.get("system_prompt", self.default_system_prompt)

        prompt = self.chat.format_prompt(messages, system_prompt)
        tool_calls_sent = False

        for chunk in self.chat.chat_stream(
            message="",  # 空消息，因为 prompt 已经格式化好了
            system_prompt=system_prompt,
            history=messages[:-1] if messages else [],
            max_new_tokens=max_tokens,
            temperature=temperature,
        ):
            # 由于 chat_stream 不返回完整文本，我们需要重新处理
            pass

        # 使用底层流式接口
        import torch
        from exllamav3.generator.sampler import ComboSampler
        from exllamav3.generator import Job

        sampler = ComboSampler(
            temperature=temperature,
            top_p=0.9,
            min_p=0.0,
            top_k=0,
            rep_p=1.0,
            rep_decay_range=1024,
        )

        input_ids = self.chat.tokenizer.encode(prompt, add_bos=False)

        job = Job(
            input_ids=input_ids,
            max_new_tokens=max_tokens,
            sampler=sampler,
            stop_conditions=["<|im_end|>", "<|im_start|>"],
        )

        self.chat.generator.enqueue(job)
        full_output = ""

        while self.chat.generator.num_remaining_jobs():
            for r in self.chat.generator.iterate():
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


async def responses_endpoint(request, handler: Qwen35APIHandler, default_model: str):
    """OpenAI Responses API 端点处理"""
    from fastapi import Request

    data = await request.json()

    messages = []
    input_data = data.get("input", "")
    if isinstance(input_data, str):
        messages = [{"role": "user", "content": input_data}]
    elif isinstance(input_data, list):
        messages = input_data

    tools = data.get("tools", [])
    chat_data = {
        "model": data.get("model", default_model),
        "messages": messages,
        "tools": tools,
        "tool_choice": "auto" if tools else None,
        "max_tokens": data.get("max_output_tokens", 4096),
        "stream": False,
    }

    result = await handler.generate_completion(chat_data)

    message = result.get("choices", [{}])[0].get("message", {})
    content = message.get("content", "")
    tool_calls = message.get("tool_calls", [])

    output = []
    if tool_calls:
        for tc in tool_calls:
            output.append(
                {
                    "type": "function_call",
                    "id": tc.get("id", ""),
                    "call_id": tc.get("id", ""),
                    "name": tc.get("function", {}).get("name", ""),
                    "arguments": tc.get("function", {}).get("arguments", ""),
                }
            )
    elif content:
        output.append(
            {
                "type": "message",
                "role": "assistant",
                "content": [{"type": "output_text", "text": content}],
            }
        )

    return {
        "id": result.get("id", ""),
        "object": "response",
        "created_at": result.get("created", int(time.time())),
        "model": result.get("model", ""),
        "output": output,
        "usage": result.get("usage", {}),
        "status": "completed",
        "incomplete": False,
        "incomplete_details": None,
    }


def create_api_server(
    model_dir: str,
    port: int = 11434,
    host: str = "0.0.0.0",
    **kwargs,
) -> Qwen35Server:
    """
    创建 API 服务器

    Args:
        model_dir: 模型目录路径
        port: 端口
        host: 主机地址
        **kwargs: 传递给 Qwen35Server 的其他参数

    Returns:
        Qwen35Server 实例
    """
    server = Qwen35Server(
        model_dir=model_dir,
        port=port,
        host=host,
        **kwargs,
    )
    return server
