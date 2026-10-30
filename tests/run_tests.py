"""Compile production Foundation code and exercise it against a local HTTP fixture."""
import json
import pathlib
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        status, body, content_type = 200, b'{"ok":true}', 'application/json'
        if self.path == '/empty':
            status, body = 204, b''
        elif self.path == '/failure':
            status, body = 500, b'{"error":"fixture failure"}'
        elif self.path == '/empty-failure':
            status, body = 403, b''
        elif self.path == '/text':
            body, content_type = b'plain response', 'text/plain'
        self.reply(status, body, content_type)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        if self.headers.get('Content-Type') == 'application/json':
            value = json.loads(body)
        else:
            value = parse_qs(body.decode('utf-8'))
        self.reply(200, json.dumps(value).encode(), 'application/json')

    do_PUT = do_POST
    do_PATCH = do_POST
    do_DELETE = do_POST

    def reply(self, status, body, content_type):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    root = pathlib.Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='projectx-tests-') as temporary:
        executable = pathlib.Path(temporary) / 'core-tests'
        subprocess.run([
            'xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation',
            '-Icommon', '-Idaemon', 'common/HttpRequest.m', 'common/ProfileManager.m',
            'daemon/RequestValidation.m', 'tests/CoreTests.m', '-o', str(executable),
        ], cwd=root, check=True)
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            subprocess.run([str(executable), f'http://127.0.0.1:{server.server_port}',
                            str(pathlib.Path(temporary) / 'profiles')], check=True, timeout=60)
        finally:
            server.shutdown()
            server.server_close()
            worker.join()


if __name__ == '__main__':
    main()
