#!/usr/bin/env python3
"""
Mentor MCP 服务 (标准 MCP 协议实现)
=========================================
本地小模型通过此服务向云端导师(我)请教问题

=================================================================================
一、启动方式
=================================================================================

方式1: HTTP 模式 (推荐，用于 OpenCode)
-----------------------------------------
    cd ~/my-shell
    python3 mentor_mcp.py --http
    
    # 服务启动在 http://localhost:5000
    # 端点:
    #   POST /mcp     - MCP 协议接口
    #   GET  /mcp/tools - 列出工具
    #   GET  /health  - 健康检查

方式2: stdio 模式 (用于本地调试)
-----------------------------------------
    python3 mentor_mcp.py
    
    # 通过标准输入输出 JSON-RPC 通信

方式3: 后台长期运行
-----------------------------------------
    cd ~/my-shell
    nohup python3 mentor_mcp.py --http > /tmp/mentor_mcp.log 2>&1 &
    
    # 查看日志
    tail -f /tmp/mentor_mcp.log
    
    # 停止服务
    pkill -f mentor_mcp.py

=================================================================================
二、OpenCode 配置
=================================================================================

1. 确保 mentor_mcp.py 在 ~/my-shell 目录下

2. 修改 ~/.config/opencode/opencode.json，添加 mentor MCP 配置:

{
  "mcp": {
    "mentor": {
      "type": "http",
      "url": "http://localhost:5000/mcp",
      "enabled": true
    }
  }
}

注意: 需要先启动 mentor_mcp.py --http 服务

3. 重启 OpenCode 使配置生效

=================================================================================
三、使用方法
=================================================================================

本地小模型遇到困难时，可以调用以下工具请教我:

1. ask_mentor - 向云端导师请教问题
-----------------------------------------
    {
      "tool": "ask_mentor",
      "arguments": {
        "question": "这段代码怎么优化？",
        "context": "相关代码片段(可选)"
      }
    }

2. explain_code - 请导师解释代码
-----------------------------------------
    {
      "tool": "explain_code",
      "arguments": {
        "code": "需要解释的代码"
      }
    }

3. review_code - 请导师审查代码
-----------------------------------------
    {
      "tool": "review_code",
      "arguments": {
        "code": "需要审查的代码"
      }
    }

4. optimize_code - 请导师优化代码
-----------------------------------------
    {
      "tool": "optimize_code",
      "arguments": {
        "code": "需要优化的代码",
        "focus": "performance|readability|both"
      }
    }

=================================================================================
四、测试
=================================================================================

1. 启动服务后测试工具列表:
    curl http://localhost:5000/mcp/tools

2. 测试调用:
    curl -X POST http://localhost:5000/mcp \
      -H "Content-Type: application/json" \
      -d '{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
          "name": "ask_mentor",
          "arguments": {"question": "Python 如何实现快速排序?"}
        }
      }'

=================================================================================
"""

import os
import sys
import json
import asyncio
import requests
from pathlib import Path
from typing import Any, Optional
from dataclasses import dataclass

# 读取 .env 文件
env_file = Path(__file__).parent / ".env"
if env_file.exists():
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and "=" in line and not line.startswith("#"):
                key, value = line.split("=", 1)
                os.environ.setdefault(key, value)

MINIMAX_API_KEY = os.environ.get("MINIMAX_API_KEY", "")
MINIMAX_API_HOST = os.environ.get("MINIMAX_API_HOST", "https://api.minimaxi.com")
BASE_URL = f"{MINIMAX_API_HOST}/v1/chat/completions"


# ==================== MCP 协议实现 ====================


@dataclass
class MCPRequest:
    """MCP 请求"""

    jsonrpc: str
    id: Optional[Any]
    method: str
    params: Optional[dict] = None


@dataclass
class MCPResponse:
    """MCP 响应"""

    jsonrpc: str = "2.0"
    id: Optional[Any] = None
    result: Optional[Any] = None
    error: Optional[dict] = None


