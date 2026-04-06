#!/usr/bin/env python3
"""
Qwen3.5-9B-Claude-Opus-Reasoning EXL3 启动脚本 - RTX 3080 10GB

================================================================================
模型特性
================================================================================
- 基础模型: Qwen3.5-9B (蒸馏自 Claude 4.6 Opus Reasoning)
- 量化: EXL3 4bpw
- 模型大小: ~7.2GB
- 上下文: 262144 (256K)
- 特点: 混合注意力 (linear + full attention)
- 用途: 长上下文推理任务

================================================================================
启动参数说明
================================================================================

[必需]
  --model-dir         模型目录路径 (默认: /opt/image/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled-4bpw-exl3)

[可选]
  --port              API 服务端口 (默认: 11434)
  --host              监听地址 (默认: 0.0.0.0)
  --cache-tokens      KV Cache token 数 (默认: 65536)
  --max-new-tokens    单次最大生成 token 数 (默认: 1024)
  --interactive       交互式聊天模式 (默认: False)
  --think             启用思考模式 (默认: False)

[性能参数 - RTX 3080 10GB 优化]
  Cache: 65536 tokens (fp16)
  max_batch_size=8, max_chunk_size=4096
  max_seq_len: 262144 (256k)
  flash_attn: True
  VRAM: ~7.2GB 模型 + 缓存

================================================================================
nohup 启动命令 (日志保存到 /tmp)
================================================================================

# 启动服务
nohup python3 /home/dministrator/my-shell/3080/run_qwen3.5-claude_exl3.py > /tmp/qwen35_claude_exl3_$(date +%Y%m%d_%H%M%S).log 2>&1 & echo $!

# 查看日志
tail -f /tmp/qwen35_claude_exl3_*.log

# 查看进程
ps aux | grep run_qwen3.5-claude_exl3

# 停止服务
pkill -f run_qwen3.5-claude_exl3

================================================================================
测试命令
================================================================================

# 测试 API (需先启动服务)
# 修改 test_api.py 的 API_URL 为 http://localhost:11434/v1/chat/completions
cd /home/dministrator/my-shell && python3 test_api.py

# 或直接用 curl 测试
curl -X POST http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Write a hello world in python"}],"max_tokens":100}'

================================================================================
OpenCode 配置 (~/.opencode/opencode.json)
================================================================================

{
  "$schema": "https://opencode.ai/config.json",
  "model": "openai/qwen3.5-claude-exl3",
  "provider": {
    "openai": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local Models",
      "options": {
        "baseURL": "http://localhost:11434/v1",
        "apiKey": "dummy"
      },
      "models": {
        "qwen3.5-claude-exl3": {
          "name": "Qwen3.5-9B-Claude-Reasoning (本地3080)",
          "maxContextWindow": 262144,
          "maxOutputTokens": 8192
        }
      }
    }
  }
}

================================================================================
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from api_handlers import Qwen35APIHandler

MODEL_DIR = "/opt/image/Qwen3.5-9B-Claude-4.6-Opus-Reasoning-Distilled-4bpw-exl3"
MAX_SEQ_LEN = 262144
PORT = 11434
CACHE_TOKENS = 65536
MAX_BATCH_SIZE = 8
MAX_CHUNK_SIZE = 4096
CACHE_TYPE = "fp16"


def main():
    print(f"Loading Qwen3.5-9B-Claude model from {MODEL_DIR}...")
    print(
        f"Max batch size: {MAX_BATCH_SIZE}, Chunk size: {MAX_CHUNK_SIZE}, Cache: {CACHE_TYPE}"
    )
    print(f"Max sequence length: {MAX_SEQ_LEN} (256K context)")

    handler = Qwen35APIHandler(
        model_dir=MODEL_DIR,
        max_seq_len=MAX_SEQ_LEN,
        cache_tokens=CACHE_TOKENS,
        max_batch_size=MAX_BATCH_SIZE,
        max_chunk_size=MAX_CHUNK_SIZE,
        model_name="qwen3.5-claude-exl3",
        default_system_prompt="You are a helpful AI assistant. When you need to call a tool, you MUST use this exact format:\n<tool_call>\n<function=TOOL_NAME>\n<parameter=PARAM_NAME>PARAM_VALUE</parameter>\n</function>\n</tool_call>\n\nCRITICAL RULES:\n1. ONLY use <tool_call> format for tool calls - no markdown code blocks\n2. Each <tool_call> contains ONE function call\n3. NEVER add text after </tool_call> until you receive the result\n4. Wait for tool results before making the next call\n5. For file operations, use exact paths provided\n6. If no tool is needed, respond naturally",
        cache_type=CACHE_TYPE,
    )

    handler.load(progressbar=True)

    print("")
    print("=" * 60)
    print("Qwen3.5-9B-Claude 服务已启动!")
    print("=" * 60)
    print(f"模型: Qwen3.5-9B-Claude-Opus-Reasoning EXL3")
    print(f"上下文: 256K")
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
                    "id": "qwen3.5-claude-exl3",
                    "object": "model",
                    "created": int(time.time()),
                    "owned_by": "qwen",
                    "permission": [],
                    "root": "qwen3.5-claude-exl3",
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

        return await handle_response(request, handler, "qwen3.5-claude-exl3")

    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)


if __name__ == "__main__":
    main()
