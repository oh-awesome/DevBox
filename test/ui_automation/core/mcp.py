"""
mcp.py —— DevBox MCP 客户端（HTTP JSON-RPC，fport 转发 18765）

功能层自动化首选通道：无坐标/无窗口/无图像依赖。
前置：应用 MCP 开关开启（TrayAbility 托盘进程监听 18765）+ hdc fport tcp:18765。
"""

import json
import subprocess
import time
import urllib.request

MCP_URL = 'http://127.0.0.1:18765/mcp'


def _fport() -> None:
    subprocess.run('hdc fport tcp:18765 tcp:18765', shell=True, capture_output=True)


class McpClient:
    def __init__(self):
        self._id = 0
        self.session = ''
        self.ready = False

    def _post(self, payload: dict) -> dict:
        req = urllib.request.Request(MCP_URL, data=json.dumps(payload).encode(),
                                     headers={'Content-Type': 'application/json',
                                              'Accept': 'application/json, text/event-stream'})
        if self.session:
            req.add_header('mcp-session-id', self.session)
        with urllib.request.urlopen(req, timeout=30) as resp:
            sid = resp.headers.get('mcp-session-id', '')
            if sid:
                self.session = sid
            body = resp.read().decode('utf-8', errors='replace')
        # SSE 或 JSON 响应兼容
        for line in body.split('\n'):
            line = line.strip()
            if line.startswith('data:'):
                line = line[5:].strip()
            if line.startswith('{'):
                return json.loads(line)
        raise RuntimeError(f'MCP 响应异常: {body[:120]}')

    def connect(self, retries: int = 3) -> bool:
        """initialize 握手（托盘进程必须已监听）"""
        _fport()
        for _ in range(retries):
            try:
                r = self._post({'jsonrpc': '2.0', 'id': 0, 'method': 'initialize',
                                'params': {'protocolVersion': '2025-03-26',
                                           'capabilities': {},
                                           'clientInfo': {'name': 'uitest', 'version': '1.0'}}})
                if 'result' in r:
                    self.ready = True
                    # notifications/initialized（协议礼节）
                    try:
                        self._post({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
                    except Exception:
                        pass
                    return True
            except Exception:
                time.sleep(1)
        return False

    def call(self, tool: str, args: dict | None = None, timeout: float = 120) -> dict:
        """工具调用；返回 result 或抛异常（isError 内容进 RuntimeError）"""
        self._id += 1
        r = self._post({'jsonrpc': '2.0', 'id': self._id, 'method': 'tools/call',
                        'params': {'name': tool, 'arguments': args or {}}}, )
        if 'error' in r:
            raise RuntimeError(f'MCP error: {r["error"]}')
        res = r.get('result', {})
        if res.get('isError'):
            texts = [c.get('text', '') for c in res.get('content', [])]
            raise RuntimeError(f'tool error: {"; ".join(texts)}')
        return res

    def result_text(self, tool: str, args: dict | None = None) -> str:
        res = self.call(tool, args)
        return '\n'.join(c.get('text', '') for c in res.get('content', []))

    def list_tools(self) -> list:
        """JSON-RPC tools/list（协议方法——注意不是 tools/call 的工具名）"""
        r = self._post({'jsonrpc': '2.0', 'id': 9001, 'method': 'tools/list'})
        return r.get('result', {}).get('tools', [])

    # ── 高层断言原语 ──────────────────────────────────────
    def list_runtimes(self) -> dict:
        return json.loads(self.result_text('list_runtimes'))

    def runtime_status(self, lang: str) -> str:
        return self.result_text('get_runtime_status', {'lang': lang})

    def task_progress(self) -> str:
        return self.result_text('get_task_progress')

    def env_info(self) -> str:
        return self.result_text('get_env_info')
