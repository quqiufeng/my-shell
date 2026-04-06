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
基准测试结果 - 2026-04-06
================================================================================

[测试环境]
- GPU: RTX 3080 10GB
- 模型: Qwen3.5-9B EXL3 (4bpw)
- 服务: exllamav3

[性能测试结果 - 30项算法/代码测试]
| 测试项 | 耗时 | Token数 | 速度 |
|--------|------|---------|------|
| 快速排序 | 20.93s | 1023 | 48.9 tok/s |
| 线程安全 | 17.19s | 1023 | 59.5 tok/s |
| 二分查找 | 11.82s | 530 | 44.9 tok/s |
| 数据库索引 | 17.34s | 1023 | 59.0 tok/s |
| Python性能优化 | 19.93s | 1023 | 51.3 tok/s |
| 归并排序 | 17.25s | 1023 | 59.3 tok/s |
| HTTP/HTTPS | 20.45s | 1022 | 50.0 tok/s |
| LRU缓存 | 13.74s | 811 | 59.0 tok/s |
| 堆排序 | 20.12s | 1023 | 50.8 tok/s |
| Dijkstra算法 | 6.72s | 391 | 58.2 tok/s |
| 一致性哈希 | 17.25s | 1023 | 59.3 tok/s |
| 令牌桶 | 20.24s | 1023 | 50.5 tok/s |
| 阻塞队列 | 19.68s | 1023 | 52.0 tok/s |
| 红黑树 | 17.77s | 1023 | 57.6 tok/s |
| B+树 | 21.65s | 1023 | 47.3 tok/s |
| A*算法 | 21.19s | 1023 | 48.3 tok/s |
| KMP算法 | 22.82s | 1023 | 44.8 tok/s |
| 布隆过滤器 | 22.57s | 1023 | 45.3 tok/s |
| 跳表 | 19.66s | 1023 | 52.0 tok/s |
| 并查集 | 21.99s | 1023 | 46.5 tok/s |
| 线段树 | 17.41s | 964 | 55.4 tok/s |
| 字典树 | 15.70s | 691 | 44.0 tok/s |
| 最小生成树 | 12.17s | 651 | 53.5 tok/s |
| 拓扑排序 | 22.40s | 1023 | 45.7 tok/s |
| 最长公共子序列 | 12.00s | 631 | 52.6 tok/s |
| 编辑距离 | 23.02s | 1023 | 44.4 tok/s |
| 滑动窗口 | 18.78s | 1023 | 54.5 tok/s |
| 双指针 | 21.94s | 1023 | 46.6 tok/s |
| 动态规划 | 19.50s | 1023 | 52.5 tok/s |
| 贪心算法 | 23.71s | 1023 | 43.1 tok/s |

[汇总]
- 总耗时: 556.94s (~9.3分钟)
- 总token数: 28197
- 平均速度: 50.6 tok/s

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
        default_system_prompt="You are a helpful assistant. Do not think step by step. Answer directly and concisely.",
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

    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)


if __name__ == "__main__":
    main()
