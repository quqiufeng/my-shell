#!/usr/bin/env python3
"""
Qwen2.5-Coder-7B-Instruct EXL2 启动脚本 - RTX 3080 10GB

================================================================================
启动参数说明
================================================================================

[必需]
  --model-dir         模型目录路径 (默认: /opt/image/Qwen2.5-Coder-7B-Instruct-exl2)

[可选]
  --port              API 服务端口 (默认: 11434)
  --host              监听地址 (默认: 0.0.0.0)
  --max-new-tokens    单次最大生成 token 数 (默认: 4096)
  --temperature       采样温度 (默认: 0.95)
  --top-k             Top-K 采样 (默认: 50)
  --top-p             Top-P 采样 (默认: 0.8)

[性能参数 - RTX 3080 10GB 优化]
  max_batch_size: 8
  max_chunk_size: 2048
  total_context: 16384
  max_seq_len: 32768

================================================================================
nohup 启动命令 (日志保存到 /tmp)
================================================================================

# 启动服务
nohup python3 /home/dministrator/my-shell/3080/run_qwen2.5-coder7b_exl2.py > /tmp/qwen25_coder7b_exl2_$(date +%Y%m%d_%H%M%S).log 2>&1 & echo $!

# 查看日志
tail -f /tmp/qwen25_coder7b_exl2_*.log

# 查看进程
ps aux | grep run_qwen2.5-coder7b_exl2

# 停止服务
pkill -f run_qwen2.5-coder7b_exl2

================================================================================
测试命令
================================================================================

# 测试 API (需先启动服务)
# 1. 修改 test_api.py 的 API_URL 为 http://localhost:11434/v1/chat/completions
# 2. 运行测试
cd /home/dministrator/my-shell && python3 test_api.py

# 或直接用 curl 测试
curl -X POST http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Write a hello world in python"}],"max_tokens":100}'

================================================================================
基准测试结果
================================================================================

[测试环境]
- GPU: RTX 3080 10GB
- 模型: Qwen2.5-Coder-7B-Instruct EXL2 (混合 2-8bit 量化)
- 框架: exllamav2 0.3.2
- 配置: batch=32, chunk=8192, temp=0

[30项算法/代码测试汇总]
- 平均速度: ~52-55 tok/s
- 总token数: ~10000+
- 总耗时: ~180-200s

[对比]
| 模型 | 框架 | 速度 |
|------|------|------|
| Qwen3.5-9B | llama.cpp | 66.8 tok/s |
| Qwen2.5-7B | exllamav2 | 52-55 tok/s |
| Qwen3.5-9B | exllamav3 | 49.7 tok/s |

================================================================================
OpenCode 配置 (~/.opencode/opencode.json)
================================================================================

{
  "model": "openai/qwen3.5-9b-exl3",
  "provider": {
    "openai": {
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "qwen3.5-9b-exl3": {
          "name": "Qwen3.5-9B-EXL3 (本地3080)",
          "maxContextWindow": 131072,
          "maxOutputTokens": 65536
        },
        "qwen3.5-9b-llama": {
          "name": "Qwen3.5-9B-llama.cpp (本地3080)",
          "maxContextWindow": 131072,
          "maxOutputTokens": 4096
        },
        "qwen2.5-coder-7b-exl2": {
          "name": "Qwen2.5-Coder-7B-EXL2 (本地3080)",
          "maxContextWindow": 32768,
          "maxOutputTokens": 4096
        }
      }
    }
  }
}

================================================================================
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from exllamav2_lib import Qwen25Chat, Qwen25Server
from api_handlers_exl2 import Qwen25APIHandler as Qwen35APIHandler

MODEL_DIR = "/opt/image/Qwen2.5-Coder-7B-Instruct-exl2"
MAX_SEQ_LEN = 32768
TOTAL_CONTEXT = 16384
PORT = 11434
MAX_BATCH_SIZE = 32
MAX_CHUNK_SIZE = 8192
TEMPERATURE = 0
TOP_K = 50
TOP_P = 0.8
MAX_NEW_TOKENS = 4096


def main():
    print(f"Loading Qwen2.5-Coder-7B model from {MODEL_DIR}...")
    print(f"Max batch size: {MAX_BATCH_SIZE}, Chunk size: {MAX_CHUNK_SIZE}")

    handler = Qwen35APIHandler(
        model_dir=MODEL_DIR,
        max_seq_len=MAX_SEQ_LEN,
        total_context=TOTAL_CONTEXT,
        max_batch_size=MAX_BATCH_SIZE,
        max_chunk_size=MAX_CHUNK_SIZE,
        temperature=TEMPERATURE,
        top_k=TOP_K,
        top_p=TOP_P,
        model_name="qwen2.5-coder-7b-exl2",
        default_system_prompt="You are a helpful coding assistant.回答问题简洁有力。",
    )

    handler.load(progressbar=True)

    print("")
    print("=" * 60)
    print("Qwen2.5-Coder-7B 服务已启动!")
    print("=" * 60)
    print(f"模型: Qwen2.5-Coder-7B EXL2")
    print(f"对内地址: http://localhost:{PORT}")
    print("=" * 60)

    server = handler.chat
    server.port = PORT

    from fastapi import FastAPI, Request
    from fastapi.responses import StreamingResponse
    import time
    import uvicorn

    app = FastAPI()

    @app.get("/v1/models")
    async def list_models():
        return {
            "object": "list",
            "data": [
                {
                    "id": "qwen2.5-coder-7b-exl2",
                    "object": "model",
                    "created": int(time.time()),
                    "owned_by": "qwen",
                    "permission": [],
                    "root": "qwen2.5-coder-7b-exl2",
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
    async def responses(request: Request):
        return await handler.responses_endpoint(request)

    uvicorn.run(app, host="0.0.0.0", port=PORT)


if __name__ == "__main__":
    main()
