#!/bin/bash

MODEL_PATH="/opt/gguf/Qwen3.5-9B-AWQ"

python3 -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_PATH" \
    --host 0.0.0.0 \
    --port 8000 \
    --dtype half \
    --max-model-len 32768 \
    --gpu-memory-utilization 0.85 \
    --enforce-eager
