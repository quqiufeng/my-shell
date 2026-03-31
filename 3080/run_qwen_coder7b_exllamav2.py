#!/usr/bin/env python3
#
# 【环境版本要求 - 重要】
#
# GCC:    12.x  (GCC 13 不被 CUDA 12.1 支持)
# CUDA:   12.1  (必须匹配 PyTorch 的 CUDA 版本)
# PyTorch: 2.4.1+cu121  (CUDA 12.1 版本)
#
# 版本匹配关系:
# - PyTorch CUDA 版本必须与系统 nvcc 版本一致
# - GCC 版本必须被 CUDA 版本支持
# - 编译时的 CUDA 版本决定了 .so 文件的兼容性
#
# 编译命令示例:
# export CUDA_HOME=/opt/cuda12.1
# export PATH=/opt/cuda12.1/bin:$PATH
# export CC=/usr/bin/gcc-12
# export CXX=/usr/bin/g++-12
# export TORCH_CUDA_ARCH_LIST="8.6"
# python setup.py build
#
# RTX 3080: compute capability 8.6
#

import sys
import time
import socket
import os
import json

# Fix for missing PyTorch libraries
os.environ["LD_LIBRARY_PATH"] = (
    "/home/dministrator/anaconda3/envs/dl/lib/python3.10/site-packages/torch/lib:"
    + os.environ.get("LD_LIBRARY_PATH", "")
)

import torch
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from exllamav2 import (
    ExLlamaV2,
    ExLlamaV2Config,
    ExLlamaV2Cache_Q6,  # Q6 提供更好的质量/速度平衡
    ExLlamaV2Tokenizer,
    ExLlamaV2Cache,
)
from exllamav2.generator import ExLlamaV2StreamingGenerator, ExLlamaV2Sampler

app = FastAPI()

MAIN_MODEL_DIR = "/opt/image/Qwen2.5-Coder-7B-Instruct-exl2"

MAX_SEQ_LEN = 65536  # 64k context - 测试极限
PORT = 11434

print("Loading main model...")

config = ExLlamaV2Config(MAIN_MODEL_DIR)
config.max_seq_len = MAX_SEQ_LEN
config.no_flash_attn = False
config.no_sdpa = False
config.no_xformers = False
config.no_cuda_graph = True  # Disable CUDA Graph to prevent JIT hang
model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q6(model, lazy=True)
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
instance_id = os.environ.get("XGC_INSTANCE_ID", hostname)
ip = socket.gethostbyname(hostname)

print("")
print("==============================")
print("ExLlamaV2 服务已启动! (3080)")
print("==============================")
print(f"模型: Qwen2.5-Coder-14B-Instruct-exl2")
print(f"位宽: 3.5 bpw")
print(f"对内地址: http://localhost:{PORT}")
print(f"对外地址: http://{instance_id}-{PORT}.container.x-gpu.com/v1/chat/completions")
print(f"IP: {ip}")
print("==============================")
sys.stdout.flush()


@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [
            {
                "id": "qwen2.5-coder-14b-exl2",
                "object": "model",
                "created": 1677610602,
                "owned_by": "qwen",
                "permission": [],
                "root": "qwen2.5-coder-14b-exl2",
            }
        ],
    }


@app.post("/v1/responses")
async def responses(request: Request):
    data = await request.json()

    messages = []
    input_data = data.get("input", "")
    if isinstance(input_data, str):
        messages = [{"role": "user", "content": input_data}]
    elif isinstance(input_data, list):
        messages = input_data

    tools = data.get("tools", [])
    chat_data = {
        "model": data.get("model", "qwen2.5-coder-14b-exl2"),
        "messages": messages,
        "tools": tools,
        "tool_choice": "auto" if tools else None,
        "max_tokens": data.get("max_output_tokens", 4096),
        "stream": False,
    }

    result = await generate_completion(chat_data)

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


