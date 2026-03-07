#!/bin/bash

MODEL_DIR="/opt/gguf/exl2_4_25"
PORT=11434
GPU_SPLIT=16
MAX_SEQ_LEN=8192

echo "=== 启动 exllamav2 (Qwen2.5-Coder-32B 4.25bpw) ==="
echo "模型: $MODEL_DIR"
echo "端口: $PORT"
echo "GPU分配: ${GPU_SPLIT}GB"
echo "上下文: ${MAX_SEQ_LEN}"

cd /opt/exllamav2

nohup python3 -c "
import time
from exllamav2 import ExLlamaV2, ExLlamaV2Config, ExLlamaV2Cache, ExLlamaV2Tokenizer
from exllamav2.generator import ExLlamaV2BaseGenerator, ExLlamaV2Sampler
from exllamav2 import ExLlamaV2HTTP

config = ExLlamaV2Config('$MODEL_DIR')
config.gpu_split = $GPU_SPLIT
config.max_seq_len = $MAX_SEQ_LEN

print('Loading model...')
model = ExLlamaV2(config)
cache = ExLlamaV2Cache(model, lazy=True)
model.load_autosplit(cache)
tokenizer = ExLlamaV2Tokenizer(config)
generator = ExLlamaV2BaseGenerator(model, cache, tokenizer)
settings = ExLlamaV2Sampler.Settings()
settings.max_tokens = 4096

print('Starting HTTP server...')
http_server = ExLlamaV2HTTP(generator, tokenizer, host='0.0.0.0', port=$PORT)
http_server.run()
" > /tmp/exllamav2.log 2>&1 &

echo "PID: $!"
sleep 10

echo ""
echo "=== 服务已启动 ==="
echo "地址: http://localhost:$PORT"
