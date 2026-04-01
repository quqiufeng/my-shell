#!/usr/bin/env python3
import requests
import time
import sys

PORT = sys.argv[1] if len(sys.argv) > 1 else "11434"
MODEL = sys.argv[2] if len(sys.argv) > 2 else "qwen2.5-coder"
URL = f"http://localhost:{PORT}/v1/chat/completions"
MAX_TOKENS = int(sys.argv[3]) if len(sys.argv) > 3 else 100

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
    (
        "一致性哈希",
        "用Python实现一致性哈希算法，包括虚拟节点机制，分析负载均衡和数据迁移策略",
    ),
    ("令牌桶", "用Python实现令牌桶限流器，支持突发流量和预热功能，提供线程安全实现"),
    ("阻塞队列", "用Python实现阻塞队列，使用条件变量和信号量，支持有界和无界队列"),
    ("红黑树", "用Python实现红黑树，包括插入、删除、旋转操作，保持红黑树性质"),
    ("B+树", "用Python实现B+树索引结构，支持范围查询和顺序遍历，分析磁盘IO优化"),
    (
        "A*算法",
        "用Python实现A*寻路算法，使用优先队列和启发式函数，处理障碍物和不同地形代价",
    ),
    ("KMP算法", "用Python实现KMP字符串匹配算法，构建next数组，分析时间复杂度优势"),
    ("布隆过滤器", "用Python实现布隆过滤器，支持动态扩容，分析误判率和内存使用权衡"),
    ("跳表", "用Python实现跳表数据结构，支持插入、删除、查找操作，分析概率平衡机制"),
    ("并查集", "用Python实现并查集，包括路径压缩和按秩合并优化，应用连通分量检测"),
    ("线段树", "用Python实现线段树，支持区间查询和懒更新，应用于区间最值和区间求和"),
    ("字典树", "用Python实现Trie树，支持前缀匹配和自动补全，分析空间优化策略"),
    ("最小生成树", "用Python实现Prim和Kruskal两种算法，对比时间复杂度和适用场景"),
    ("拓扑排序", "用Python实现拓扑排序，检测环存在，应用于任务调度和依赖解析"),
    ("最长公共子序列", "用Python实现LCS算法，使用动态规划和空间优化，回溯输出具体序列"),
    (
        "编辑距离",
        "用Python实现Levenshtein距离算法，支持替换、插入、删除操作，应用于拼写检查",
    ),
    ("滑动窗口", "用Python实现滑动窗口算法模板，解决子串问题和定长窗口统计问题"),
    ("双指针", "用Python实现双指针技巧，包括快慢指针和对撞指针，解决链表和数组问题"),
    ("动态规划", "用Python实现0/1背包和完全背包问题，分析状态转移方程和滚动数组优化"),
    ("贪心算法", "用Python实现活动选择问题和哈夫曼编码，分析贪心策略的正确性证明"),
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
