"""
AsyncWeb 框架测试
"""

import pytest
import asyncio
import sys
import os

# 添加父目录到路径
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from async_web import AsyncApp, Request, Response, json, html
from async_web.router import Router
from async_web.middleware import (
    Middleware,
    MiddlewareManager,
    CORSMiddleware,
    LoggingMiddleware,
    RateLimitMiddleware,
)


# ===== Request Tests =====


class TestRequest:
    """Request类测试"""

    def test_parse_simple_get(self):
        """测试解析简单GET请求"""
        raw_request = b"GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n"

        request = Request.parse(raw_request, ("127.0.0.1", 8080))

        assert request.method == "GET"
        assert request.path == "/hello"
        assert request.headers["host"] == "localhost"

    def test_parse_post_with_body(self):
        """测试解析带请求体的POST请求"""
        raw_request = (
            b"POST /api/data HTTP/1.1\r\n"
            b"Host: localhost\r\n"
            b"Content-Type: application/json\r\n"
            b"Content-Length: 13\r\n\r\n"
            b'{"key": "value"}'
        )

        request = Request.parse(raw_request, ("127.0.0.1", 8080))

        assert request.method == "POST"
        assert request.path == "/api/data"
        assert request.json == {"key": "value"}

    def test_parse_query_string(self):
        """测试解析URL查询参数"""
        raw_request = b"GET /search?q=test&page=1 HTTP/1.1\r\nHost: localhost\r\n\r\n"

        request = Request.parse(raw_request, ("127.0.0.1", 8080))

        assert request.path == "/search"
        assert request.query["q"] == "test"
        assert request.query["page"] == "1"

    def test_get_param(self):
        """测试获取请求参数"""
        raw_request = b"GET /test?name=john&age=25 HTTP/1.1\r\nHost: localhost\r\n\r\n"

        request = Request.parse(raw_request)

        assert request.get("name") == "john"
        assert request.get("age") == "25"
        assert request.get("nonexistent", "default") == "default"

    def test_remote_addr(self):
        """测试获取客户端IP"""
        raw_request = b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"

        request = Request.parse(raw_request, ("192.168.1.1", 12345))

        assert request.remote_addr == "192.168.1.1"


# ===== Response Tests =====


class TestResponse:
    """Response类测试"""

    def test_create_basic_response(self):
        """测试创建基本响应"""
        response = Response(status=200, body="Hello")

        assert response.status == 200
        assert response.body == "Hello"

    def test_json_response(self):
        """测试JSON响应"""
        response = json({"message": "success", "data": [1, 2, 3]})

        assert response.status == 200
        assert response.content_type == "application/json"
        assert '"message": "success"' in response.body

    def test_html_response(self):
        """测试HTML响应"""
        response = html("<h1>Hello World</h1>")

        assert response.content_type == "text/html; charset=utf-8"
        assert "<h1>Hello World</h1>" in response.body

    def test_set_cookie(self):
        """测试设置Cookie"""
        response = Response(body="OK")
        response.set_cookie("session", "abc123", expires=3600)

        assert "session=abc123" in response._cookies["session"]

    def test_redirect(self):
        """测试重定向"""
        response = Response(body="")
        response.redirect("/new-location", status=301)

        assert response.status == 301
        assert response.headers["Location"] == "/new-location"

    def test_to_bytes(self):
        """测试响应转字节"""
        response = Response(status=200, body="Hello")

        response_bytes = response.to_bytes()

        assert b"HTTP/1.1 200 OK" in response_bytes
        assert b"Hello" in response_bytes


# ===== Router Tests =====


class TestRouter:
    """Router类测试"""

    def test_add_simple_route(self):
        """测试添加简单路由"""

        async def handler(request):
            return Response(body="OK")

        router = Router()
        route = router.add("/hello", handler)

        assert route.path == "/hello"
        assert "GET" in route.methods

    def test_match_exact_path(self):
        """测试精确路径匹配"""

        async def handler(request):
            return Response(body="OK")

        router = Router()
        router.add("/hello", handler)

        matched = router.match("/hello", "GET")

        assert matched is not None

    def test_match_path_with_params(self):
        """测试带参数的路径匹配"""

        async def handler(request):
            return Response(body="OK")

        router = Router()
        router.add("/user/<id>", handler)

        matched = router.match("/user/123", "GET")

        assert matched is not None

    def test_match_wrong_method(self):
        """测试HTTP方法不匹配"""

        async def handler(request):
            return Response(body="OK")

        router = Router()
        router.add("/hello", handler, methods=["POST"])

        matched = router.match("/hello", "GET")

        assert matched is None

    def test_match_not_found(self):
        """测试路径未找到"""
        router = Router()

        matched = router.match("/nonexistent", "GET")

        assert matched is None


# ===== Middleware Tests =====


