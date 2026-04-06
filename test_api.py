#!/usr/bin/env python3
"""
API 性能测试脚本

================================================================================
基准测试结果 - 2026-04-06
================================================================================

[测试环境]
- GPU: RTX 3080 10GB
- 模型: Qwen3.5-9B EXL3 (4bpw)
- 服务: exllamav3

[性能测试结果]
| 测试项 | 耗时 | Token数 | 速度 |
|--------|------|---------|------|
| 快速排序 | 20.93s | 1023 | 48.9 tok/s |
| 线程安全 | 17.19s | 1023 | 59.5 tok/s |
| 二分查找 | 11.82s | 530 | 44.9 tok/s |
| 数据库索引 | 17.34s | 1023 | 59.0 tok/s |
| Python性能优化 | 19.93s | 1023 | 51.3 tok/s |
| 归并排序 | 17.25s | 1023 | 59.3 tok/s |
| HTTP/HTTPS | 20.45s | 1022 | 50.0 tok/s |
| LRU缓存 | 13.74s | 811 | 59.0 tok/s |
| 堆排序 | 20.12s | 1023 | 50.8 tok/s |
| Dijkstra算法 | 6.72s | 391 | 58.2 tok/s |
| 一致性哈希 | 17.25s | 1023 | 59.3 tok/s |
| 令牌桶 | 20.24s | 1023 | 50.5 tok/s |
| 阻塞队列 | 19.68s | 1023 | 52.0 tok/s |
| 红黑树 | 17.77s | 1023 | 57.6 tok/s |
| B+树 | 21.65s | 1023 | 47.3 tok/s |
| A*算法 | 21.19s | 1023 | 48.3 tok/s |
| KMP算法 | 22.82s | 1023 | 44.8 tok/s |
| 布隆过滤器 | 22.57s | 1023 | 45.3 tok/s |
| 跳表 | 19.66s | 1023 | 52.0 tok/s |
| 并查集 | 21.99s | 1023 | 46.5 tok/s |
| 线段树 | 17.41s | 964 | 55.4 tok/s |
| 字典树 | 15.70s | 691 | 44.0 tok/s |
| 最小生成树 | 12.17s | 651 | 53.5 tok/s |
| 拓扑排序 | 22.40s | 1023 | 45.7 tok/s |
| 最长公共子序列 | 12.00s | 631 | 52.6 tok/s |
| 编辑距离 | 23.02s | 1023 | 44.4 tok/s |
| 滑动窗口 | 18.78s | 1023 | 54.5 tok/s |
| 双指针 | 21.94s | 1023 | 46.6 tok/s |
| 动态规划 | 19.50s | 1023 | 52.5 tok/s |
| 贪心算法 | 23.71s | 1023 | 43.1 tok/s |

================================================================================
[汇总]
- 总耗时: 556.94s (~9.3分钟)
- 总token数: 28197
- 平均速度: 50.6 tok/s
================================================================================
"""

import sys
import time
import json
import urllib.request
import urllib.error

API_URL = "http://localhost:11434/v1/chat/completions"
MAX_TOKENS = 1024

