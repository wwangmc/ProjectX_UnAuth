"""Compile production Foundation code and exercise it against a local HTTP fixture."""
import json
import os
import pathlib
import subprocess
import tempfile
import threading
import zipfile
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
        for name, entry in [('traversal.zip', '../escape'), ('absolute.zip', '/tmp/escape')]:
            with zipfile.ZipFile(pathlib.Path(temporary) / name, 'w') as archive:
                archive.writestr(entry, 'bad')
        with zipfile.ZipFile(pathlib.Path(temporary) / 'symlink.zip', 'w') as archive:
            entry = zipfile.ZipInfo('link')
            entry.create_system = 3
            entry.external_attr = 0o120777 << 16
            archive.writestr(entry, '/tmp/outside')
        with zipfile.ZipFile(pathlib.Path(temporary) / 'duplicate.zip', 'w') as archive:
            archive.writestr('file', 'first')
            archive.writestr('file', 'second')
        (pathlib.Path(temporary) / 'corrupt.zip').write_bytes(b'bad zip data')
        executable = pathlib.Path(temporary) / 'core-tests'
        subprocess.run([
            'xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation',
            '-Icommon', '-Idaemon', '-Imodel', '-larchive', 'common/HttpRequest.m', 'common/ProfileManager.m',
            'common/PXConfiguration.m', 'common/PXArchive.m', 'common/PXContainerFiles.m', 'common/PXURLCommand.m',
            'model/PhoneInfo.m', 'daemon/RequestValidation.m', 'tests/FeatureTests.m', 'tests/CoreTests.m', '-o', str(executable),
        ], cwd=root, check=True)
        sdk_executable = pathlib.Path(temporary) / 'sdk-tests'
        subprocess.run([
            'xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation',
            '-Ihooks', '-Imodel', '-Icommon', 'hooks/PXSDKCompatibility.m', 'hooks/PXSDKEarlyLoad.m',
            'common/PXConfiguration.m', 'model/PhoneInfo.m', 'tests/SDKTests.m',
            '-o', str(sdk_executable),
        ], cwd=root, check=True)
        subprocess.run([str(sdk_executable)], check=True, timeout=30)
        subprocess.run([str(sdk_executable), '--bad-signatures'], check=True, timeout=30)
        abi_executable = pathlib.Path(temporary) / 'sdk-abi-tests'
        subprocess.run([
            'xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation',
            '-Ihooks', '-Imodel', '-Icommon', 'hooks/PXSDKCompatibility.m', 'hooks/PXSDKEarlyLoad.m',
            'common/PXConfiguration.m', 'model/PhoneInfo.m', 'tests/SDKABITests.m',
            '-o', str(abi_executable),
        ], cwd=root, check=True)
        subprocess.run([str(abi_executable)], check=True, timeout=30)
        late_image = pathlib.Path(temporary) / 'sdk-late.dylib'
        native_hook = os.environ.get('PROJECTX_TEST_HOOK_LIBRARY')
        native_flags = ['-DPX_SDK_NATIVE_HOOKS', native_hook, '-lc++'] if native_hook else []
        subprocess.run([
            'xcrun', 'clang', '-fobjc-arc', '-dynamiclib', '-framework', 'Foundation',
            'tests/SDKLateImage.m', '-o', str(late_image),
        ], cwd=root, check=True)
        loader_executable = pathlib.Path(temporary) / 'sdk-loader-tests'
        subprocess.run([
            'xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation',
            '-Ihooks', '-Imodel', '-Icommon', 'hooks/PXSDKCompatibility.m', 'hooks/PXSDKEarlyLoad.m',
            'hooks/SDKCompatibilityHooks.m', 'common/PXConfiguration.m',
            'model/PhoneInfo.m', 'tests/SDKLoaderTests.m', *native_flags, '-o', str(loader_executable),
        ], cwd=root, check=True)
        subprocess.run([str(loader_executable), str(late_image)], check=True, timeout=30)
        subprocess.run([str(loader_executable), str(late_image), '--original-init'], check=True, timeout=30)
        if native_hook:
            subprocess.run([str(loader_executable), str(late_image)], check=True, timeout=30,
                           env={**os.environ, 'PXSDK_TEST_DISABLE_EARLY': '1'})
            inner_image = pathlib.Path(temporary) / 'sdk-inner.dylib'
            subprocess.run([
                'xcrun', 'clang', '-fobjc-arc', '-dynamiclib', '-framework', 'Foundation',
                'tests/SDKInnerImage.m', '-o', str(inner_image),
            ], cwd=root, check=True)
            subprocess.run([str(loader_executable), str(late_image), '--threaded-load'], check=True, timeout=30,
                           env={**os.environ, 'PXSDK_TEST_NESTED_IMAGE': str(inner_image)})
            subprocess.run([str(loader_executable), str(late_image)], check=True, timeout=30,
                           env={**os.environ, 'PXSDK_TEST_DELAY_EARLY': '1'})
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
