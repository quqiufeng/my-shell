# OpenCode 对接本地大模型 API 配置指南

本文档说明如何配置 OpenCode 连接本地部署的大模型 API 服务。

## 问题背景

使用 OpenCode 连接本地 Qwen 模型时，可能会遇到错误：

```
request (19974 tokens) exceeds the available context size (16384 tokens), try increasing it
```

这是因为 llama.cpp 服务端的上下文大小与 OpenCode 配置不匹配。

## llama.cpp 启动参数与实际上下文的关系

| 启动参数 `-c` | 实际 Slot 上下文 | 说明 |
|---------------|-----------------|------|
| 65536 | 16384 | 默认值 |
| 131072 | 32768 | 2倍 |
| 262144 | 65536 | 4倍 |

**重要**：由于 Qwen3.5-9B 模型原始训练上下文是 16K，需要通过 `-c` 参数扩展。实际上下文约为参数值的 **1/4**。

## OpenCode 配置文件参数

配置文件位置：`~/.config/opencode/opencode.json`

```json
{
  "model": "llama.cpp/qwen3.5-9b",
  "provider": {
    "llama.cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "qwen3.5-9b": {
          "name": "qwen3.5-9b",
          "maxContextWindow": 131072,
          "maxOutputTokens": 65536,
          "options": {
            "num_ctx": 131072
          }
        }
      }
    }
  }
}
```

## 参数对应关系

| OpenCode 配置 | llama.cpp 参数 | 说明 |
|---------------|----------------|------|
| `maxContextWindow` | `-c` (ctx-size) | 最大上下文窗口 |
| `options.num_ctx` | `-c` (ctx-size) | 传递给 API 的上下文大小 |
| `maxOutputTokens` | `--n-predict` | 最大输出 tokens |

## 解决 Token 限制的方法

### 方法 1：修改 llama.cpp 启动参数

编辑启动脚本 `3080/run_qwen_api.sh`：

```bash
# 修改 -c 参数值
-c 131072  # 对应 32K 上下文
# 或
-c 262144  # 对应 64K 上下文
```

重启服务：

```bash
pkill -f llama-server
./3080/run_qwen_api.sh
```

### 方法 2：修改 OpenCode 配置

在 `~/.config/opencode/opencode.json` 中设置：

```json
{
  "model": "llama.cpp/qwen3.5-9b",
  "provider": {
    "llama.cpp": {
      "options": { "baseURL": "http://localhost:11434/v1" },
      "models": {
        "qwen3.5-9b": {
          "name": "qwen3.5-9b",
          "maxContextWindow": 131072,
          "maxOutputTokens": 65536,
          "options": { "num_ctx": 131072 }
        }
      }
    }
  }
}
```

### 方法 3：运行时指定模型

```bash
opencode -m llama.cpp/qwen3.5-9b
```

## 验证配置

检查 llama.cpp 服务实际上下文：

```bash
curl -s http://localhost:11434/slots | grep -o '"n_ctx":[0-9]*'
```

检查 OpenCode 配置是否生效：

```bash
opencode debug config
```

## 备份配置

```bash
cp ~/.config/opencode/opencode.json ~/my-shell/opencode.json
```

## 原理简述

### llama.cpp 启动参数

```bash
llama-server -c 131072 ...
```

| `-c` 参数值 | 实际 Slot 上下文 |
|------------|-----------------|
| 65536 | 16K |
| 131072 | 32K |
| 262144 | 64K |

**原理**：Qwen3.5-9B 原始训练上下文是 16K，`-c` 参数用于扩展上下文，实际可用约为参数的 **1/4**。

### OpenCode 配置参数

```json
{
  "model": "llama.cpp/qwen3.5-9b",
  "provider": {
    "llama.cpp": {
      "options": { "baseURL": "http://localhost:11434/v1" },
      "models": {
        "qwen3.5-9b": {
          "maxContextWindow": 131072,
          "maxOutputTokens": 65536,
          "options": { "num_ctx": 131072 }
        }
      }
    }
  }
}
```

| 配置项 | 作用 |
|--------|------|
| `maxContextWindow` | 声明最大上下文窗口 |
| `options.num_ctx` | 传递给 API 的实际上下文参数 |
| `maxOutputTokens` | 最大输出 tokens |

## 解决思路

1. 修改 llama.cpp 启动参数 `-c` 扩展上下文
2. 修改 OpenCode 配置 `num_ctx` 匹配服务端
3. 两者需同时匹配，否则会报 `exceeds context size` 错误
