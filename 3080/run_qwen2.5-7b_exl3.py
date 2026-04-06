#!/usr/bin/env python3
"""
Qwen2.5-7B-Instruct EXL3 启动脚本 - RTX 3080 10GB

================================================================================
启动参数说明
================================================================================

[必需]
  --model-dir         模型目录路径 (默认: /opt/image/Qwen2.5-7B-Instruct-exl3)

[可选]
  --port              API 服务端口 (默认: 11435)
  --host              监听地址 (默认: 0.0.0.0)
  --cache-tokens      KV Cache token 数 (默认: 65536)
  --max-new-tokens    单次最大生成 token 数 (默认: 1024)
  --interactive       交互式聊天模式 (默认: False)
  --think             启用思考模式 (默认: False)

[性能参数 - RTX 3080 10GB 优化]
  Cache: 65536 tokens (fp16)
  max_batch_size=16, max_chunk_size=8192
  max_seq_len: 32768 (32k)
  flash_attn: True
  VRAM: ~5.5GB 模型 + 缓存

================================================================================
nohup 启动命令 (日志保存到 /tmp)
================================================================================

# 启动服务
nohup python3 /home/dministrator/my-shell/3080/run_qwen2.5-7b_exl3.py > /tmp/qwen25_7b_exl3_$(date +%Y%m%d_%H%M%S).log 2>&1 & echo $!

# 查看日志
tail -f /tmp/qwen25_7b_exl3_*.log

# 查看进程
ps aux | grep run_qwen2.5-7b_exl3

# 停止服务
pkill -f run_qwen2.5-7b_exl3

================================================================================
基准测试结果 - 2026-04-06
================================================================================

[测试环境]
- GPU: RTX 3080 10GB
- 模型: Qwen2.5-7B-Instruct EXL3 (5bpw)
- 服务: exllamav3

[汇总]
- 总耗时: 198.21s
- 总token数: 10964
- 平均速度: 55.3 tok/s
- 模型大小: ~5.5GB
- 上下文: 32K

================================================================================
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from api_handlers import Qwen35APIHandler

MODEL_DIR = "/opt/image/Qwen2.5-7B-Instruct-exl3"
MAX_SEQ_LEN = 32768
PORT = 11435
CACHE_TOKENS = 32768
MAX_BATCH_SIZE = 16
MAX_CHUNK_SIZE = 8192
CACHE_TYPE = "fp16"


def main():
    print(f"Loading Qwen2.5-7B model from {MODEL_DIR}...")
    print(
        f"Max batch size: {MAX_BATCH_SIZE}, Chunk size: {MAX_CHUNK_SIZE}, Cache: {CACHE_TYPE}"
    )

    handler = Qwen35APIHandler(
        model_dir=MODEL_DIR,
        max_seq_len=MAX_SEQ_LEN,
        cache_tokens=CACHE_TOKENS,
        max_batch_size=MAX_BATCH_SIZE,
        max_chunk_size=MAX_CHUNK_SIZE,
        model_name="qwen2.5-7b-exl3",
        default_system_prompt="You are a helpful assistant. Do not think step by step. Answer directly and concisely.",
        cache_type=CACHE_TYPE,
    )

    handler.load(progressbar=True)

    print("")
    print("=" * 60)
    print("Qwen2.5-7B 服务已启动!")
    print("=" * 60)
    print(f"模型: Qwen2.5-7B EXL3")
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
                    "id": "qwen2.5-7b-exl3",
                    "object": "model",
                    "created": int(time.time()),
                    "owned_by": "qwen",
                    "permission": [],
                    "root": "qwen2.5-7b-exl3",
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
