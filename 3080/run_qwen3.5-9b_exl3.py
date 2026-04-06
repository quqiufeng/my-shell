#!/usr/bin/env python3
"""
Qwen3.5-9B EXL3 启动脚本 - RTX 3080 10GB

================================================================================
启动参数说明
================================================================================

[必需]
  --model-dir         模型目录路径 (默认: /opt/image/Qwen3.5-9B-exl3)

[可选]
  --port              API 服务端口 (默认: 11434)
  --host              监听地址 (默认: 0.0.0.0)
  --cache-tokens      KV Cache token 数 (默认: 65536)
  --max-new-tokens    单次最大生成 token 数 (默认: 1024)
  --interactive       交互式聊天模式 (默认: False)
  --think             启用思考模式 (默认: False)

[性能参数 - RTX 3080 10GB 优化]
  Cache: 65536 tokens (Q4 4bit)
  max_batch_size=1, max_chunk_size=2048
  max_seq_len: 131072 (128k)
  flash_attn: True
  VRAM: ~9.4GB 模型 + 缓存

================================================================================
nohup 启动命令 (日志保存到 /tmp)
================================================================================

# 启动服务
nohup python3 /home/dministrator/my-shell/3080/run_qwen3.5-9b_exl3.py > /tmp/qwen35_exl3_$(date +%Y%m%d_%H%M%S).log 2>&1 & echo $!

# 查看日志
tail -f /tmp/qwen35_exl3_*.log

# 查看进程
ps aux | grep run_qwen3.5-9b_exl3

# 停止服务
pkill -f run_qwen3.5-9b_exl3

================================================================================
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from api_handlers import Qwen35APIHandler

MODEL_DIR = "/opt/image/Qwen3.5-9B-exl3"
MAX_SEQ_LEN = 131072
PORT = 11434
CACHE_TOKENS = 65536


def main():
    print(f"Loading Qwen3.5-9B model from {MODEL_DIR}...")

    handler = Qwen35APIHandler(
        model_dir=MODEL_DIR,
        max_seq_len=MAX_SEQ_LEN,
        cache_tokens=CACHE_TOKENS,
        model_name="qwen3.5-9b-exl3",
        default_system_prompt="You are a helpful assistant. Do not think step by step. Answer directly and concisely.",
    )

    handler.load(progressbar=True)

    print("")
    print("=" * 60)
    print("Qwen3.5-9B 服务已启动!")
    print("=" * 60)
    print(f"模型: Qwen3.5-9B EXL3")
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
                    "id": "qwen3.5-9b-exl3",
                    "object": "model",
                    "created": int(time.time()),
                    "owned_by": "qwen",
                    "permission": [],
                    "root": "qwen3.5-9b-exl3",
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

    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)


if __name__ == "__main__":
    main()