async def generate_completion(data):
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
        chunk = result["chunk"]
        eos = result["eos"]
        tokens = result["chunk_token_ids"]

        if chunk:
            full_text += chunk
            gen_tokens = tokens.shape[1] if hasattr(tokens, "shape") else len(tokens)
            generated += gen_tokens

        if eos:
            break

    def parse_tool_calls(text):
        try:
            data = json.loads(text.strip())
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
        except:
            pass
        return None

    tool_calls = parse_tool_calls(full_text)

    if tool_calls:
        return {
            "id": f"chatcmpl-{int(time.time() * 1000)}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": data.get("model", "qwen2.5-coder-14b-exl2"),
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "tool_calls": tool_calls},
                    "finish_reason": "tool_calls",
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
    else:
        return {
            "id": f"chatcmpl-{int(time.time() * 1000)}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": data.get("model", "qwen2.5-coder-14b-exl2"),
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


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    data = await request.json()
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    model_name = data.get("model", "qwen2.5-coder-14b-exl2")
    max_tokens = data.get("max_tokens", MAX_SEQ_LEN - 1024)
    stream = data.get("stream", False)

    print(
        f"[REQUEST] stream={stream}, messages count={len(messages)}, tools={len(tools)}"
    )
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
                chunk = result["chunk"]
                eos = result["eos"]
                tokens = result["chunk_token_ids"]

                if chunk:
                    gen_tokens = (
                        tokens.shape[1] if hasattr(tokens, "shape") else len(tokens)
                    )
                    generated += gen_tokens
                    full_output += chunk

                    if not tool_calls_sent:
                        try:
                            data = json.loads(full_output.strip())
                            if (
                                isinstance(data, dict)
                                and "name" in data
                                and "arguments" in data
                            ):
                                tool_call = [
                                    {
                                        "id": f"call_{int(time.time() * 1000)}",
                                        "type": "function",
                                        "index": 0,
                                        "function": {
                                            "name": data["name"],
                                            "arguments": json.dumps(data["arguments"])
                                            if isinstance(data["arguments"], dict)
                                            else str(data["arguments"]),
                                        },
                                    }
                                ]
                                data = {
                                    "choices": [
                                        {
                                            "delta": {
                                                "role": "assistant",
                                                "tool_calls": tool_call,
                                            },
                                            "finish_reason": "tool_calls",
                                        }
                                    ]
                                }
                                yield f"data: {json.dumps(data)}\n\n"
                                tool_calls_sent = True
                                continue
                        except:
                            pass

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

                if eos:
                    if not tool_calls_sent:
                        tool_calls = (
                            parse_tool_calls(full_output)
                            if "parse_tool_calls" in globals()
                            else None
                        )
                        if tool_calls:
                            data = {
                                "choices": [
                                    {
                                        "delta": {
                                            "role": "assistant",
                                            "tool_calls": tool_call,
                                        },
                                        "finish_reason": "tool_calls",
                                    }
                                ]
                            }
                            yield f"data: {json.dumps(data)}\n\n"
                        else:
                            data = {"choices": [{"delta": {}, "finish_reason": "stop"}]}
                            yield f"data: {json.dumps(data)}\n\n"
                    yield "data: [DONE]\n\n"
                    break

            if not eos:
                if not tool_calls_sent:
                    tool_calls = (
                        parse_tool_calls(full_output)
                        if "parse_tool_calls" in globals()
                        else None
                    )
                    if tool_calls:
                        data = {
                            "choices": [
                                {
                                    "delta": {
                                        "role": "assistant",
                                        "tool_calls": tool_calls,
                                    },
                                    "finish_reason": "tool_calls",
                                }
                            ]
                        }
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

        import json
        import time

        def parse_tool_calls(text):
            try:
                data = json.loads(text.strip())
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
            except:
                pass
            return None

        tool_calls = parse_tool_calls(full_text)

        if tool_calls:
            response = {
                "id": f"chatcmpl-{int(time.time() * 1000)}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": model_name,
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "tool_calls": tool_calls},
                        "finish_reason": "tool_calls",
                    }
                ],
                "usage": {
                    "prompt_tokens": input_ids.shape[-1],
                    "completion_tokens": generated,
                    "total_tokens": input_ids.shape[-1] + generated,
                },
            }
        else:
            response = {
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

        return response


def build_prompt(messages, tools=None):
    if tools is None:
        tools = []
    if not messages:
        return ""

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
        system_msg = """You are a helpful coding assistant.

IMPORTANT: When you finish answering the user's question, do NOT ask follow-up questions or suggest next steps. Simply end your response. The conversation should stop after your answer."""
        prompt = f"<|im_start|>system\n{system_msg}{tools_def}<|im_end|>\n" + prompt

    prompt += "<|im_start|>assistant\n"
    return prompt


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