class MentorMCPServer:
    """Mentor MCP 服务器"""

    def __init__(self):
        self.protocol_version = "2024-11-05"
        self.capabilities = {"tools": {}}

    def handle_request(self, request: MCPRequest) -> MCPResponse:
        """处理 MCP 请求"""
        method = request.method

        if method == "initialize":
            return self._initialize(request)
        elif method == "tools/list":
            return self._list_tools(request)
        elif method == "tools/call":
            return self._call_tool(request)
        elif method == "ping":
            return MCPResponse(id=request.id, result={"pong": True})
        else:
            return MCPResponse(
                id=request.id,
                error={"code": -32601, "message": f"Method not found: {method}"},
            )

    def _initialize(self, request: MCPRequest) -> MCPResponse:
        """初始化"""
        return MCPResponse(
            id=request.id,
            result={
                "protocolVersion": self.protocol_version,
                "capabilities": self.capabilities,
                "serverInfo": {"name": "mentor-mcp", "version": "1.0.0"},
            },
        )

    def _list_tools(self, request: MCPRequest) -> MCPResponse:
        """列出工具"""
        tools = [
            {
                "name": "ask_mentor",
                "description": "向云端导师(我)请教编程问题 - 适用于本地小模型遇到困难时调用",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "question": {"type": "string", "description": "需要请教的问题"},
                        "context": {
                            "type": "string",
                            "description": "相关上下文代码片段(可选)",
                        },
                    },
                    "required": ["question"],
                },
            },
            {
                "name": "explain_code",
                "description": "请云端导师解释代码功能和原理",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "code": {"type": "string", "description": "需要解释的代码"}
                    },
                    "required": ["code"],
                },
            },
            {
                "name": "review_code",
                "description": "请云端导师审查代码并给出改进建议",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "code": {"type": "string", "description": "需要审查的代码"}
                    },
                    "required": ["code"],
                },
            },
            {
                "name": "optimize_code",
                "description": "请云端导师优化代码性能和可读性",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "code": {"type": "string", "description": "需要优化的代码"},
                        "focus": {
                            "type": "string",
                            "description": "优化重点: performance/readability/both",
                        },
                    },
                    "required": ["code"],
                },
            },
        ]
        return MCPResponse(id=request.id, result={"tools": tools})

    def _call_tool(self, request: MCPRequest) -> MCPResponse:
        """调用工具"""
        params = request.params or {}
        tool_name = params.get("name")
        arguments = params.get("arguments", {})

        try:
            if tool_name == "ask_mentor":
                result = self._ask_mentor(
                    arguments.get("question", ""), arguments.get("context", "")
                )
            elif tool_name == "explain_code":
                result = self._explain_code(arguments.get("code", ""))
            elif tool_name == "review_code":
                result = self._review_code(arguments.get("code", ""))
            elif tool_name == "optimize_code":
                result = self._optimize_code(
                    arguments.get("code", ""), arguments.get("focus", "both")
                )
            else:
                return MCPResponse(
                    id=request.id,
                    error={"code": -32602, "message": f"Tool not found: {tool_name}"},
                )

            return MCPResponse(
                id=request.id,
                result={
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(result, ensure_ascii=False, indent=2),
                        }
                    ]
                },
            )

        except Exception as e:
            return MCPResponse(id=request.id, error={"code": -32603, "message": str(e)})

    def call_minimax(self, prompt: str) -> str:
        """调用 MiniMax API"""
        headers = {
            "Authorization": f"Bearer {MINIMAX_API_KEY}",
            "Content-Type": "application/json",
        }

        payload = {
            "model": "MiniMax-M2.5",
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 8192,
            "temperature": 0.7,
        }

        response = requests.post(BASE_URL, headers=headers, json=payload, timeout=180)
        result = response.json()
        return result["choices"][0]["message"]["content"]

    def _ask_mentor(self, question: str, context: str = "") -> dict:
        """向云端导师请教问题"""
        context_part = ("相关上下文:\n" + context) if context else ""
        prompt = f"""你是一个经验丰富的编程导师。本地小模型遇到了以下问题，需要你的指导。

{context_part}

问题: {question}

请给出清晰、易懂的指导答案。如果涉及代码，请给出具体示例。"""

        answer = self.call_minimax(prompt)
        return {"answer": answer, "tool": "ask_mentor"}

    def _explain_code(self, code: str) -> dict:
        """请导师解释代码"""
        prompt = f"""请解释以下代码的功能和原理:

```{code}
```

请用通俗易懂的语言解释，并说明关键点。"""

        answer = self.call_minimax(prompt)
        return {"explanation": answer, "tool": "explain_code"}

    def _review_code(self, code: str) -> dict:
        """请导师审查代码"""
        prompt = f"""请审查以下代码，指出问题并给出改进建议:

```{code}
```

请从以下方面审查:
1. 代码正确性
2. 性能问题
3. 安全隐患
4. 代码风格
5. 可改进的地方"""

        answer = self.call_minimax(prompt)
        return {"review": answer, "tool": "review_code"}

    def _optimize_code(self, code: str, focus: str = "both") -> dict:
        """请导师优化代码"""
        prompt = f"""请优化以下代码:

```{code}
```

优化重点: {focus}
- performance: 性能优化
- readability: 可读性优化
- both: 两者兼顾

请给出优化后的代码和优化说明。"""

        answer = self.call_minimax(prompt)
        return {"optimized": answer, "tool": "optimize_code"}


# ==================== stdio 模式 ====================


def run_stdio():
    """运行 stdio 模式"""
    server = MentorMCPServer()

    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break

            request_data = json.loads(line.strip())
            request = MCPRequest(**request_data)

            response = server.handle_request(request)
            print(
                json.dumps(
                    {
                        "jsonrpc": response.jsonrpc,
                        "id": response.id,
                        "result": response.result,
                        "error": response.error,
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )

        except EOFError:
            break
        except Exception as e:
            print(
                json.dumps(
                    {"jsonrpc": "2.0", "error": {"code": -32603, "message": str(e)}},
                    ensure_ascii=False,
                ),
                flush=True,
            )


# ==================== HTTP 模式 ====================


def run_http():
    """运行 HTTP 模式"""
    from flask import Flask, request, jsonify

    app = Flask(__name__)
    server = MentorMCPServer()

    @app.route("/mcp", methods=["POST"])
    def handle_mcp():
        data = request.json
        request_obj = MCPRequest(
            jsonrpc=data.get("jsonrpc", "2.0"),
            id=data.get("id"),
            method=data.get("method"),
            params=data.get("params"),
        )
        response = server.handle_request(request_obj)
        return jsonify(
            {
                "jsonrpc": response.jsonrpc,
                "id": response.id,
                "result": response.result,
                "error": response.error,
            }
        )

    @app.route("/mcp/tools", methods=["GET"])
    def list_tools():
        return jsonify(
            server._list_tools(MCPRequest(jsonrpc="2.0", id=None, method="")).result
        )

    @app.route("/health", methods=["GET"])
    def health():
        return jsonify({"status": "ok", "server": "mentor-mcp"})

    print("=" * 50)
    print("Mentor MCP 服务已启动 (HTTP 模式)")
    print("=" * 50)
    print("端点:")
    print("  POST /mcp     - MCP 协议接口")
    print("  GET  /mcp/tools - 列出工具")
    print("  GET  /health  - 健康检查")
    print("=" * 50)
    app.run(host="0.0.0.0", port=5000, debug=False)


# ==================== 主入口 ====================

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--http":
        run_http()
    else:
        run_stdio()
