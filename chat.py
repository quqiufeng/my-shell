#!/usr/bin/env python3
"""
Qwen3.5 Chat Library - exllamav3
RTX 3080 10GB optimization
"""

import sys
import time
import socket
import json
import torch
from typing import Optional, Literal
from exllamav3 import Model, Config, Cache, Tokenizer, Generator
from exllamav3.cache import CacheLayer_fp16, CacheLayer_quant
from exllamav3.generator.sampler import ComboSampler
from exllamav3.generator import Job


class PromptFormat:
    def __init__(self, bot_name: str = "assistant", user_name: str = "user"):
        self.bot_name = bot_name
        self.user_name = user_name

    def default_system_prompt(self, think: bool) -> str:
        raise NotImplementedError

    def format(self, system_prompt: str, messages: list, think: bool) -> str:
        raise NotImplementedError

    def add_bos(self) -> bool:
        raise NotImplementedError

    def stop_conditions(self, tokenizer) -> list:
        raise NotImplementedError

    def thinktag(self):
        return None, None


class PromptFormat_qwen35(PromptFormat):
    description = "Qwen3.5 format, reasoning-aware ChatML"

    def default_system_prompt(self, think: bool = False) -> str:
        if think:
            return "You are a helpful AI assistant that can think step by step."
        return "You are a helpful AI assistant. Do not think step by step. Answer directly and concisely."

    def format(self, system_prompt: str, messages: list, think: bool = False) -> str:
        context = f"<|im_start|>system\n{system_prompt}<|im_end|>\n"
        for msg in messages:
            role = msg.get("role", "user")
            content = msg.get("content", "")
            context += f"<|im_start|>{role}\n{content}<|im_end|>\n"
            if role == "assistant" and not think:
                context += f"<|im_start|>assistant\n"
        context += "<|im_start|>assistant\n"
        return context

    def add_bos(self) -> bool:
        return False

    def stop_conditions(self, tokenizer):
        return [
            tokenizer.eos_token_id,
            tokenizer.single_id("<|im_end|>"),
            "<|im_end|>",
        ]

    def thinktag(self):
        return ("\u600e\u8003\n", "\u7ed3\u675f\n\n")


