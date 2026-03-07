#!/bin/bash
# exllamav2 投机采样启动脚本 (Qwen2.5-Coder-32B + 0.5B Draft)
# 配置: 32K 上下文, 4.0bpw, 投机采样 3 tokens

cd /opt/exllamav2

python3 << 'EOF'
import sys
import torch
import time
sys.path.insert(0, '/opt/exllamav2')

from exllamav2 import ExLlamaV2, ExLlamaV2Config, ExLlamaV2Cache_Q4, ExLlamaV2Tokenizer, ExLlamaV2Cache
from exllamav2.generator import ExLlamaV2StreamingGenerator, ExLlamaV2Sampler

print("=" * 60)
print("Qwen2.5-Coder-32B 投机采样启动")
print("=" * 60)

# 主模型配置 (32B, 4.0bpw, 32K 上下文)
print("\n[1/4] 加载主模型...")
config = ExLlamaV2Config('/opt/gguf/exl2_4_0')
config.max_seq_len = 32768
model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q4(model, lazy=True)
model.load_autosplit(cache)
print(f"    主模型加载完成, VRAM: {torch.cuda.memory_allocated()/1024**3:.2f} GB")

# 草稿模型配置 (0.5B, 8bpw, 32K)
print("[2/4] 加载草稿模型...")
draft_config = ExLlamaV2Config('/opt/gguf/Qwen2.5-Coder-0.5B-exl2')
draft_config.max_seq_len = 32768
draft_model = ExLlamaV2(draft_config)
draft_cache_init = ExLlamaV2Cache(draft_model)
draft_model.load_autosplit(draft_cache_init)
print(f"    草稿模型加载完成, VRAM: {torch.cuda.memory_allocated()/1024**3:.2f} GB")

# 分词器
print("[3/4] 初始化分词器...")
tokenizer = ExLlamaV2Tokenizer(config)
print(f"    词表大小: {tokenizer.get_vocab_size()}")

# 生成器配置
print("[4/4] 配置投机采样...")
settings = ExLlamaV2Sampler.Settings()
settings.temperature = 0       # 贪婪搜索 - 提升接受率
settings.token_repetition_penalty = 1.0  # 禁用惩罚

# 创建生成器
generator = ExLlamaV2StreamingGenerator(
    model, cache, tokenizer,
    draft_model=draft_model,
    draft_cache=ExLlamaV2Cache(draft_model),
    num_speculative_tokens=3
)

print("\n" + "=" * 60)
print("投机采样已启动!")
print("=" * 60)
print("配置:")
print("  - 主模型: Qwen2.5-Coder-32B (4.0bpw)")
print("  - 草稿模型: Qwen2.5-Coder-0.5B (8bpw)")
print("  - 上下文: 32K")
print("  - 投机步长: 3 tokens")
print("  - Temperature: 0 (Greedy)")
print("  - Repetition Penalty: 1.0 (禁用)")
print("=" * 60)

# 测试生成
prompt = "用 Python 实现 LRU 缓存"
input_ids = tokenizer.encode(prompt)

print(f"\n测试 Prompt: {prompt}")
print(f"Token 数量: {input_ids.shape[-1]}")

generator.begin_stream_ex(input_ids, settings)
start = time.time()
tokens = 0

print("\n生成中...\n")

for i in range(500):
    result = generator.stream_ex()
    chunk = result['chunk']
    chunk_tokens = result['chunk_token_ids']
    eos = result['eos']
    
    print(chunk, end='', flush=True)
    
    tokens += chunk_tokens.shape[1]
    if eos:
        break

elapsed = time.time() - start
speed = tokens / elapsed

print("\n" + "=" * 60)
print(f"生成完成!")
print(f"  - 生成 Token 数: {tokens}")
print(f"  - 耗时: {elapsed:.2f}s")
print(f"  - 速度: {speed:.2f} tokens/s")
print(f"  - 接受率: {100*generator.accepted_draft_tokens/generator.total_draft_tokens:.1f}%")
print("=" * 60)

EOF
