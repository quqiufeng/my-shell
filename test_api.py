#!/usr/bin/env python3
"""
API 性能测试脚本
"""

import sys
import time
import json
import urllib.request
import urllib.error

API_URL = "http://localhost:11434/v1/chat/completions"
MAX_TOKENS = 1024

TESTS = [
    ("快速排序", "用Python实现快速排序，要求支持自定义比较函数，并添加详细注释说明时间复杂度和空间复杂度"),
    ("线程安全", "解释什么是线程安全，用Python示例说明竞态条件和死锁问题，并提供解决方案"),
    ("二分查找", "写一个通用的二分查找函数，支持查找第一个/最后一个匹配元素，处理边界情况"),
    ("数据库索引", "解释B+树索引原理，对比哈希索引和全文索引的适用场景，分析索引失效情况"),
    ("Python性能优化", "详细分析Python代码性能瓶颈，介绍Cython、Numba、多进程等优化方案并给出示例"),
    ("归并排序", "用Python实现归并排序，要求支持链表排序，分析递归和迭代的实现差异"),
    ("HTTP/HTTPS", "详细解释HTTP与HTTPS的区别，包括TLS握手过程、证书验证机制、中间人攻击防护"),
    ("LRU缓存", "用Python实现线程安全的LRU缓存，使用OrderedDict和双向链表两种方法，分析时间复杂度"),
    ("堆排序", "用Python实现堆排序，包括构建堆、调整堆的详细过程，分析不稳定排序的原因"),
    ("Dijkstra算法", "用Python实现Dijkstra最短路径算法，支持优先队列优化，处理负权边情况"),
    ("一致性哈希", "详细解释一致性哈希原理，如何解决节点新增和删除时的数据迁移问题"),
    ("令牌桶", "用Python实现令牌桶算法，对比漏桶算法，分析在限流场景下的应用"),
    ("阻塞队列", "用Python实现阻塞队列，对比普通队列，分析生产者消费者模式的应用"),
    ("红黑树", "用Python实现红黑树，包含插入、删除、查找操作，分析AVL树的区别"),
    ("B+树", "解释B+树与B树的区别，分析数据库索引为什么使用B+树而非B树"),
    ("A*算法", "用Python实现A*寻路算法，对比Dijkstra，分析启发式函数设计"),
    ("KMP算法", "详细解释KMP字符串匹配算法原理，给出Python实现，分析next数组计算"),
    ("布隆过滤器", "解释布隆过滤器的原理和用途，分析误判率和最优参数选择"),
    ("跳表", "解释跳表的数据结构，用Python实现跳表，分析与红黑树的性能差异"),
    ("并查集", "用Python实现并查集，分析路径压缩和按秩合并的优化，分析在连通性问题中的应用"),
    ("线段树", "用Python实现线段树，支持区间查询和单点更新，分析在区间问题中的应用"),
    ("字典树", "用Python实现字典树（前缀树），分析在字符串查找中的优势"),
    ("最小生成树", "用Python实现Prim和Kruskal算法，对比分析时间复杂度"),
    ("拓扑排序", "解释拓扑排序的原理，用Python实现Kahn算法和DFS算法，分析应用场景"),
    ("最长公共子序列", "用Python实现LCS动态规划算法，分析空间优化方法"),
    ("编辑距离", "解释编辑距离算法，用Python实现Levenshtein距离，分析在拼写检查中的应用"),
    ("滑动窗口", "用Python实现滑动窗口算法，分析在子串问题中的应用"),
    ("双指针", "用Python实现双指针技巧，分析在链表和数组问题中的应用"),
    ("动态规划", "详解动态规划思想，对比递归和迭代实现，分析状态转移方程设计"),
    ("贪心算法", "通过实例详解贪心算法，证明正确性，分析与动态规划的区别"),
]

def count_tokens(text):
    """用tokenizer计算token数"""
    import sys
    sys.path.insert(0, '/opt/exllamav3')
    from exllamav3 import Config, Tokenizer
    c = Config.from_directory("/opt/gguf/Qwen3-14B-exl3")
    t = Tokenizer.from_config(c)
    ids = t.encode(text)
    return len(ids) if hasattr(ids, '__len__') else 1

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