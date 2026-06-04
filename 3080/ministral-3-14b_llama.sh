#!/bin/bash
# Ministral-3-14B launcher
exec nohup /opt/llama.cpp/build/bin/llama-server \
  -m /data/models/Ministral-3-14B-Instruct-2512-UD-Q4_K_XL.gguf \
  --alias "Ministral-3-14B-Instruct-2512" \
  -ngl 99 \
  --ctx-size 65536 \
  --batch-size 512 \
  --ubatch-size 512 \
  --threads 6 \
  --temp 0.05 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.0 \
  --parallel 1 \
  --cont-batching \
  --flash-attn on \
  --no-mmap \
  --mlock \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --port 11434 \
  --host 127.0.0.1 \
  --jinja \
  > /tmp/ministral-3-14b_llama.log 2>&1