class Qwen35Chat:
    DEFAULT_SYSTEM_PROMPT = "You are a helpful AI assistant. Do not think step by step. Answer directly and concisely."

    def __init__(
        self,
        model_dir: str,
        max_seq_len: int = 131072,
        cache_tokens: int = 65536,
        max_batch_size: int = 1,
        max_chunk_size: int = 2048,
        device: str = "cuda",
        k_bits: int = 4,
        v_bits: int = 4,
        cache_type: str = "quant",
    ):
        self.model_dir = model_dir
        self.max_seq_len = max_seq_len
        self.cache_tokens = cache_tokens
        self.max_batch_size = max_batch_size
        self.max_chunk_size = max_chunk_size
        self.device = device
        self.k_bits = k_bits
        self.v_bits = v_bits
        self.cache_type = cache_type

        self.model = None
        self.cache = None
        self.tokenizer = None
        self.generator = None
        self.prompt_format = PromptFormat_qwen35()

    def load(self, progressbar: bool = True):
        config = Config.from_directory(self.model_dir)
        config.flash_attn = True

        self.model = Model.from_config(config)

        if self.cache_type == "fp16":
            self.cache = Cache(
                self.model,
                max_num_tokens=self.cache_tokens,
                layer_type=CacheLayer_fp16,
            )
        else:
            self.cache = Cache(
                self.model,
                max_num_tokens=self.cache_tokens,
                layer_type=CacheLayer_quant,
                k_bits=self.k_bits,
                v_bits=self.v_bits,
            )
        self.tokenizer = Tokenizer.from_config(config)

        self.model.load(progressbar=progressbar)

        self.generator = Generator(
            model=self.model,
            cache=self.cache,
            tokenizer=self.tokenizer,
            max_batch_size=self.max_batch_size,
            max_chunk_size=self.max_chunk_size,
        )

        print(f"VRAM: {torch.cuda.memory_allocated() / 1024**3:.2f} GB")

    def format_prompt(
        self,
        messages: list,
        system_prompt: Optional[str] = None,
        think: bool = False,
    ) -> str:
        if system_prompt is None:
            system_prompt = (
                self.DEFAULT_SYSTEM_PROMPT
                if not think
                else self.prompt_format.default_system_prompt(think)
            )
        return self.prompt_format.format(system_prompt, messages, think)

    def generate_text(
        self,
        prompt: str,
        max_new_tokens: int = 1024,
        temperature: float = 0.0,
        top_p: float = 0.9,
        min_p: float = 0.0,
        top_k: int = 0,
        rep_p: float = 1.0,
        rep_decay_range: int = 1024,
        add_bos: bool = False,
    ) -> str:
        sampler = ComboSampler(
            temperature=temperature,
            top_p=top_p,
            min_p=min_p,
            top_k=top_k,
            rep_p=rep_p,
            rep_decay_range=rep_decay_range,
        )

        stop_conditions = self.prompt_format.stop_conditions(self.tokenizer)

        response = self.generator.generate(
            prompt=prompt,
            max_new_tokens=max_new_tokens,
            sampler=sampler,
            stop_conditions=stop_conditions,
            completion_only=True,
            add_bos=add_bos,
        )
        return response

    def chat(
        self,
        message: str,
        system_prompt: Optional[str] = None,
        history: Optional[list] = None,
        max_new_tokens: int = 1024,
        temperature: float = 0.0,
        think: bool = False,
    ) -> tuple[str, list]:
        if history is None:
            history = []

        messages = history + [{"role": "user", "content": message}]
        prompt = self.format_prompt(messages, system_prompt, think)
        response = self.generate_text(prompt, max_new_tokens, temperature)

        messages.append({"role": "assistant", "content": response})
        return response, messages

    def chat_stream(
        self,
        message: str,
        system_prompt: Optional[str] = None,
        history: Optional[list] = None,
        max_new_tokens: int = 1024,
        temperature: float = 0.0,
        think: bool = False,
    ):
        if history is None:
            history = []

        messages = history + [{"role": "user", "content": message}]
        prompt = self.format_prompt(messages, system_prompt, think)

        sampler = ComboSampler(
            temperature=temperature,
            top_p=0.9,
            min_p=0.0,
            top_k=0,
            rep_p=1.0,
            rep_decay_range=1024,
        )

        input_ids = self.tokenizer.encode(prompt, add_bos=False)

        job = Job(
            input_ids=input_ids,
            max_new_tokens=max_new_tokens,
            sampler=sampler,
            stop_conditions=["<|im_end|>", "<|im_start|>"],
        )

        self.generator.enqueue(job)

        while self.generator.num_remaining_jobs():
            for r in self.generator.iterate():
                if r["stage"] == "streaming":
                    chunk = r.get("text", "")
                    yield chunk

                if r.get("eos"):
                    return

    def get_token_count(self, text: str) -> int:
        ids = self.tokenizer.encode(text)
        if isinstance(ids, torch.Tensor):
            return ids.shape[-1] if ids.dim() > 0 else 1
        return len(ids)

    @property
    def vram_usage(self) -> float:
        return torch.cuda.memory_allocated() / 1024**3

    def unload(self):
        if self.model:
            self.model.unload()
            self.model = None
            self.cache = None
            self.generator = None


