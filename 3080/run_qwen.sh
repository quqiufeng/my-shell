#!/bin/bash

MODEL_DIR="$HOME/Qwen3.5-9B-Q6_K.gguf"
LLAMA_BIN="$HOME/llama.cpp/build/bin/llama-cli"

export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH

if [ ! -f "$MODEL_DIR" ]; then
    echo "错误: 模型文件不存在: $MODEL_DIR"
    exit 1
fi

NGLAYERS=40
CTX_SIZE=20480
BATCH_SIZE=512
FLASH_ATTN="on"
CACHE_TYPE_K="q4_0"
CACHE_TYPE_V="q4_0"
THREADS=14

if [ $# -eq 0 ]; then
    $LLAMA_BIN -m "$MODEL_DIR" \
        -ngl $NGLAYERS \
        -c $CTX_SIZE \
        --batch-size $BATCH_SIZE \
        --flash-attn $FLASH_ATTN \
        --cache-type-k $CACHE_TYPE_K \
        --cache-type-v $CACHE_TYPE_V \
        --threads $THREADS
else
    PROMPT="$1"
    $LLAMA_BIN -m "$MODEL_DIR" \
        --prompt "<|im_start|>system\nYou are a helpful assistant.<|im_end|>\n<|im_start|>user\n${PROMPT}<|im_end|>\n<|im_start|>assistant\n" \
        -n 4096 \
        -ngl $NGLAYERS \
        -c $CTX_SIZE \
        --batch-size $BATCH_SIZE \
        --flash-attn $FLASH_ATTN \
        --cache-type-k $CACHE_TYPE_K \
        --cache-type-v $CACHE_TYPE_V \
        --threads $THREADS
fi
