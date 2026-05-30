#!/usr/bin/env python3
"""
Ollama Tool Call Proxy
Converts markdown-wrapped JSON tool calls to standard OpenAI format
"""

import json
import re
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

OLLAMA_URL = "http://localhost:11434"
PROXY_PORT = 11436

class ProxyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        # Forward to Ollama
        req = urllib.request.Request(
            f"{OLLAMA_URL}{self.path}",
            data=body,
            headers={k: v for k, v in self.headers.items()},
            method='POST'
        )
        
        try:
            with urllib.request.urlopen(req) as resp:
                response_body = resp.read()
                
                # Only process chat completions
                if '/v1/chat/completions' in self.path:
                    response_body = self.fix_tool_calls(response_body)
                
                self.send_response(resp.status)
                for header, value in resp.headers.items():
                    if header.lower() not in ('transfer-encoding', 'content-length'):
                        self.send_header(header, value)
                self.send_header('Content-Length', len(response_body))
                self.end_headers()
                self.wfile.write(response_body)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()
            self.wfile.write(e.read())
    
    def fix_tool_calls(self, response_body):
        try:
            data = json.loads(response_body)
            
            if 'choices' in data:
                for choice in data['choices']:
                    if 'message' in choice and 'content' in choice['message']:
                        content = choice['message']['content']
                        
                        # Extract JSON from markdown code blocks
                        json_match = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', content, re.DOTALL)
                        if json_match:
                            try:
                                tool_json = json.loads(json_match.group(1))
                                
                                # Convert to standard tool_calls format
                                if 'name' in tool_json and 'arguments' in tool_json:
                                    choice['message']['tool_calls'] = [{
                                        "id": "call_" + str(hash(json.dumps(tool_json)))[:10],
                                        "type": "function",
                                        "function": {
                                            "name": tool_json['name'],
                                            "arguments": json.dumps(tool_json['arguments'])
                                        }
                                    }]
                                    choice['message']['content'] = None
                                    choice['finish_reason'] = 'tool_calls'
                            except json.JSONDecodeError:
                                pass
                        else:
                            # Try plain JSON
                            try:
                                tool_json = json.loads(content.strip())
                                if 'name' in tool_json and 'arguments' in tool_json:
                                    choice['message']['tool_calls'] = [{
                                        "id": "call_" + str(hash(json.dumps(tool_json)))[:10],
                                        "type": "function",
                                        "function": {
                                            "name": tool_json['name'],
                                            "arguments": json.dumps(tool_json['arguments'])
                                        }
                                    }]
                                    choice['message']['content'] = None
                                    choice['finish_reason'] = 'tool_calls'
                            except (json.JSONDecodeError, ValueError):
                                pass
            
            return json.dumps(data).encode('utf-8')
        except (json.JSONDecodeError, Exception):
            return response_body
    
    def do_GET(self):
        req = urllib.request.Request(f"{OLLAMA_URL}{self.path}", headers={k: v for k, v in self.headers.items()})
        with urllib.request.urlopen(req) as resp:
            self.send_response(resp.status)
            for header, value in resp.headers.items():
                if header.lower() not in ('transfer-encoding', 'content-length'):
                    self.send_header(header, value)
            body = resp.read()
            self.send_header('Content-Length', len(body))
            self.end_headers()
            self.wfile.write(body)
    
    def log_message(self, format, *args):
        pass  # Suppress logs

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', PROXY_PORT), ProxyHandler)
    print(f"Proxy running on http://0.0.0.0:{PROXY_PORT} -> {OLLAMA_URL}")
    server.serve_forever()
