#!/usr/bin/env python3
import requests
import time
import sys

PORT = sys.argv[1] if len(sys.argv) > 1 else "11434"
MODEL = sys.argv[2] if len(sys.argv) > 2 else "qwen2.5-coder"
URL = f"http://localhost:{PORT}/v1/chat/completions"
MAX_TOKENS = int(sys.argv[3]) if len(sys.argv) > 3 else 100

TESTS = [
    ("快速排序", "用Python实现快速排序"),
    ("线程安全", "解释什么是线程安全"),
    ("二分查找", "写一个二分查找函数"),
    ("数据库索引", "解释数据库索引原理"),
    ("Python性能优化", "如何优化Python代码性能"),
    ("归并排序", "用Python实现归并排序"),
    ("HTTP/HTTPS", "解释HTTP与HTTPS的区别"),
    ("LRU缓存", "用Python实现LRU缓存"),
    ("堆排序", "用Python实现堆排序"),
    ("Dijkstra算法", "用Python实现Dijkstra算法"),
    ("一致性哈希", "用Python实现一致性哈希"),
    ("令牌桶", "用Python实现令牌桶限流"),
    ("阻塞队列", "用Python实现阻塞队列"),
    ("红黑树", "用Python实现红黑树"),
    ("B+树", "用Python实现B+树"),
]


def test_speed(name, prompt, tokens=MAX_TOKENS):
    start = time.time()
    r = requests.post(
        URL,
        json={
            "model": MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": tokens,
            "temperature": 0.2,
            "stream": False,
        },
        timeout=120,
    )
    elapsed = time.time() - start
    result_tokens = r.json()["usage"]["completion_tokens"]
    tps = result_tokens / elapsed
    print(
        f"Test [{name}]: {result_tokens} tokens in {elapsed:.2f}s = {tps:.1f} tokens/s"
    )
    return tps


def print_usage():
    print("Usage: python3 branch.py <port> <model_name> [max_tokens]")
    print("  port: API端口 (默认: 11434)")
    print("  model_name: 模型名称 (默认: qwen2.5-coder)")
    print("  max_tokens: 生成token数 (默认: 100)")
    print("")
    print("示例:")
    print("  python3 branch.py 11435 qwen2.5-coder-14b-exl2 500")
    print("  python3 branch.py 11434 qwen2.5-coder-32b 100")


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ["-h", "--help"]:
        print_usage()
        return

    print("=" * 60)
    print("API 性能测试")
    print("=" * 60)
    print(f"地址: {URL}")
    print(f"模型: {MODEL}")
    print(f"Max tokens: {MAX_TOKENS}")
    print("=" * 60)
    results = []
    for i, (name, prompt) in enumerate(TESTS, 1):
        try:
            tps = test_speed(name, prompt)
            results.append(tps)
        except Exception as e:
            print(f"Test {i} [{name}] 失败: {e}")

    if results:
        avg = sum(results) / len(results)
        print("=" * 60)
        print(f"平均速度: {avg:.1f} tokens/s")
        print("=" * 60)


if __name__ == "__main__":
    main()
