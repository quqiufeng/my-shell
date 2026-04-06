"""
ExLlamaV2 封装库 - Qwen2.5 模型
"""

import sys
import os
import re
import json
import torch
from typing import Optional, List, Dict, Any, Iterator

from exllamav2 import (
    ExLlamaV2,
    ExLlamaV2Config,
    ExLlamaV2Cache,
    ExLlamaV2Tokenizer,
)
from exllamav2.generator import (
    ExLlamaV2DynamicGenerator,
    ExLlamaV2DynamicJob,
    ExLlamaV2Sampler,
)


class PromptFormat_qwen25:
    """Qwen2.5 ChatML 格式"""

    def __init__(self):
        self.username = "user"
        self.botname = "assistant"

    def format(
        self, messages: List[Dict[str, str]], tools: Optional[List[Dict]] = None
    ) -> str:
        prompt = ""
        for msg in messages:
            role = msg["role"]
            content = msg.get("content", "")

            if role == "system":
                prompt += f"<|im_start|>system\n{content}<|im_end|>\n"
            elif role == "user":
                prompt += f"<|im_start|>user\n{content}<|im_end|>\n"
            elif role == "assistant":
                prompt += f"<|im_start|>assistant\n{content}<|im_end|>\n"
            elif role == "tool":
                prompt += f"<|im_start|>user\n{content}<|im_end|>\n"

        prompt += "<|im_start|>assistant\n"
        return prompt

    def stop_conditions(self, tokenizer) -> List:
        return [
            tokenizer.eos_token_id,
            tokenizer.single_id("<|im_end|>"),
        ]

    def encoding_options(self) -> tuple:
        return False, False, True


class Qwen25Chat:
    """Qwen2.5 聊天类 (ExLlamaV2)"""

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
        repeat_penalty: float = 1.1,
    ):
        self.model_dir = model_dir
        self.max_seq_len = max_seq_len
        self.total_context = total_context
        self.max_batch_size = max_batch_size
        self.max_chunk_size = max_chunk_size
        self.temperature = temperature
        self.top_k = top_k
        self.top_p = top_p
        self.repeat_penalty = repeat_penalty

        self.model = None
        self.cache = None
        self.tokenizer = None
        self.generator = None
        self.prompt_format = PromptFormat_qwen25()

    def load(self, progressbar: bool = True):
        config = ExLlamaV2Config(self.model_dir)
        config.arch_compat_overrides()
        config.max_input_len = self.max_chunk_size
        config.max_attention_size = self.max_chunk_size**2

        self.model = ExLlamaV2(config)
        self.cache = ExLlamaV2Cache(
            self.model,
            max_seq_len=self.total_context,
            lazy=True,
        )
        self.model.load_autosplit(self.cache, progress=progressbar)

        self.tokenizer = ExLlamaV2Tokenizer(config)

        self.generator = ExLlamaV2DynamicGenerator(
            model=self.model,
            cache=self.cache,
            tokenizer=self.tokenizer,
            max_batch_size=self.max_batch_size,
            max_chunk_size=self.max_chunk_size,
        )

        self.generator.warmup()

    def generate(
        self,
        messages: List[Dict[str, str]],
        max_new_tokens: int = 1024,
        tools: Optional[List[Dict]] = None,
    ) -> str:
        prompt = self.prompt_format.format(messages, tools)

        add_bos, _, _ = self.prompt_format.encoding_options()
        input_ids = self.tokenizer.encode(prompt, add_bos=add_bos)

        stop_tokens = self.prompt_format.stop_conditions(self.tokenizer)

        job = ExLlamaV2DynamicJob(
            input_ids=input_ids,
            max_new_tokens=max_new_tokens,
            stop_conditions=stop_tokens,
            sampling_settings=ExLlamaV2Sampler.Settings(
                temperature=self.temperature,
                top_k=self.top_k,
                top_p=self.top_p,
                token_repetition_penalty=self.repeat_penalty,
            ),
        )

        self.generator.enqueue(job)

        output = ""
        eos = False
        while not eos:
            results = self.generator.iterate()
            if not results:
                break
            for result in results:
                if result["stage"] == "streaming":
                    if "text" in result:
                        output += result["text"]
                    if result.get("eos", False):
                        eos = True

        return output

    def generate_stream(
        self,
        messages: List[Dict[str, str]],
        max_new_tokens: int = 1024,
        tools: Optional[List[Dict]] = None,
    ) -> Iterator[Dict[str, Any]]:
        prompt = self.prompt_format.format(messages, tools)

        add_bos, _, _ = self.prompt_format.encoding_options()
        input_ids = self.tokenizer.encode(prompt, add_bos=add_bos)

        stop_tokens = self.prompt_format.stop_conditions(self.tokenizer)

        job = ExLlamaV2DynamicJob(
            input_ids=input_ids,
            max_new_tokens=max_new_tokens,
            stop_conditions=stop_tokens,
            sampling_settings=ExLlamaV2Sampler.Settings(
                temperature=self.temperature,
                top_k=self.top_k,
                top_p=self.top_p,
                token_repetition_penalty=self.repeat_penalty,
            ),
        )

        self.generator.enqueue(job)

        while True:
            results = self.generator.iterate()
            for result in results:
                if result["stage"] == "prefill":
                    continue
                if result["stage"] == "streaming":
                    yield {
                        "text": result.get("text", ""),
                        "eos": result.get("eos", False),
                    }
                    if result.get("eos", False):
                        return
            if not job.active:
                return


class Qwen25Server(Qwen25Chat):
    """Qwen2.5 API 服务器 (ExLlamaV2)"""

    def __init__(self, *args, port: int = 11434, **kwargs):
        super().__init__(*args, **kwargs)
        self.port = port
