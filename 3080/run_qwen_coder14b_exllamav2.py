#!/usr/bin/env python3
#
# 【模型信息】
# 模型: Qwen2.5-Coder-14B-Instruct-exl2
# 框架: ExLlamaV2
# 显存占用: ~10GB (RTX 3080 10GB)
# 上下文: 12K (12288 tokens)
#
# 【性能测试数据 - 30个高难度提示词】
# 平均速度: 53.4 tokens/s
# 最快: 红黑树 59.0 tokens/s
# 最慢: 最长公共子序列 40.4 tokens/s
# 典型速度: 50-58 tokens/s
#
# 【测试方法】
# cd /home/dministrator/my-shell
# python3 branch.py 11434 "qwen2.5-coder-14b-exl2" 200
#
# =============================================================================
# 依赖安装 (首次运行前执行)
# =============================================================================
# ⚠️ 重要: 安装 FlashAttention 可提升 50%+ 速度
# 编译安装 (针对 RTX 3080):
#   bash /opt/my-shell/3080/build_flash_attention.sh
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
from exllamav2 import ExLlamaV2, ExLlamaV2Config, ExLlamaV2Cache_Q4, ExLlamaV2Tokenizer
from exllamav2.generator import ExLlamaV2StreamingGenerator, ExLlamaV2Sampler

app = FastAPI()

# 3080 配置 - 16GB 显存，只加载主模型
MAIN_MODEL_DIR = "/opt/image/Qwen2.5-Coder-14B-Instruct-exl2/3_5"

MAX_SEQ_LEN = 12288  # 12k context - 适合 16GB 显存
PORT = 11434

print("Loading model...")

config = ExLlamaV2Config(MAIN_MODEL_DIR)
config.max_seq_len = MAX_SEQ_LEN
config.no_flash_attn = False  # 确保启用FlashAttention
config.no_sdpa = False  # 禁用SDPA，强制用FlashAttention
config.no_xformers = False  # 禁用xformers
model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q4(model, lazy=True)  # Q4 KV Cache (省显存)
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
import sys

sys.stdout.flush()

hostname = socket.gethostname()
instance_id = os.environ.get("XGC_INSTANCE_ID", hostname)
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
        "stream": False,
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

    # 截断超长输入，保留最后 MAX_SEQ_LEN - max_tokens 个 token
    max_input_len = MAX_SEQ_LEN - max_tokens - 256  # 留 256 token 缓冲
    if hasattr(input_ids, "shape"):
        current_len = input_ids.shape[-1]
    else:
        current_len = len(input_ids)

    if current_len > max_input_len:
        print(
            f"[WARNING] Input too long ({current_len}), truncating to {max_input_len}"
        )
        if hasattr(input_ids, "shape"):
            input_ids = input_ids[:, -max_input_len:]
        else:
            input_ids = input_ids[-max_input_len:]

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

    # 检查是否是 tool call
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
    # 支持工具调用
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

    # 截断超长输入，保留最后 MAX_SEQ_LEN - max_tokens 个 token
    max_input_len = MAX_SEQ_LEN - max_tokens - 256  # 留 256 token 缓冲
    if hasattr(input_ids, "shape"):
        current_len = input_ids.shape[-1]
    else:
        current_len = len(input_ids)

    if current_len > max_input_len:
        print(
            f"[WARNING] Input too long ({current_len}), truncating to {max_input_len}"
        )
        if hasattr(input_ids, "shape"):
            input_ids = input_ids[:, -max_input_len:]
        else:
            input_ids = input_ids[-max_input_len:]

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
                    # 发送带有 finish_reason 的最终消息
                    if not tool_calls_sent:
                        # 检查是否是 tool call
                        try:
                            parsed = json.loads(full_output.strip())
                            if (
                                isinstance(parsed, dict)
                                and "name" in parsed
                                and "arguments" in parsed
                            ):
                                tool_calls = [
                                    {
                                        "id": f"call_{int(time.time() * 1000)}",
                                        "type": "function",
                                        "function": {
                                            "name": parsed["name"],
                                            "arguments": json.dumps(parsed["arguments"])
                                            if isinstance(parsed["arguments"], dict)
                                            else str(parsed["arguments"]),
                                        },
                                    }
                                ]
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
                            else:
                                # 普通回复，发送 finish_reason: stop (OpenAI 格式要求 delta 为空对象)
                                data = {
                                    "choices": [{"delta": {}, "finish_reason": "stop"}]
                                }
                                yield f"data: {json.dumps(data)}\n\n"
                        except:
                            # 普通回复
                            data = {"choices": [{"delta": {}, "finish_reason": "stop"}]}
                            yield f"data: {json.dumps(data)}\n\n"
                    yield "data: [DONE]\n\n"
                    break

            if not eos:
                if not tool_calls_sent:
                    try:
                        parsed = json.loads(full_output.strip())
                        if (
                            isinstance(parsed, dict)
                            and "name" in parsed
                            and "arguments" in parsed
                        ):
                            tool_calls = [
                                {
                                    "id": f"call_{int(time.time() * 1000)}",
                                    "type": "function",
                                    "function": {
                                        "name": parsed["name"],
                                        "arguments": json.dumps(parsed["arguments"])
                                        if isinstance(parsed["arguments"], dict)
                                        else str(parsed["arguments"]),
                                    },
                                }
                            ]
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
                    except:
                        pass
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

    # Qwen2.5 工具调用格式
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