class Qwen35Server(Qwen35Chat):
    def __init__(
        self,
        model_dir: str,
        port: int = 11434,
        host: str = "0.0.0.0",
        **kwargs,
    ):
        super().__init__(model_dir, **kwargs)
        self.port = port
        self.host = host
        self.app = None

    def create_app(self):
        try:
            from fastapi import FastAPI, Request
            from fastapi.responses import StreamingResponse
        except ImportError:
            raise ImportError(
                "fastapi and uvicorn are required for server mode: pip install fastapi uvicorn"
            )

        app = FastAPI()

        @app.get("/v1/models")
        async def list_models():
            return {
                "object": "list",
                "data": [
                    {
                        "id": "qwen3.5-exl3",
                        "object": "model",
                        "created": int(time.time()),
                        "owned_by": "qwen",
                        "permission": [],
                        "root": "qwen3.5-exl3",
                    }
                ],
            }

        @app.post("/v1/chat/completions")
        async def chat_completions(request: Request):
            data = await request.json()
            messages = data.get("messages", [])
            model_name = data.get("model", "qwen3.5-exl3")
            max_tokens = data.get("max_tokens", self.max_seq_len - 1024)
            temperature = data.get("temperature", 0.0)
            stream = data.get("stream", False)
            system_prompt = data.get("system_prompt", self.DEFAULT_SYSTEM_PROMPT)

            if stream:

                async def generate_stream():
                    prompt = self.format_prompt(messages, system_prompt)

                    sampler = ComboSampler(
                        temperature=temperature,
                        top_p=0.9,
                        min_p=0.0,
                        top_k=0,
                        rep_p=1.0,
                        rep_decay_range=1024,
                    )

                    input_ids = self.tokenizer.encode(prompt, add_bos=False)

                    job = Job(
                        input_ids=input_ids,
                        max_new_tokens=max_tokens,
                        sampler=sampler,
                        stop_conditions=["<|im_end|>", "<|im_start|>"],
                    )

                    self.generator.enqueue(job)

                    while self.generator.num_remaining_jobs():
                        for r in self.generator.iterate():
                            if r["stage"] == "streaming":
                                chunk = r.get("text", "")
                                yield (
                                    "data: "
                                    + json.dumps(
                                        {
                                            "choices": [
                                                {
                                                    "delta": {"content": chunk},
                                                    "finish_reason": None,
                                                }
                                            ]
                                        }
                                    )
                                    + "\n\n"
                                )

                            if r.get("eos"):
                                yield (
                                    "data: "
                                    + json.dumps(
                                        {
                                            "choices": [
                                                {"delta": {}, "finish_reason": "stop"}
                                            ]
                                        }
                                    )
                                    + "\n\n"
                                )
                                yield "data: [DONE]\n\n"
                                return

                return StreamingResponse(
                    generate_stream(), media_type="text/event-stream"
                )
            else:
                prompt = self.format_prompt(messages, system_prompt)
                response_text = self.generate_text(prompt, max_new_tokens, temperature)

                input_len = self.get_token_count(prompt)
                output_len = self.get_token_count(response_text)

                return {
                    "id": f"chatcmpl-{int(time.time() * 1000)}",
                    "object": "chat.completion",
                    "created": int(time.time()),
                    "model": model_name,
                    "choices": [
                        {
                            "index": 0,
                            "message": {"role": "assistant", "content": response_text},
                            "finish_reason": "stop",
                        }
                    ],
                    "usage": {
                        "prompt_tokens": input_len,
                        "completion_tokens": output_len,
                        "total_tokens": input_len + output_len,
                    },
                }

        self.app = app
        return app

    def run(self):
        if self.app is None:
            self.create_app()

        import uvicorn

        print(f"Starting Qwen3.5 server on {self.host}:{self.port}")
        uvicorn.run(self.app, host=self.host, port=self.port)


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Qwen3.5 Chat Library")
    parser.add_argument(
        "--model-dir", type=str, required=True, help="Path to Qwen3.5 model directory"
    )
    parser.add_argument("--port", type=int, default=11434, help="Server port")
    parser.add_argument("--host", type=str, default="0.0.0.0", help="Server host")
    parser.add_argument(
        "--cache-tokens", type=int, default=65536, help="Cache token count"
    )
    parser.add_argument(
        "--max-new-tokens", type=int, default=1024, help="Max new tokens per generation"
    )
    parser.add_argument(
        "--interactive", action="store_true", help="Interactive chat mode"
    )
    parser.add_argument("--think", action="store_true", help="Enable thinking mode")

    args = parser.parse_args()

    print(f"Loading model from {args.model_dir}...")
    server = Qwen35Server(
        model_dir=args.model_dir,
        port=args.port,
        host=args.host,
        cache_tokens=args.cache_tokens,
    )
    server.load()

    if args.interactive:
        print("\n=== Qwen3.5 Interactive Chat ===")
        print("Type 'quit' or 'exit' to exit\n")
        history = []

        while True:
            try:
                user_input = input("You: ").strip()
                if user_input.lower() in ["quit", "exit"]:
                    break
                if not user_input:
                    continue

                print("\nAssistant: ", end="", flush=True)
                response, history = server.chat(
                    user_input,
                    history=history,
                    max_new_tokens=args.max_new_tokens,
                    think=args.think,
                )
                print(response)
                print()
            except KeyboardInterrupt:
                break

        print("\nGoodbye!")
    else:
        server.run()


if __name__ == "__main__":
    main()
