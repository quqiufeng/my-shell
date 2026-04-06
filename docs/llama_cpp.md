# Llama.cpp API 工具调用响应格式

本文档记录 llama.cpp 模型在不同工具调用场景下的 API 返回格式，作为 exllamav3 API 的参考实现。

## 概述

Llama.cpp 返回的工具调用格式：
- 使用 `tool_calls` 字段（数组）
- 每个工具调用包含 `id`, `type`, `function` (含 `name` 和 `arguments`)
- `arguments` 是 JSON 字符串

---

## 1. write_file（保存文件）

### 请求
```json
{
  "messages": [{"role": "user", "content": "保存代码到 /tmp/test.py"}],
  "tools": [{
    "type": "function",
    "function": {
      "name": "write_file",
      "parameters": {
        "type": "object",
        "properties": {
          "path": {"type": "string"},
          "content": {"type": "string"}
        },
        "required": ["path", "content"]
      }
    }
  }],
  "max_tokens": 800
}
```

### 响应
```json
{
  "choices": [{
    "finish_reason": "tool_calls",
    "index": 0,
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [
        {
          "id": "KvgXMSqIxXDmWW63UooVv4RXcOAMoxJZ",
          "type": "function",
          "function": {
            "name": "write_file",
            "arguments": "{\"path\":\"/tmp/test.py\",\"content\":\"#!/usr/bin/env python3\\n\\\"\\\"\\\"\\u6d4b\\u8bd5\\u6587\\u4ef6\\u793a\\u4f8b\\\"\\\"\\\"\\n...\"}"
          }
        }
      ]
    }
  }]
}
```

### 关键字段
| 字段 | 说明 |
|------|------|
| `tool_calls[].id` | 工具调用唯一 ID |
| `tool_calls[].type` | 固定为 `"function"` |
| `tool_calls[].function.name` | 函数名 `"write_file"` |
| `tool_calls[].function.arguments` | JSON 字符串，含 `path` 和 `content` |

---

## 2. run_shell（执行 Shell 命令）

### 请求
```json
{
  "messages": [{"role": "user", "content": "执行命令: ls -la /tmp"}],
  "tools": [{
    "type": "function",
    "function": {
      "name": "run_shell",
      "parameters": {
        "type": "object",
        "properties": {
          "command": {"type": "string"}
        },
        "required": ["command"]
      }
    }
  }],
  "max_tokens": 500
}
```

### 响应
```json
{
  "choices": [{
    "finish_reason": "tool_calls",
    "index": 0,
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [
        {
          "id": "zCzuu7rLTt4bhfB45P4CvHI52HevbywH",
          "type": "function",
          "function": {
            "name": "run_shell",
            "arguments": "{\"command\":\"ls -la /tmp\"}"
          }
        }
      ]
    }
  }]
}
```

### 关键字段
| 字段 | 说明 |
|------|------|
| `tool_calls[].function.name` | 函数名 `"run_shell"` |
| `tool_calls[].function.arguments` | JSON 字符串，含 `command` |

---

## 3. create_directory（创建文件夹）

### 请求
```json
{
  "messages": [{"role": "user", "content": "创建一个文件夹 /tmp/test_dir"}],
  "tools": [{
    "type": "function",
    "function": {
      "name": "create_directory",
      "parameters": {
        "type": "object",
        "properties": {
          "path": {"type": "string"}
        },
        "required": ["path"]
      }
    }
  }],
  "max_tokens": 500
}
```

### 响应
```json
{
  "choices": [{
    "finish_reason": "tool_calls",
    "index": 0,
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [
        {
          "id": "a2NwXmjyGBmYiMoj97Lf5GXaK6mzYjEt",
          "type": "function",
          "function": {
            "name": "create_directory",
            "arguments": "{\"path\":\"/tmp/test_dir\"}"
          }
        }
      ]
    }
  }]
}
```

### 关键字段
| 字段 | 说明 |
|------|------|
| `tool_calls[].function.name` | 函数名 `"create_directory"` |
| `tool_calls[].function.arguments` | JSON 字符串，含 `path` |

---

## Exllamav3 API 适配要点

为了让 exllamav3 返回与 llama.cpp 兼容的工具调用格式，需要：

### 1. 响应格式
```python
{
    "choices": [{
        "finish_reason": "tool_calls",
        "index": 0,
        "message": {
            "role": "assistant",
            "content": None,  # 注意：是 null，不是空字符串
            "tool_calls": [
                {
                    "id": "call_xxx",
                    "type": "function",
                    "function": {
                        "name": "write_file",
                        "arguments": "{\"path\": \"/tmp/a.py\", \"content\": \"...\"}"
                    }
                }
            ]
        }
    }]
}
```

### 2. 关键差异
| 字段 | Llama.cpp | 当前 Exllamav3 |
|------|-----------|----------------|
| `content` | `null` | `"EMPTY"` 或 `""` |
| `tool_calls[].id` | 完整 UUID 格式 | `"call_xxx"` 格式 |
| `finish_reason` | `"tool_calls"` | `"tool_calls"` |

### 3. 修复代码示例
```python
if tool_calls:
    return {
        "id": f"chatcmpl-{int(time.time() * 1000)}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": data.get("model", self.model_name),
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": None,  # 必须是 null
                    "tool_calls": tool_calls
                },
                "finish_reason": "tool_calls",
            }
        ],
        "usage": {
            "prompt_tokens": input_len,
            "completion_tokens": output_len,
            "total_tokens": input_len + output_len,
        },
    }
```

---

## 测试命令

```bash
# 测试 write_file
curl -X POST http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "保存代码到 /tmp/test.py"}],
    "tools": [{"type": "function", "function": {"name": "write_file", "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}}}],
    "max_tokens": 800
  }'

# 测试 run_shell
curl -X POST http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "执行命令: ls -la /tmp"}],
    "tools": [{"type": "function", "function": {"name": "run_shell", "parameters": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}}}],
    "max_tokens": 500
  }'

# 测试 create_directory
curl -X POST http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "创建一个文件夹 /tmp/test_dir"}],
    "tools": [{"type": "function", "function": {"name": "create_directory", "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}}],
    "max_tokens": 500
  }'
```
