#!/usr/bin/env python3
"""
测试 ExLlamaV2 API 性能 - 生成20个 Python 编程题并测量 token 速度
"""

import requests
import time
import json
import statistics

API_URL = "http://localhost:11435/v1/chat/completions"
MODEL = "qwen-coder-14b"


def generate_coding_tasks():
    """生成20个 Python 编程题目"""
    return [
        "写一个函数实现斐波那契数列",
        "实现快速排序算法",
        "写一个二分查找函数",
        "实现链表反转",
        "写一个函数判断回文字符串",
        "实现归并排序",
        "写一个函数计算阶乘",
        "实现 LRU 缓存",
        "写一个函数找数组中的最大值和最小值",
        "实现冒泡排序",
        "写一个函数检查括号是否匹配",
        "实现一个简单的计算器类",
        "写一个函数删除链表中的重复元素",
        "实现堆排序",
        "写一个函数找两个数的最大公约数",
        "实现选择排序",
        "写一个函数实现字符串反转",
        "实现插入排序",
        "写一个函数计算平方根（不使用内置函数）",
        "实现一个简单的栈类",
    ]


def test_api_speed(prompt, task_num):
    """测试单个任务的 API 速度"""
    print(f"\n[{task_num}/20] 任务: {prompt[:30]}...")

    headers = {"Content-Type": "application/json"}

    data = {
        "model": MODEL,
        "messages": [{"role": "user", "content": f"用 Python 实现: {prompt}"}],
        "max_tokens": 256,
        "temperature": 0.0,
        "stream": False,
    }

    start_time = time.time()

    try:
        response = requests.post(API_URL, headers=headers, json=data, timeout=30)
        response.raise_for_status()

        end_time = time.time()
        elapsed = end_time - start_time

        result = response.json()

        if "choices" in result and len(result["choices"]) > 0:
            content = result["choices"][0]["message"]["content"]
            completion_tokens = result.get("usage", {}).get("completion_tokens", 0)
            prompt_tokens = result.get("usage", {}).get("prompt_tokens", 0)

            tokens_per_sec = completion_tokens / elapsed if elapsed > 0 else 0

            print(f"  ✓ 完成!")
            print(f"  耗时: {elapsed:.2f}s")
            print(f"  Token数: {completion_tokens} (生成) + {prompt_tokens} (输入)")
            print(f"  速度: {tokens_per_sec:.2f} tokens/sec")

            return {
                "task": prompt,
                "elapsed": elapsed,
                "completion_tokens": completion_tokens,
                "prompt_tokens": prompt_tokens,
                "tokens_per_sec": tokens_per_sec,
            }
        else:
            print(f"  ✗ API 返回异常: {result}")
            return None

    except Exception as e:
        print(f"  ✗ 错误: {e}")
        return None


def main():
    print("=" * 60)
    print("ExLlamaV2 API 性能测试")
    print("=" * 60)
    print(f"API地址: {API_URL}")
    print(f"模型: {MODEL}")
    print(f"任务数: 20 个 Python 编程题")
    print("=" * 60)

    tasks = generate_coding_tasks()
    results = []

    for i, task in enumerate(tasks, 1):
        result = test_api_speed(task, i)
        if result:
            results.append(result)

    # 统计结果
    if results:
        speeds = [r["tokens_per_sec"] for r in results]
        times = [r["elapsed"] for r in results]
        total_tokens = sum(r["completion_tokens"] for r in results)

        print("\n" + "=" * 60)
        print("测试结果汇总")
        print("=" * 60)
        print(f"成功任务: {len(results)}/{len(tasks)}")
        print(f"总生成 token: {total_tokens}")
        print(f"\n速度统计 (tokens/sec):")
        print(f"  平均: {statistics.mean(speeds):.2f}")
        print(f"  最快: {max(speeds):.2f}")
        print(f"  最慢: {min(speeds):.2f}")
        print(f"  中位数: {statistics.median(speeds):.2f}")
        print(f"\n耗时统计 (秒):")
        print(f"  平均: {statistics.mean(times):.2f}")
        print(f"  总耗时: {sum(times):.2f}")
        print("=" * 60)
    else:
        print("\n✗ 所有任务都失败了")


if __name__ == "__main__":
    main()
