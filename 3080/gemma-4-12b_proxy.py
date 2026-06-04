#!/usr/bin/env python3
"""
Gemma 4 thought 标签过滤代理
- 监听 11435
- 转发到 11434 (llama-server)
- 过滤响应中的 <|channel|>thought\n<channel|> 标签
- 支持流式和非流式响应
"""
import asyncio
import re
import sys
import aiohttp
from aiohttp import web

LLAMA_BACKEND = "http://localhost:11434"
PROXY_PORT = 11435
THOUGHT_END_MARKER = '<channel|>'

def strip_thought_content(text):
    """去掉 content 开头的 thought 块: 找到第一个 <channel|> 关闭符, 截取之后"""
    idx = text.find(THOUGHT_END_MARKER)
    if idx == -1:
        return text
    after = text[idx + len(THOUGHT_END_MARKER):]
    return after.lstrip('\n')

async def filter_stream(reader, writer):
    """过滤流式响应"""
    buffer = ""
    async for chunk in reader.iter_any():
        if not chunk:
            break
        text = chunk.decode('utf-8', errors='ignore')
        buffer += text
        # 按 SSE event 切分
        while '\n\n' in buffer:
            event, buffer = buffer.split('\n\n', 1)
            # 过滤 data: 行的 content
            lines = event.split('\n')
            new_lines = []
            for line in lines:
                if line.startswith('data: '):
                    payload = line[6:]
                    if payload == '[DONE]':
                        new_lines.append(line)
                        continue
                    try:
                        import json
                        d = json.loads(payload)
                        if 'choices' in d:
                            for choice in d['choices']:
                                delta = choice.get('delta', {})
                                if 'content' in delta and delta['content']:
                                    delta['content'] = strip_thought_content(delta['content'])
                        payload = json.dumps(d, ensure_ascii=False)
                        new_lines.append(f'data: {payload}')
                    except Exception:
                        new_lines.append(line)
                else:
                    new_lines.append(line)
            writer.write(('\n'.join(new_lines) + '\n\n').encode('utf-8'))
            await writer.drain()
    if buffer:
        writer.write(buffer.encode('utf-8'))
        await writer.drain()

async def proxy_handler(request):
    """代理所有请求"""
    target_url = f"{LLAMA_BACKEND}{request.path_qs}"
    headers = dict(request.headers)
    headers.pop('Host', None)

    body = await request.read()

    is_stream = False
    if request.content_type == 'application/json':
        try:
            import json
            d = json.loads(body)
            is_stream = d.get('stream', False)
        except Exception:
            pass

    async with aiohttp.ClientSession() as session:
        async with session.request(
            method=request.method,
            url=target_url,
            headers=headers,
            data=body,
        ) as resp:
            if is_stream and 'text/event-stream' in resp.headers.get('Content-Type', ''):
                resp_ct = resp.headers.get('Content-Type', 'text/event-stream')
                response = web.StreamResponse(
                    status=resp.status,
                    headers={'Content-Type': resp_ct},
                )
                await response.prepare(request)
                thought_buffer = ""
                thought_passed = False
                event_buffer = ""
                async for chunk in resp.content.iter_any():
                    if not chunk:
                        break
                    text = chunk.decode('utf-8', errors='ignore')
                    event_buffer += text
                    while '\n\n' in event_buffer:
                        event, event_buffer = event_buffer.split('\n\n', 1)
                        lines = event.split('\n')
                        new_lines = []
                        for line in lines:
                            if line.startswith('data: '):
                                payload = line[6:]
                                if payload == '[DONE]':
                                    new_lines.append(line)
                                    continue
                                try:
                                    import json
                                    d = json.loads(payload)
                                    if 'choices' in d:
                                        for choice in d['choices']:
                                            delta = choice.get('delta', {})
                                            if 'content' in delta and delta['content']:
                                                if not thought_passed:
                                                    thought_buffer += delta['content']
                                                    if THOUGHT_END_MARKER in thought_buffer:
                                                        idx = thought_buffer.find(THOUGHT_END_MARKER)
                                                        after = thought_buffer[idx + len(THOUGHT_END_MARKER):]
                                                        if after:
                                                            delta['content'] = after.lstrip('\n')
                                                        else:
                                                            delta['content'] = ''
                                                        thought_passed = True
                                                        thought_buffer = ""
                                                    else:
                                                        delta['content'] = ''
                                    payload = json.dumps(d, ensure_ascii=False)
                                    if d['choices'][0].get('delta', {}).get('content'):
                                        new_lines.append(f'data: {payload}')
                                except Exception:
                                    new_lines.append(line)
                            else:
                                new_lines.append(line)
                        if any(l.startswith('data: ') and l != 'data: [DONE]' for l in new_lines):
                            await response.write(('\n'.join(new_lines) + '\n\n').encode('utf-8'))
                if event_buffer:
                    await response.write(event_buffer.encode('utf-8'))
                await response.write_eof()
                return response
            else:
                body = await resp.read()
                ct = resp.headers.get('Content-Type', 'application/json')
                if 'application/json' in ct:
                    try:
                        import json
                        d = json.loads(body)
                        if 'choices' in d:
                            for choice in d['choices']:
                                msg = choice.get('message', {})
                                if 'content' in msg and msg['content']:
                                    msg['content'] = strip_thought_content(msg['content'])
                        body = json.dumps(d, ensure_ascii=False).encode('utf-8')
                    except Exception:
                        pass
                return web.Response(
                    body=body,
                    status=resp.status,
                    headers={'Content-Type': ct},
                )

async def main():
    app = web.Application(client_max_size=1024**3)
    app.router.add_route('*', '/{path:.*}', proxy_handler)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, '0.0.0.0', PROXY_PORT)
    await site.start()
    print(f"Gemma 4 proxy listening on 0.0.0.0:{PROXY_PORT}")
    print(f"Backend: {LLAMA_BACKEND}")
    print(f"Filter: strip thought block before <channel|> marker")
    while True:
        await asyncio.sleep(3600)

if __name__ == '__main__':
    asyncio.run(main())
