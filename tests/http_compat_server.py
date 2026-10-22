#!/usr/bin/env python3
"""Local-only fixture for tests/test_http_compat.lua."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import gzip
import json
import sys
import zlib


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        if self.path == "/binary":
            data = b"\x00\xffA\n"
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.path == "/comma,a,b":
            data = b"comma URL preserved"
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.path == "/echo":
            data = json.dumps({"method": "GET", "body": ""}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/gzip")
            self.end_headers()
            return
        if self.path == "/truncated":
            self.send_response(200)
            self.send_header("Content-Length", "100")
            self.end_headers()
            self.wfile.write(b"short body")
            self.wfile.flush()
            self.close_connection = True
            return
        if self.path == "/gzip":
            data = gzip.compress("gzip 测试正文".encode("utf-8"))
            self.send_response(200)
            self.send_header("Content-Encoding", "gzip")
        elif self.path == "/deflate":
            data = zlib.compress(b"deflate payload")
            self.send_response(200)
            self.send_header("Content-Encoding", "deflate")
        else:
            data = b"missing"
            self.send_response(404)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path == "/redirect-post-302":
            self.send_response(302)
            self.send_header("Location", "/echo")
            self.end_headers()
            return
        if self.path == "/redirect-post-307":
            self.send_response(307)
            self.send_header("Location", "/echo")
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        result = {"method": "POST", "body": body.decode("utf-8"), "header": self.headers.get("X-Test")}
        data = json.dumps(result, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


port = int(sys.argv[1]) if len(sys.argv) > 1 else 18763
HTTPServer(("127.0.0.1", port), Handler).serve_forever()
