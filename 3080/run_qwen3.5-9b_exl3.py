#!/usr/bin/env python3
"""
Qwen3.5-9B EXL3 启动脚本 - RTX 3080 10GB

================================================================================
OpenCode 本地配置 (opencode 使用该模型正常)
================================================================================

配置文件路径: ~/.opencode/opencode.json

配置内容:
{
  "$schema": "https://opencode.ai/config.json",
  "model": "openai/qwen3.5-9b-exl3",
  "provider": {
    "openai": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local Models",
      "options": {
        "baseURL": "http://localhost:11434/v1",
        "apiKey": "dummy"
      },
      "models": {
        "qwen3.5-9b-exl3": {
          "name": "Qwen3.5-9B-EXL3 (本地3080)",
          "maxContextWindow": 131072,
          "maxOutputTokens": 65536
        }
      }
    }
  }
}

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
  max_batch_size=8, max_chunk_size=4096
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
基准测试结果 - 2026-04-06 (第二轮)
================================================================================

[测试环境]
- GPU: RTX 3080 10GB
- 模型: Qwen3.5-9B EXL3 (4bpw)
- 服务: exllamav3

[性能测试结果 - 30项算法/代码测试]
| 测试项 | 耗时 | Token数 | 速度 |
|--------|------|---------|------|
| 快速排序 | 19.68s | 1022 | 51.9 tok/s |
| 线程安全 | 19.93s | 1023 | 51.3 tok/s |
| 二分查找 | 11.97s | 669 | 55.9 tok/s |
| 数据库索引 | 19.17s | 1023 | 53.4 tok/s |
| Python性能优化 | 20.65s | 1023 | 49.5 tok/s |
| 归并排序 | 1.14s | 56 | 49.3 tok/s |
| HTTP/HTTPS | 18.34s | 1023 | 55.8 tok/s |
| LRU缓存 | 20.64s | 1023 | 49.6 tok/s |
| 堆排序 | 1.17s | 54 | 46.1 tok/s |
| Dijkstra算法 | 19.85s | 1023 | 51.5 tok/s |
| 一致性哈希 | 20.09s | 1023 | 50.9 tok/s |
| 令牌桶 | 12.61s | 722 | 57.3 tok/s |
| 阻塞队列 | 1.07s | 51 | 47.9 tok/s |
| 红黑树 | 19.73s | 1023 | 51.9 tok/s |
| B+树 | 15.02s | 843 | 56.1 tok/s |
| A*算法 | 19.67s | 1023 | 52.0 tok/s |
| KMP算法 | 19.84s | 1023 | 51.6 tok/s |
| 布隆过滤器 | 18.25s | 1023 | 56.1 tok/s |
| 跳表 | 19.38s | 1023 | 52.8 tok/s |
| 并查集 | 1.47s | 76 | 51.8 tok/s |
| 线段树 | 1.13s | 58 | 51.2 tok/s |
| 字典树 | 17.86s | 1023 | 57.3 tok/s |
| 最小生成树 | 1.39s | 73 | 52.6 tok/s |
| 拓扑排序 | 19.78s | 1023 | 51.7 tok/s |
| 最长公共子序列 | 1.11s | 55 | 49.5 tok/s |
| 编辑距离 | 19.73s | 1024 | 51.9 tok/s |
| 滑动窗口 | 18.37s | 1023 | 55.7 tok/s |
| 双指针 | 11.61s | 629 | 54.2 tok/s |
| 动态规划 | 20.27s | 1023 | 50.5 tok/s |
| 贪心算法 | 19.43s | 1023 | 52.7 tok/s |

[汇总]
- 总耗时: 430.35s
- 总token数: 22723
- 平均速度: 52.8 tok/s

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
MAX_BATCH_SIZE = 8
MAX_CHUNK_SIZE = 4096
CACHE_TYPE = "fp16"


def main():
    print(f"Loading Qwen3.5-9B model from {MODEL_DIR}...")
    print(
        f"Max batch size: {MAX_BATCH_SIZE}, Chunk size: {MAX_CHUNK_SIZE}, Cache: {CACHE_TYPE}"
    )

    handler = Qwen35APIHandler(
        model_dir=MODEL_DIR,
        max_seq_len=MAX_SEQ_LEN,
        cache_tokens=CACHE_TOKENS,
        max_batch_size=MAX_BATCH_SIZE,
        max_chunk_size=MAX_CHUNK_SIZE,
        model_name="qwen3.5-9b-exl3",
        default_system_prompt="You are a helpful AI assistant. When you need to call a tool, you MUST use this exact format:\n<tool_call>\n<function=TOOL_NAME>\n<parameter=PARAM_NAME>PARAM_VALUE</parameter>\n</function>\n</tool_call>\n\nCRITICAL RULES:\n1. ONLY use <tool_call> format for tool calls - no markdown code blocks\n2. Each <tool_call> contains ONE function call\n3. NEVER add text after </tool_call> until you receive the result\n4. Wait for tool results before making the next call\n5. For file operations, use exact paths provided\n6. If no tool is needed, respond naturally",
        cache_type=CACHE_TYPE,
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

    @app.post("/v1/responses")
    async def responses_endpoint(request: Request):
        from api_handlers import responses_endpoint as handle_response

        return await handle_response(request, handler, "qwen3.5-9b-exl3")

    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)


if __name__ == "__main__":
    main()
