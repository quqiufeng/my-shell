# OpenCode 对接 ExL2 模型 API 实现详解

本文档详细描述 OpenCode 如何对接基于 ExLlamaV2 量化的本地大模型服务。

## 目录

- [架构概览](#架构概览)
- [模型加载](#模型加载)
- [API 端点实现](#api-端点实现)
- [工具调用（Tool Calls）](#工具调用tool-calls)
- [流式响应](#流式响应)
- [性能优化](#性能优化)
- [对接配置](#对接配置)

---

## 架构概览

### 技术栈

```
┌─────────────────┐
│   OpenCode CLI  │  ← 调用 OpenAI 兼容 API
└────────┬────────┘
         │ HTTP/JSON
         ▼
┌─────────────────┐
│  FastAPI Server │  ← Python + FastAPI
│  (Port: 11434)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  ExLlamaV2      │  ← 模型推理引擎
│  + 量化模型     │
└─────────────────┘
```

### 模型类型

| 模型 | 量化 | 端口 | 特点 | 速度 |
|------|------|------|------|------|
| Qwen2.5-Coder-14B | 3.5 bpw | 11435 | CUDA Graph 加速 | ~82 tok/s |
| Qwen2.5-Coder-14B | 4.25 bpw | 11436 | 高精度量化 | ~77 tok/s |
| Qwen2.5-Coder-32B | 4.0 bpw + 0.5B草稿 | 11434 | 投机解码 | ~51 tok/s |

---

## 模型加载

### 14B 模型加载（3.5bpw / 4.25bpw）

```python
from exllamav2 import (
    ExLlamaV2,
    ExLlamaV2Config,
    ExLlamaV2Cache_Q4,
    ExLlamaV2Tokenizer,
)
from exllamav2.generator import ExLlamaV2StreamingGenerator, ExLlamaV2Sampler

# 1. 配置模型
config = ExLlamaV2Config(MAIN_MODEL_DIR)
config.max_seq_len = 32768  # 32k 上下文
config.no_flash_attn = False
config.no_sdpa = False
config.no_xformers = False

# 3.5bpw 特有：启用 CUDA Graph 加速
config.no_cuda_graph = False  # 11435 端口
# 4.25bpw 特有：禁用 CUDA Graph（与 64k 上下文冲突）
config.no_cuda_graph = True   # 11436 端口

# 2. 加载模型
model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q4(model, lazy=True)  # Q4 KV Cache
model.load_autosplit(cache)

# 3. 创建生成器
tokenizer = ExLlamaV2Tokenizer(config)
generator = ExLlamaV2StreamingGenerator(
    model=model,
    cache=cache,
    tokenizer=tokenizer,
)
```

### 32B 模型加载（投机解码）

```python
# 1. 加载主模型（32B）
config = ExLlamaV2Config(MAIN_MODEL_DIR)
config.max_seq_len = 32768
model = ExLlamaV2(config)
cache = ExLlamaV2Cache_Q4(model, lazy=True)
model.load_autosplit(cache)

# 2. 加载草稿模型（0.5B）
draft_config = ExLlamaV2Config(DRAFT_MODEL_DIR)
draft_model = ExLlamaV2(draft_config)
draft_cache = ExLlamaV2Cache(draft_model)
draft_model.load_autosplit(draft_cache)

# 3. 创建带投机解码的生成器
generator = ExLlamaV2StreamingGenerator(
    model=model,
    cache=cache,
    tokenizer=tokenizer,
    draft_model=draft_model,           # 草稿模型
    draft_cache=draft_cache,           # 草稿缓存
    num_speculative_tokens=6,          # 投机 token 数
)
```

### 关键差异

| 特性 | 14B (3.5/4.25) | 32B |
|------|----------------|-----|
| 模型数量 | 1个 | 2个（主+草稿） |
| CUDA Graph | 支持（3.5bpw）| 不支持 |
| 投机解码 | 无 | 有 |
| KV Cache | Q4 | Q4 |
| 显存占用 | ~10GB | ~22GB |

---

## API 端点实现

### 1. `/v1/models` - 模型列表

```python
@app.get("/v1/models")
async def list_models():
    return {
        "object": "list",
        "data": [{
            "id": "qwen2.5-coder-14b-exl2",  # 或 32b-exl2
            "object": "model",
            "created": int(time.time()),
            "owned_by": "qwen",
        }]
    }
```

**用途**：OpenCode 启动时探测可用模型。

### 2. `/v1/chat/completions` - 标准对话

这是核心端点，支持：
- ✅ 流式/非流式响应
- ✅ 工具调用（Tool Calls）
- ✅ 温度参数控制
- ✅ 最大 token 限制

#### 请求处理流程

```python
@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    data = await request.json()
    messages = data.get("messages", [])
    tools = data.get("tools", [])           # 工具定义
    stream = data.get("stream", False)
    temperature = data.get("temperature", 0.0)
    
    # 1. 构建带工具的 Prompt
    prompt = build_prompt(messages, tools)
    
    # 2. Tokenize
    input_ids = tokenizer.encode(prompt)
    
    # 3. 流式或非流式生成
    if stream:
        return StreamingResponse(generate_stream(), ...)
    else:
        return await generate_completion(data)
```

### 3. `/v1/responses` - OpenAI Responses API

这是 OpenAI 新版 API 格式，OpenCode 优先使用此端点。

```python
@app.post("/v1/responses")
async def responses(request: Request):
    """
    OpenAI Responses API - 支持 function calling
    """
    data = await request.json()
    
    # 转换 input 为 messages 格式
    input_data = data.get("input", "")
    if isinstance(input_data, str):
        messages = [{"role": "user", "content": input_data}]
    elif isinstance(input_data, list):
        messages = input_data
    
    # 获取工具定义
    tools = data.get("tools", [])
    
    # 转发到 generate_completion
    result = await generate_completion({
        "messages": messages,
        "tools": tools,
        "stream": False
    })
    
    # 转换回 Responses API 格式
    message = result["choices"][0]["message"]
    
    if "tool_calls" in message:
        # Function call 响应
        output = [{
            "type": "function_call",
            "id": tc["id"],
            "name": tc["function"]["name"],
            "arguments": tc["function"]["arguments"]
        } for tc in message["tool_calls"]]
    else:
        # 普通文本响应
        output = [{
            "type": "message",
            "role": "assistant",
            "content": [{"type": "output_text", "text": message["content"]}]
        }]
    
    return {
        "id": result["id"],
        "object": "response",
        "output": output,
        "usage": result["usage"],
        "status": "completed"
    }
```

---

## 工具调用（Tool Calls）

### 核心逻辑

```python
async def generate_completion(data):
    messages = data.get("messages", [])
    tools = data.get("tools", [])
    
    # 1. 构建带工具定义的 Prompt
    prompt = build_prompt(messages, tools)
    
    # 2. 生成文本
    full_text = ""
    while not eos:
        result = generator.stream_ex()
        full_text += result['chunk']
    
    # 3. 检测是否为工具调用
    tool_calls = parse_tool_calls(full_text)
    
    if tool_calls:
        # 返回 tool_calls 格式
        return {
            "choices": [{
                "message": {"tool_calls": tool_calls},
                "finish_reason": "tool_calls"
            }]
        }
    else:
        # 返回普通文本
        return {
            "choices": [{
                "message": {"content": full_text},
                "finish_reason": "stop"
            }]
        }
```

### Prompt 构建（工具调用）

```python
def build_prompt(messages, tools=None):
    tools_def = ""
    if tools:
        # Qwen2.5 工具调用格式
        tools_def = """
# Tools

You may call one or more functions to assist with the user query.

You are provided with function signatures within <tools></tools> XML tags:
<tools>
{"name": "get_weather", "description": "获取天气", "parameters": {...}}
</tools>

For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
<tool_call>
{"name": "<function-name>", "arguments": <args-json-object>}
</tool_call>
"""
    
    # 将 tools_def 注入到 system prompt
    if system_msg:
        prompt += f"<|im_start|>system\n{system_msg}{tools_def}<|im_end|>\n"
    
    # 添加用户/助手消息...
    
    return prompt
```

### 工具调用解析

```python
def parse_tool_calls(text):
    """
    解析模型输出的工具调用
    期望格式: {"name": "func_name", "arguments": {...}}
    """
    try:
        data = json.loads(text.strip())
        if isinstance(data, dict) and "name" in data and "arguments" in data:
            return [{
                "id": f"call_{int(time.time()*1000)}",
                "type": "function",
                "function": {
                    "name": data["name"],
                    "arguments": json.dumps(data["arguments"])
                }
            }]
    except:
        pass
    return None
```

### 流式响应中的工具调用

```python
def generate():
    full_output = ""
    tool_calls_sent = False
    
    while generated < max_tokens:
        result = generator.stream_ex()
        chunk = result['chunk']
        full_output += chunk
        
        # 实时检测是否触发了工具调用
        if not tool_calls_sent:
            try:
                data = json.loads(full_output.strip())
                if "name" in data and "arguments" in data:
                    # 发送 tool_calls 事件
                    yield json.dumps({
                        "choices": [{
                            "delta": {"tool_calls": [...]},
                            "finish_reason": "tool_calls"
                        }]
                    })
                    tool_calls_sent = True
                    continue
            except:
                pass
        
        # 普通文本块
        yield json.dumps({
            "choices": [{
                "delta": {"content": chunk},
                "finish_reason": None
            }]
        })
```

---

## 流式响应

### SSE (Server-Sent Events) 格式

```python
from fastapi.responses import StreamingResponse

def generate():
    generator.begin_stream(input_ids, settings)
    
    while not eos:
        result = generator.stream_ex()
        chunk = result['chunk']
        
        # OpenAI 流式格式
        data = {
            "choices": [{
                "delta": {"content": chunk},
                "finish_reason": None
            }],
            "usage": {
                "prompt_tokens": prompt_len,
                "completion_tokens": generated
            }
        }
        
        # SSE 格式: data: {...}\n\n
        yield f"data: {json.dumps(data)}\n\n"
    
    # 结束标记
    yield "data: [DONE]\n\n"

return StreamingResponse(
    generate(),
    media_type="text/event-stream"
)
```

### 响应示例

```
data: {"choices":[{"delta":{"content":"你"},"finish_reason":null}]}

data: {"choices":[{"delta":{"content":"好"},"finish_reason":null}]}

data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

data: [DONE]

```

---

## 性能优化

### 1. 量化策略

```python
# KV Cache 使用 Q4 量化（显存 vs 速度平衡）
cache = ExLlamaV2Cache_Q4(model, lazy=True)

# 可选：Q6 / Q8（更高精度，更多显存）
# cache = ExLlamaV2Cache_Q6(model, lazy=True)
```

### 2. CUDA Graph（仅 14B 3.5bpw）

```python
config.no_cuda_graph = False  # 启用可提升 10-20% 速度
```

⚠️ **注意**：与 64k 上下文不兼容，4.25bpw 版本已禁用。

### 3. FlashAttention

```python
# 确保启用 FlashAttention
config.no_flash_attn = False
config.no_sdpa = False
```

需要安装 `flash-attn`：
```bash
bash /opt/my-shell/4090d/build_flash_attention.sh
```

### 4. 投机解码（仅 32B）

```python
# 使用 0.5B 小模型预测，32B 模型验证
num_speculative_tokens = 6  # 最优值（8 会下降）

# 理论加速：~1.5-2x
# 实测加速：~1.2-1.3x（草稿模型质量限制）
```

### 性能数据对比

| 模型 | 平均速度 | 最快测试 | 最慢测试 | 显存占用 |
|------|---------|---------|---------|---------|
| 14B 3.5bpw | 81.9 tok/s | 92.1 | 60.0 | ~8GB |
| 14B 4.25bpw | 76.9 tok/s | 87.6 | 61.0 | ~9GB |
| 32B | 51.0 tok/s | 73.0 | 33.1 | ~22GB |

---

## 对接配置

### OpenCode 配置示例

```json
// ~/.config/opencode/config.json
{
  "models": [
    {
      "name": "qwen2.5-coder-14b-3.5",
      "provider": "openai",
      "base_url": "http://localhost:11435/v1",
      "api_key": "dummy",
      "model": "qwen2.5-coder-14b-exl2",
      "max_tokens": 4096,
      "temperature": 0.2
    },
    {
      "name": "qwen2.5-coder-14b-4.25",
      "provider": "openai",
      "base_url": "http://localhost:11436/v1",
      "api_key": "dummy",
      "model": "qwen2.5-coder-14b-exl2",
      "max_tokens": 4096,
      "temperature": 0.2
    },
    {
      "name": "qwen2.5-coder-32b",
      "provider": "openai",
      "base_url": "http://localhost:11434/v1",
      "api_key": "dummy",
      "model": "qwen2.5-coder-32b-exl2",
      "max_tokens": 4096,
      "temperature": 0.2
    }
  ]
}
```

**配置文件位置：**
- **Linux/macOS**: `~/.config/opencode/config.json`
- **Windows**: `%APPDATA%\opencode\config.json`

**配置说明：**
- `api_key`: 本地模型无需真实 key，填 `dummy` 即可
- `base_url`: 根据启动的模型选择对应端口（11435/11436/11434）
- `provider`: 使用 `openai` 兼容模式
- `model`: 与脚本中定义的模型 ID 保持一致

### 启动脚本

```bash
#!/bin/bash

# 根据任务选择模型

# 快速代码补全 - 14B 3.5bpw
nohup python3 run_qwen2.5-coder-14b-3.5_exl2.py > /tmp/model.log 2>&1 &

# 高精度代码生成 - 14B 4.25bpw  
nohup python3 run_qwen2.5-coder-14b-4.25_exl2.py > /tmp/model.log 2>&1 &

# 复杂算法设计 - 32B
nohup python3 run_qwen2.5-coder-32b_exl2.py > /tmp/model.log 2>&1 &
```

### 监控命令

```bash
# 查看模型日志
tail -f /tmp/model.log

# 检查 API 是否就绪
curl http://localhost:11435/v1/models

# 测试生成
curl -X POST http://localhost:11435/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"你好"}],"max_tokens":100}'

# 查看显存占用
nvidia-smi
```

---

## 故障排查

### 显存不足 (OOM)

```python
# 减小上下文长度
config.max_seq_len = 16384  # 默认 32768

# 或使用 Q8 缓存（更省显存）
from exllamav2 import ExLlamaV2Cache_Q8
cache = ExLlamaV2Cache_Q8(model, lazy=True)
```

### 速度慢

1. 检查 FlashAttention 是否安装
2. 确认 CUDA Graph 启用（仅限 3.5bpw）
3. 监控 GPU 利用率：`nvidia-smi dmon`

### 工具调用不触发

1. 检查 Prompt 是否正确包含 tools 定义
2. 确认模型输出格式为 JSON：
   ```json
   {"name": "func_name", "arguments": {"arg1": "value1"}}
   ```
3. 降低 temperature 到 0.0-0.2

---

## 附录：完整请求/响应示例

### 工具调用请求

```bash
curl -X POST http://localhost:11435/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder-14b-exl2",
    "input": "北京今天天气怎么样？",
    "tools": [{
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "获取指定城市天气",
        "parameters": {
          "type": "object",
          "properties": {
            "city": {"type": "string", "description": "城市名称"}
          },
          "required": ["city"]
        }
      }
    }]
  }'
```

### 工具调用响应

```json
{
  "id": "resp_xxx",
  "object": "response",
  "output": [{
    "type": "function_call",
    "id": "call_123",
    "name": "get_weather",
    "arguments": "{\"city\": \"北京\"}"
  }],
  "usage": {
    "prompt_tokens": 156,
    "completion_tokens": 25,
    "total_tokens": 181
  },
  "status": "completed"
}
```

---

## 总结

| 特性 | 实现方案 | 备注 |
|------|---------|------|
| API 框架 | FastAPI | 高性能异步支持 |
| 模型推理 | ExLlamaV2 | 4-bit 量化，RTX 4090D 优化 |
| 工具调用 | XML 格式 Prompt + JSON 解析 | Qwen2.5 原生支持 |
| 流式响应 | SSE | OpenAI 兼容格式 |
| 性能优化 | CUDA Graph + FlashAttention | 81+ tok/s（14B）|

---

**文档版本**: 2026-04-01  
**适用模型**: Qwen2.5-Coder-14B/32B EXL2  
**测试环境**: RTX 4090D 24GB
