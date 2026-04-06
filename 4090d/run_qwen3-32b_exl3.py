#!/usr/bin/env python3
"""
Qwen3-32B EXL3 启动脚本 - RTX 4090D 24GB

================================================================================
启动参数说明
================================================================================

[必需]
  --model-dir         模型目录路径 (默认: /opt/gguf/Qwen3-32B-exl3/3_5)

[可选]
  --port              API 服务端口 (默认: 11434)
  --host              监听地址 (默认: 0.0.0.0)
  --cache-tokens      KV Cache token 数 (默认: 8192)
  --max-new-tokens    单次最大生成 token 数 (默认: 1024)
  --interactive       交互式聊天模式 (默认: False)
  --think             启用思考模式 (默认: False)

[性能参数 - RTX 4090D 24GB 优化]
  Cache: 8192 tokens (Q4 KV Cache, k_bits=4, v_bits=4)
  max_batch_size=1, max_chunk_size=256
  max_seq_len: 32768
  VRAM: ~13.86GB
  速度: ~40 tok/s (无 speculative decoding)

================================================================================
nohup 启动命令 (日志保存到 /tmp)
================================================================================

# 启动服务
nohup python3 /home/dministrator/my-shell/4090d/run_qwen3-32b_exl3.py > /tmp/qwen3_32b_exl3_$(date +%Y%m%d_%H%M%S).log 2>&1 & echo $!

# 查看日志
tail -f /tmp/qwen3_32b_exl3_*.log

# 查看进程
ps aux | grep run_qwen3-32b_exl3

# 停止服务
pkill -f run_qwen3-32b_exl3

================================================================================
OpenCode 配置
================================================================================

配置文件路径: ~/.opencode/opencode.json

配置内容:
{
  "$schema": "https://opencode.ai/config.json",
  "model": "openai/qwen3-32b-exl3",
  "provider": {
    "openai": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local Models",
      "options": {
        "baseURL": "http://localhost:11434/v1",
        "apiKey": "dummy"
      },
      "models": {
        "qwen3-32b-exl3": {
          "name": "Qwen3-32B-EXL3 (本地4090D)",
          "maxContextWindow": 32768,
          "maxOutputTokens": 32768
        }
      }
    }
  }
}

================================================================================
性能测试数据
================================================================================

[测试环境]
- GPU: RTX 4090D 24GB
- 模型: Qwen3-32B EXL3 (3.5bpw)
- 服务: exllamav3

[测试结果]
- Cache: 8192 tokens (Q4 KV Cache)
- max_batch_size=1, max_chunk_size=256
- 速度: ~40 tok/s (无 speculative decoding)
- VRAM: ~13.86GB

[Speculative Decoding 说明]
- Draft model: Qwen3-0.6B-exl3 (已注释)
- 原因: 0.6B 与 32B 接受率太低，导致负优化 (14-22 tok/s)
- 如需启用: 取消注释 draft model 相关代码，设置 num_draft_tokens

================================================================================
测试命令
================================================================================

curl -X POST http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"写一个Python快速排序"}],"max_tokens":200}'

================================================================================
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from api_handlers import Qwen35APIHandler

MODEL_DIR = "/opt/gguf/Qwen3-32B-exl3/3_5"
MAX_SEQ_LEN = 32768
PORT = 11434
CACHE_TOKENS = 8192
MAX_BATCH_SIZE = 1
MAX_CHUNK_SIZE = 256
CACHE_TYPE = "quant"


def main():
    print(f"Loading Qwen3-32B model from {MODEL_DIR}...")
    print(
        f"Max batch size: {MAX_BATCH_SIZE}, Chunk size: {MAX_CHUNK_SIZE}, Cache: {CACHE_TYPE}"
    )

    handler = Qwen35APIHandler(
        model_dir=MODEL_DIR,
        max_seq_len=MAX_SEQ_LEN,
        cache_tokens=CACHE_TOKENS,
        max_batch_size=MAX_BATCH_SIZE,
        max_chunk_size=MAX_CHUNK_SIZE,
        model_name="qwen3-32b-exl3",
        default_system_prompt="You are a helpful AI assistant. When you need to call a tool, you MUST use this exact format:\n<tool_call>\n<function=TOOL_NAME>\n<parameter=PARAM_NAME>PARAM_VALUE</parameter>\n</function>\n</tool_call>\n\nCRITICAL RULES:\n1. ONLY use <tool_call> format for tool calls - no markdown code blocks\n2. Each <tool_call> contains ONE function call\n3. NEVER add text after </tool_call> until you receive the result\n4. Wait for tool results before making the next call\n5. For file operations, use exact paths provided\n6. If no tool is needed, respond naturally",
        cache_type=CACHE_TYPE,
    )

    handler.load(progressbar=True)

    print("")
    print("=" * 60)
    print("Qwen3-32B 服务已启动!")
    print("=" * 60)
    print(f"模型: Qwen3-32B EXL3")
    print(f"对内地址: http://localhost:{PORT}")
    print("=" * 60)

    server = handler.chat
    server.port = PORT

    from fastapi import FastAPI, Request
    from fastapi.responses import StreamingResponse
    import time
    import json
    import socket

    app = FastAPI()

    @app.get("/v1/models")
    async def list_models():
        return {
            "object": "list",
            "data": [
                {
                    "id": "qwen3-32b-exl3",
                    "object": "model",
                    "created": int(time.time()),
                    "owned_by": "qwen",
                    "permission": [],
                    "root": "qwen3-32b-exl3",
                }
            ],
        }

    @app.post("/v1/chat/completions")
    async def chat_completions(request: Request):
        data = await request.json()
        stream = data.get("stream", False)

        if stream:
            return StreamingResponse(
                handler.generate_completion_stream(data), media_type="text/event-stream"
            )
        else:
            return await handler.generate_completion(data)

    @app.post("/v1/responses")
    async def responses_endpoint(request: Request):
        from api_handlers import responses_endpoint as handle_response

        return await handle_response(request, handler, "qwen3-32b-exl3")

    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)


if __name__ == "__main__":
    main()