class TestMiddlewareManager:
    """MiddlewareManager类测试"""

    def test_add_function_middleware(self):
        """测试添加函数中间件"""

        async def my_middleware(request, handler):
            return await handler(request)

        manager = MiddlewareManager()
        manager.add(my_middleware)

        assert len(manager.get_middlewares()) == 1

    def test_wrap_no_middleware(self):
        """测试没有中间件时的包装"""

        async def handler(request):
            return Response(body="OK")

        manager = MiddlewareManager()
        wrapped = manager.wrap(handler)

        assert wrapped is handler

    def test_middleware_chain(self):
        """测试中间件链执行"""
        call_order = []

        async def middleware1(request, handler):
            call_order.append(1)
            response = await handler(request)
            call_order.append(4)
            return response

        async def middleware2(request, handler):
            call_order.append(2)
            response = await handler(request)
            call_order.append(3)
            return response

        async def handler(request):
            return Response(body="OK")

        manager = MiddlewareManager()
        manager.add(middleware1)
        manager.add(middleware2)

        wrapped = manager.wrap(handler)

        # 执行请求
        asyncio.run(wrapped(Request()))

        # 验证执行顺序: 洋葱模型
        assert call_order == [1, 2, 3, 4]


class TestCORSMiddleware:
    """CORS中间件测试"""

    def test_cors_simple_request(self):
        """测试简单请求的CORS"""
        middleware = CORSMiddleware(origins=["*"])

        async def handler(request):
            return Response(body="OK")

        request = Request()
        request.method = "GET"

        response = asyncio.run(middleware.process(request, handler))

        assert "Access-Control-Allow-Origin" in response.headers

    def test_cors_preflight_request(self):
        """测试预检请求的CORS"""
        middleware = CORSMiddleware(origins=["http://example.com"])

        async def handler(request):
            return Response(body="OK")

        request = Request()
        request.method = "OPTIONS"
        request.headers["Origin"] = "http://example.com"

        response = asyncio.run(middleware.process(request, handler))

        assert "Access-Control-Allow-Methods" in response.headers


class TestRateLimitMiddleware:
    """限流中间件测试"""

    def test_rate_limit_allowed(self):
        """测试允许的请求"""
        middleware = RateLimitMiddleware(max_requests=2, window=60)

        async def handler(request):
            return Response(body="OK")

        request = Request()
        request.headers["Host"] = "localhost"

        # 第一次请求
        response1 = asyncio.run(middleware.process(request, handler))
        assert response1.status == 200

        # 第二次请求
        response2 = asyncio.run(middleware.process(request, handler))
        assert response2.status == 200

    def test_rate_limit_blocked(self):
        """测试被限流的请求"""
        middleware = RateLimitMiddleware(max_requests=1, window=60)

        async def handler(request):
            return Response(body="OK")

        request = Request()
        request.headers["Host"] = "localhost"

        # 第一次请求
        asyncio.run(middleware.process(request, handler))

        # 第二次请求应该被限流
        response = asyncio.run(middleware.process(request, handler))
        assert response.status == 429


# ===== Application Tests =====


class TestAsyncApp:
    """AsyncApp类测试"""

    def test_create_app(self):
        """测试创建应用"""
        app = AsyncApp()

        assert app.router is not None
        assert app.middleware_manager is not None

    def test_route_decorator(self):
        """测试路由装饰器"""
        app = AsyncApp()

        @app.route("/hello")
        async def hello(request):
            return Response(body="Hello!")

        routes = app.router.get_routes()

        assert len(routes) == 1
        assert routes[0].path == "/hello"

    def test_route_with_methods(self):
        """测试路由指定HTTP方法"""
        app = AsyncApp()

        @app.route("/api", methods=["GET", "POST"])
        async def api(request):
            return Response(body="OK")

        routes = app.router.get_routes()

        assert "GET" in routes[0].methods
        assert "POST" in routes[0].methods

    def test_handle_request_not_found(self):
        """测试404处理"""
        app = AsyncApp()

        request = Request()
        request.path = "/nonexistent"
        request.method = "GET"

        response = asyncio.run(app.handle_request(request))

        assert response.status == 404

    def test_handle_request_success(self):
        """测试成功处理请求"""
        app = AsyncApp()

        @app.route("/hello")
        async def hello(request):
            return Response(body="Hello!")

        request = Request()
        request.path = "/hello"
        request.method = "GET"

        response = asyncio.run(app.handle_request(request))

        assert response.status == 200
        assert "Hello!" in response.body


# ===== Integration Tests =====


class TestIntegration:
    """集成测试"""

    def test_full_request_flow(self):
        """测试完整请求流程"""
        app = AsyncApp()

        @app.route("/api/users/<id>")
        async def get_user(request):
            user_id = request.params.get("id")
            return json({"user_id": user_id, "name": "John"})

        # 模拟HTTP请求
        raw_request = (
            b"GET /api/users/123 HTTP/1.1\r\n"
            b"Host: localhost\r\n"
            b"Accept: application/json\r\n\r\n"
        )

        request = Request.parse(raw_request, ("127.0.0.1", 8080))
        response = asyncio.run(app.handle_request(request))

        assert response.status == 200
        assert "123" in response.body
        assert "John" in response.body

    def test_json_post_request(self):
        """测试JSON POST请求"""
        app = AsyncApp()

        @app.route("/api/create", methods=["POST"])
        async def create(request):
            data = request.json
            return json({"received": data}, status=201)

        raw_request = (
            b"POST /api/create HTTP/1.1\r\n"
            b"Host: localhost\r\n"
            b"Content-Type: application/json\r\n\r\n"
            b'{"name": "test"}'
        )

        request = Request.parse(raw_request)
        response = asyncio.run(app.handle_request(request))

        assert response.status == 201
        assert "test" in response.body


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