TESTS = [
    (
        "快速排序",
        "用Python实现快速排序，要求支持自定义比较函数，并添加详细注释说明时间复杂度和空间复杂度",
    ),
    (
        "线程安全",
        "解释什么是线程安全，用Python示例说明竞态条件和死锁问题，并提供解决方案",
    ),
    (
        "二分查找",
        "写一个通用的二分查找函数，支持查找第一个/最后一个匹配元素，处理边界情况",
    ),
    (
        "数据库索引",
        "解释B+树索引原理，对比哈希索引和全文索引的适用场景，分析索引失效情况",
    ),
    (
        "Python性能优化",
        "详细分析Python代码性能瓶颈，介绍Cython、Numba、多进程等优化方案并给出示例",
    ),
    ("归并排序", "用Python实现归并排序，要求支持链表排序，分析递归和迭代的实现差异"),
    (
        "HTTP/HTTPS",
        "详细解释HTTP与HTTPS的区别，包括TLS握手过程、证书验证机制、中间人攻击防护",
    ),
    (
        "LRU缓存",
        "用Python实现线程安全的LRU缓存，使用OrderedDict和双向链表两种方法，分析时间复杂度",
    ),
    (
        "堆排序",
        "用Python实现堆排序，包括构建堆、调整堆的详细过程，分析不稳定排序的原因",
    ),
    (
        "Dijkstra算法",
        "用Python实现Dijkstra最短路径算法，支持优先队列优化，处理负权边情况",
    ),
    ("一致性哈希", "详细解释一致性哈希原理，如何解决节点新增和删除时的数据迁移问题"),
    ("令牌桶", "用Python实现令牌桶算法，对比漏桶算法，分析在限流场景下的应用"),
    ("阻塞队列", "用Python实现阻塞队列，对比普通队列，分析生产者消费者模式的应用"),
    ("红黑树", "用Python实现红黑树，包含插入、删除、查找操作，分析AVL树的区别"),
    ("B+树", "解释B+树与B树的区别，分析数据库索引为什么使用B+树而非B树"),
    ("A*算法", "用Python实现A*寻路算法，对比Dijkstra，分析启发式函数设计"),
    ("KMP算法", "详细解释KMP字符串匹配算法原理，给出Python实现，分析next数组计算"),
    ("布隆过滤器", "解释布隆过滤器的原理和用途，分析误判率和最优参数选择"),
    ("跳表", "解释跳表的数据结构，用Python实现跳表，分析与红黑树的性能差异"),
    (
        "并查集",
        "用Python实现并查集，分析路径压缩和按秩合并的优化，分析在连通性问题中的应用",
    ),
    ("线段树", "用Python实现线段树，支持区间查询和单点更新，分析在区间问题中的应用"),
    ("字典树", "用Python实现字典树（前缀树），分析在字符串查找中的优势"),
    ("最小生成树", "用Python实现Prim和Kruskal算法，对比分析时间复杂度"),
    ("拓扑排序", "解释拓扑排序的原理，用Python实现Kahn算法和DFS算法，分析应用场景"),
    ("最长公共子序列", "用Python实现LCS动态规划算法，分析空间优化方法"),
    (
        "编辑距离",
        "解释编辑距离算法，用Python实现Levenshtein距离，分析在拼写检查中的应用",
    ),
    ("滑动窗口", "用Python实现滑动窗口算法，分析在子串问题中的应用"),
    ("双指针", "用Python实现双指针技巧，分析在链表和数组问题中的应用"),
    ("动态规划", "详解动态规划思想，对比递归和迭代实现，分析状态转移方程设计"),
    ("贪心算法", "通过实例详解贪心算法，证明正确性，分析与动态规划的区别"),
]


def count_tokens(text):
    """用tokenizer计算token数"""
    import sys

    sys.path.insert(0, "/opt/exllamav3")
    from exllamav3 import Config, Tokenizer

    c = Config.from_directory("/opt/gguf/Qwen3-14B-exl3")
    t = Tokenizer.from_config(c)
    ids = t.encode(text)
    return len(ids) if hasattr(ids, "__len__") else 1


def call_api(prompt, max_tokens=MAX_TOKENS):
    """调用 API"""
    data = {
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "stream": False,
    }

    req = urllib.request.Request(
        API_URL,
        data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    start_time = time.time()
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            result = json.loads(response.read().decode("utf-8"))
            elapsed = time.time() - start_time

            if result.get("choices") and len(result["choices"]) > 0:
                content = result["choices"][0].get("message", {}).get("content", "")
                # 直接用 API 返回的 usage
                usage = result.get("usage", {})
                tokens = usage.get("completion_tokens", 0)
                return elapsed, tokens, content
            return elapsed, 0, ""
    except Exception as e:
        return time.time() - start_time, 0, f"Error: {e}"


def main():
    print("=" * 60)
    print("API 性能测试")
    print("=" * 60)
    print(f"地址: {API_URL}")
    print(f"Max tokens: {MAX_TOKENS}")
    print("=" * 60)
    print()

    total_time = 0
    total_tokens = 0

    for name, prompt in TESTS:
        print(f"[{name}]...", end=" ", flush=True)

        elapsed, tokens, _ = call_api(prompt)
        speed = tokens / elapsed if elapsed > 0 else 0

        print(f"{elapsed:.2f}s, {tokens} tokens, {speed:.1f} tok/s")

        total_time += elapsed
        total_tokens += tokens

    print()
    print("=" * 60)
    avg_speed = total_tokens / total_time if total_time > 0 else 0
    print(f"总耗时: {total_time:.2f}s")
    print(f"总token数: {total_tokens}")
    print(f"平均速度: {avg_speed:.1f} tok/s")
    print("=" * 60)


if __name__ == "__main__":
    main()
