# 4090D 模型脚本

## 14B 模型速度对比 (4090D 24GB, KoboldCpp)

| 模型 | 量化 | 大小 | 上下文 | 速度 | 备注 |
|------|------|------|--------|------|------|
| **Qwen3-14B-Q4_K_M** | Q4_K_M | 9GB | 80K | **~75 tok/s** | 基础版 |
| **Qwen3-14B-Claude-4.5-Opus-Distill** | Q4_K_M | 9GB | 80K | **~74-75 tok/s** | Claude推理蒸馏 |
| **Qwen3-14B-Q5_K_M** | Q5_K_M | 10.5GB | 80K | **~67 tok/s** | 精度更高但更慢 |

**结论**: 14B 是甜点位，Q4_K_M 速度最快

## 启动脚本

| 脚本 | 模型 |
|------|------|
| `run_qwen3-14b_koboldcpp.sh` | Qwen3-14B-Q4_K_M |
| `run_qwen3-14b-claude-45-opus-distill_koboldcpp.sh` | Qwen3-14B-Claude-4.5-Opus-Distill |
| `run_qwen3-14b_q5_k_m_koboldcpp.sh` | Qwen3-14B-Q5_K_M |

## 启动命令

```bash
cd /opt/my-shell/4090d
nohup ./run_qwen3-14b_koboldcpp.sh > /tmp/14b_koboldcpp.log 2>&1 &
```

## 停止服务

```bash
pkill -f koboldcpp.py
```

## 测试 API

```bash
curl http://localhost:11434/v1/models
```

## 性能测试

```bash
cd /opt/my-shell
python3 test_api.py
```

## OpenCode 配置

路径: `~/.config/opencode/opencode.json`

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "openai/Qwen3-14B-Q4_K_M.gguf",
  "provider": {
    "openai": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local Models",
      "options": {
        "baseURL": "http://localhost:11434/v1",
        "apiKey": "dummy"
      },
      "models": {
        "Qwen3-14B-Q4_K_M.gguf": {
          "name": "Qwen3-14B-Q4_K_M.gguf",
          "maxContextWindow": 81920,
          "maxOutputTokens": 32768
        }
      }
    }
  }
}
```

使用: `opencode -m openai/Qwen3-14B-Q4_K_M.gguf`
