"""
ExLlamaV2 API Handler for Qwen2.5
"""

import json
import re
import time
from typing import Dict, List, Optional, Any

from exllamav2_lib import Qwen25Chat


class Qwen25APIHandler:
    """Qwen2.5 API Handler (ExLlamaV2)"""

    def __init__(
        self,
        model_dir: str,
        max_seq_len: int = 32768,
        total_context: int = 16384,
        max_batch_size: int = 8,
        max_chunk_size: int = 2048,
        temperature: float = 0.95,
        top_k: int = 50,
        top_p: float = 0.8,
        model_name: str = "qwen2.5-coder-7b-exl2",
        default_system_prompt: str = "You are a helpful assistant.",
    ):
        self.model_name = model_name
        self.max_seq_len = max_seq_len
        self.default_system_prompt = default_system_prompt

        self.chat = Qwen25Chat(
            model_dir=model_dir,
            max_seq_len=max_seq_len,
            total_context=total_context,
            max_batch_size=max_batch_size,
            max_chunk_size=max_chunk_size,
            temperature=temperature,
            top_k=top_k,
            top_p=top_p,
        )

    def load(self, progressbar: bool = True):
        self.chat.load(progressbar=progressbar)

    def parse_messages(self, data: Dict[str, Any]) -> tuple:
        messages = data.get("messages", [])
        max_tokens = data.get("max_tokens", 4096)

        if not messages:
            return [], "", max_tokens

        system_prompt = self.default_system_prompt
        parsed_messages = []

        for msg in messages:
            role = msg.get("role", "user")
            content = msg.get("content", "")

            if role == "system":
                system_prompt = content
            elif role in ("user", "assistant"):
                parsed_messages.append({"role": role, "content": content})
            elif role == "tool":
                parsed_messages.append({"role": "tool", "content": content})

        if parsed_messages and parsed_messages[0].get("role") != "system":
            parsed_messages.insert(0, {"role": "system", "content": system_prompt})
        else:
            parsed_messages[0]["content"] = system_prompt

        return parsed_messages, "", max_tokens

    def parse_tool_calls(self, text: str) -> Optional[List[Dict]]:
        tool_call_pattern = r"<tool_call>\s*(\w+)\s*:\s*(\{[^}]+\})\s*</tool_call>"
        matches = re.findall(tool_call_pattern, text, re.DOTALL)

        if not matches:
            return None

        tool_calls = []
        for name, params_str in matches:
            try:
                params = json.loads(params_str)
                tool_calls.append(
                    {
                        "id": f"call_{len(tool_calls)}",
                        "type": "function",
                        "function": {"name": name, "arguments": json.dumps(params)},
                    }
                )
            except json.JSONDecodeError:
                continue

        return tool_calls if tool_calls else None

    async def generate_completion(self, data: Dict[str, Any]) -> Dict[str, Any]:
        messages, _, max_tokens = self.parse_messages(data)

        if not messages:
            return {
                "id": f"chatcmpl-{int(time.time())}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": self.model_name,
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": ""},
                        "finish_reason": "length",
                    }
                ],
                "usage": {
                    "prompt_tokens": 0,
                    "completion_tokens": 0,
                    "total_tokens": 0,
                },
            }

        text = self.chat.generate(messages, max_new_tokens=max_tokens)

        tool_calls = self.parse_tool_calls(text)

        if tool_calls:
            content = "EMPTY"
        else:
            content = text

        return {
            "id": f"chatcmpl-{int(time.time())}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": self.model_name,
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": content,
                        "tool_calls": tool_calls,
                    },
                    "finish_reason": "tool_calls" if tool_calls else "stop",
                }
            ],
            "usage": {
                "prompt_tokens": self._count_tokens(content),
                "completion_tokens": self._count_tokens(content),
                "total_tokens": self._count_tokens(content) * 2,
            },
        }

    def _count_tokens(self, text: str) -> int:
        if not text or text == "EMPTY":
            return 0
        return len(text) // 4

    async def generate_completion_stream(self, data: Dict[str, Any]):
        messages, _, max_tokens = self.parse_messages(data)

        if not messages:
            yield {"error": "No messages provided"}
            return

        id_ = f"chatcmpl-{int(time.time())}"

        yield f"data: {json.dumps({'id': id_, 'object': 'chat.completion.chunk', 'created': int(time.time()), 'model': self.model_name, 'choices': [{'index': 0, 'delta': {'role': 'assistant'}, 'finish_reason': None}]})}\n\n"

        full_text = ""
        for chunk in self.chat.generate_stream(messages, max_new_tokens=max_tokens):
            text = chunk.get("text", "")
            if text:
                full_text += text
                yield f"data: {json.dumps({'id': id_, 'object': 'chat.completion.chunk', 'created': int(time.time()), 'model': self.model_name, 'choices': [{'index': 0, 'delta': {'content': text}, 'finish_reason': None}]})}\n\n"

            if chunk.get("eos", False):
                tool_calls = self.parse_tool_calls(full_text)
                if tool_calls:
                    for tc in tool_calls:
                        yield f"data: {json.dumps({'id': id_, 'object': 'chat.completion.chunk', 'created': int(time.time()), 'model': self.model_name, 'choices': [{'index': 0, 'delta': {'tool_calls': [tc]}, 'finish_reason': None}]})}\n\n"

                yield f"data: {json.dumps({'id': id_, 'object': 'chat.completion.chunk', 'created': int(time.time()), 'model': self.model_name, 'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'tool_calls' if tool_calls else 'stop'}]})}\n\n"
                yield "data: [DONE]\n\n"
                break

    async def responses_endpoint(self, request) -> Dict[str, Any]:
        data = await request.json()

        input_text = data.get("input", "")
        max_tokens = data.get("max_tokens", 4096)

        messages = [
            {"role": "system", "content": self.default_system_prompt},
            {"role": "user", "content": input_text},
        ]

        text = self.chat.generate(messages, max_new_tokens=max_tokens)

        tool_calls = self.parse_tool_calls(text)

        if tool_calls:
            return {
                "id": f"resp-{int(time.time())}",
                "object": "response",
                "created": int(time.time()),
                "model": self.model_name,
                "choices": [
                    {
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": "EMPTY",
                            "tool_calls": tool_calls,
                        },
                        "finish_reason": "tool_calls",
                    }
                ],
                "usage": {
                    "prompt_tokens": 0,
                    "completion_tokens": 0,
                    "total_tokens": 0,
                },
            }

        return {
            "id": f"resp-{int(time.time())}",
            "object": "response",
            "created": int(time.time()),
            "model": self.model_name,
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": text},
                    "finish_reason": "stop",
                }
            ],
            "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
        }
