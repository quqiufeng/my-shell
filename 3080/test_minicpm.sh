#!/bin/bash
# MiniCPM-o 2.6 性能测试脚本

URL="http://localhost:11434/v1/chat/completions"
MODEL="minicpm-o"

prompts=(
"用Python实现一个红黑树数据结构"
"用Python实现一个B+树"
"用Python实现一个A*寻路算法"
"用Python实现一个布隆过滤器"
"用Python实现一个LRU缓存淘汰算法"
"用Python实现一个线程安全的阻塞队列"
"用Python实现一个无锁CAS队列"
"用Python实现一个支持亿级数据排序的外排序算法"
"用Python实现一个协程调度器"
"用Python实现一个STL风格的vector容器"
"用Python实现一个堆排序算法"
"用Python实现一个Dijkstra最短路径算法"
"用Python实现一个限流令牌桶算法"
"用Python实现一个一致性哈希算法"
"用Python实现一个跳表SkipList"
"用Python实现一个字典树Trie"
"用Python实现一个最小生成树Prim算法"
"用Python实现一个Tarjan强连通分量算法"
"用Python实现一个线段树"
"用Python实现一个并查集"
"用Python实现一个AC自动机"
"用Python实现一个KMP字符串匹配"
"用Python实现一个Manacher最长回文子串"
"用Python实现一个珂朵莉树"
"用Python实现一个图的三色着色算法"
"用Python实现一个拓扑排序算法"
"用Python实现一个菲波那契堆"
"用Python实现一个二项堆"
"用Python实现一个霍夫曼编码压缩"
"用Python实现一个BP神经网络"
)

total_speed=0
count=0

for i in "${!prompts[@]}"; do
    prompt="${prompts[$i]}"
    result=$(python3 -c "
import requests, time, json
url = '$URL'
data = {
    'model': '$MODEL',
    'messages': [{'role': 'user', 'content': '$prompt'}],
    'max_tokens': 500,
    'stream': False
}
t = time.time()
r = requests.post(url, json=data, timeout=120).json()
elapsed = time.time() - t
if 'usage' in r:
    gen_tokens = r['usage']['completion_tokens']
    speed = gen_tokens / elapsed
    print(f'{gen_tokens}|{elapsed:.2f}|{speed:.1f}')
else:
    print('ERROR')
")
    
    if [[ $result != "ERROR" ]]; then
        tokens=$(echo $result | cut -d'|' -f1)
        time=$(echo $result | cut -d'|' -f2)
        speed=$(echo $result | cut -d'|' -f3)
        echo "$((i+1)). $prompt | $tokens tokens | ${time}s | ${speed} tokens/s"
        total_speed=$(echo "$total_speed + $speed" | bc)
        count=$((count+1))
    else
        echo "$((i+1)). ERROR"
    fi
done

if [ $count -gt 0 ]; then
    avg=$(echo "scale=1; $total_speed / $count" | bc)
    echo ""
    echo "平均速度: $avg tokens/s"
fi
