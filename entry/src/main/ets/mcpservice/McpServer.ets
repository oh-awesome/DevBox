/**
 * MCP Server — HTTP/JSON-RPC 服务器（Streamable HTTP 模式）
 */
import { socket } from '@kit.NetworkKit';
import { McpToolRegistry, McpToolDef, McpToolResult } from './McpToolRegistry';

type Conn = socket.TCPSocketConnection;

interface HttpParsed {
  method: string;
  path: string;
  body: string;
  origin: string;      // 请求头 Origin（浏览器指纹——MCP 客户端不发）
  host: string;        // 请求头 Host（DNS rebinding 防线）
  contentType: string; // 请求头 Content-Type
}

export class McpServer {
  private server: socket.TCPSocketServer | null = null;
  private port: number;
  private running: boolean = false;

  constructor(port: number) {
    this.port = port;
  }

  isRunning(): boolean {
    return this.running;
  }

  start(): void {
    if (this.running) { return; }
    try {
      this.server = socket.constructTCPSocketServerInstance();
      this.server.listen({ address: '127.0.0.1', port: this.port, family: 1 }).then(() => {
        console.info(`[MCP] HTTP Server listening on http://127.0.0.1:${this.port}/mcp`);
        this.server?.on('connect', (conn: Conn) => {
          this.handleClient(conn);
        });
        this.server?.on('error', (err: Error) => {
          console.error(`[MCP] Server error: ${err}`);
        });
      }).catch((e: object) => {
        console.error(`[MCP] Listen failed: ${e}`);
      });
      this.running = true;
    } catch (e) {
      console.error(`[MCP] Start failed: ${e}`);
    }
  }

  stop(): void {
    if (this.server !== null) {
      this.server.close().catch(() => {});
      this.server = null;
    }
    this.running = false;
  }

  private handleClient(conn: Conn): void {
    let buffer: string = '';

    conn.on('message', (info: socket.SocketMessageInfo) => {
      buffer += McpServer.decode(info.message);
      if (buffer.length > 65536) { conn.close(); return; } // 64KB 上限防 DoS
      // HTTP 请求以 \r\n\r\n 结尾（headers），body 跟在后面
      // 尝试解析完整的 HTTP 请求
      const parsed: HttpParsed | null = McpServer.parseHttpRequest(buffer);
      if (parsed !== null) {
        buffer = '';
        this.routeRequest(conn, parsed);
      }
    });

    conn.on('close', () => {});
    conn.on('error', () => {});
  }

  /** 解析 HTTP 请求（headers + body），返回 null 如果还没收完 */
  private static parseHttpRequest(raw: string): HttpParsed | null {
    const headerEnd: number = raw.indexOf('\r\n\r\n');
    if (headerEnd < 0) { return null; }

    const headerBlock: string = raw.substring(0, headerEnd);
    const bodyStart: number = headerEnd + 4;
    const bodyCandidate: string = raw.substring(bodyStart);

    // 解析请求行
    const lines: string[] = headerBlock.split('\r\n');
    const requestLine: string[] = lines[0].split(' ');
    if (requestLine.length < 2) { return null; }
    const method: string = requestLine[0];
    const path: string = requestLine[1];

    // 解析 Content-Length / Origin / Host / Content-Type
    let contentLength: number = 0;
    let origin: string = '';
    let host: string = '';
    let contentType: string = '';
    for (let i = 1; i < lines.length; i++) {
      const lower: string = lines[i].toLowerCase();
      if (lower.startsWith('content-length:')) {
        contentLength = parseInt(lower.substring(15).trim()) || 0;
      } else if (lower.startsWith('origin:')) {
        origin = lines[i].substring(7).trim();
      } else if (lower.startsWith('host:')) {
        host = lines[i].substring(5).trim();
      } else if (lower.startsWith('content-type:')) {
        contentType = lines[i].substring(13).trim();
      }
    }

    // 审计 F-P0-5：body 长度按字节比较——UTF-16 code units ≠ 字节。
    // 含中文时 .length < contentLength 恒真（1 code unit = 3 UTF-8 字节）
    // → 请求永久挂起。改用保守估计：UTF-16 长度 × 3 ≥ contentLength
    // 即认为可能收完（中文 3 倍展开是最大比，ASCII 1 倍；宁可多试一次
    // JSON parse 也不挂死）
    if (bodyCandidate.length * 3 < contentLength) { return null; }
    const body: string = bodyCandidate.substring(0, contentLength);

    const result: HttpParsed = { method: method, path: path, body: body, origin: origin, host: host, contentType: contentType };
    return result;
  }

  /** HTTP 路由 */
  private routeRequest(conn: Conn, req: HttpParsed): void {
    // ── 来源校验（安全审查 H-1：任意网页 fetch → pip_install 任意源 = RCE）──
    // ①带 Origin 头的一律拒绝：MCP 客户端（非浏览器）从不发 Origin；浏览器（含 file://
    //   本地页 Origin=null、普通网页）必发——此前 ACAO:null 恰好放行这两类最危险来源
    if (req.origin !== '') {
      this.sendJson(conn, 403, JSON.stringify({ error: 'origin rejected' }));
      return;
    }
    // ②Host 必须是本机环回（防 DNS rebinding：域名解析到 127.0.0.1 后 Host 仍是域名）
    if (req.host !== '' && req.host !== '127.0.0.1:18765' && req.host !== 'localhost:18765') {
      this.sendJson(conn, 403, JSON.stringify({ error: 'host rejected' }));
      return;
    }
    // CORS 预检：不再放行（真实 MCP 客户端不做预检；预检只来自浏览器）
    if (req.method === 'OPTIONS') {
      this.sendHttp(conn, 204, '');
      return;
    }
    // ③tools/call 通道强制 JSON Content-Type（封死 text/plain simple-request 跨域路径）
    if (req.method === 'POST' && (req.path === '/mcp' || req.path === '/' || req.path === '/messages')
      && req.contentType.indexOf('application/json') < 0) {
      this.sendJson(conn, 415, JSON.stringify({ error: 'content-type must be application/json' }));
      return;
    }

    // 健康检查
    if (req.method === 'GET' && (req.path === '/' || req.path === '/health')) {
      this.sendJson(conn, 200, JSON.stringify({ status: 'ok', server: 'DevBox MCP', version: '2.0' }));
      return;
    }

    // MCP 主端点（POST /mcp 或 POST /）
    if (req.method === 'POST' && (req.path === '/mcp' || req.path === '/' || req.path === '/messages')) {
      this.handleRpc(conn, req.body);
      return;
    }

    // SSE 端点（GET /sse）— 旧版 MCP Client
    if (req.method === 'GET' && req.path === '/sse') {
      this.handleSse(conn);
      return;
    }

    // 404
    this.sendJson(conn, 404, JSON.stringify({ error: 'Not Found' }));
  }

  /** 处理 JSON-RPC 请求 */
  private handleRpc(conn: Conn, body: string): void {
    let method: string = '';
    let idStr: string = '';
    let toolName: string = '';
    let toolArgs: Record<string, string> = {};

    try {
      const req = JSON.parse(body) as Record<string, Object>;
      method = (req['method'] as string) ?? '';
      const rawId: Object | undefined = req['id'];
      idStr = rawId !== undefined ? JSON.stringify(rawId) : '';
      const params: Record<string, Object> = (req['params'] as Record<string, Object>) ?? {};

      if (method === 'initialize') {
        const info: Record<string, Object> = {};
        info['name'] = 'DevBox';
        info['version'] = '2.0';
        const caps: Record<string, Object> = {};
        const toolsCap: Record<string, Object> = {};
        caps['tools'] = toolsCap;
        const result: Record<string, Object> = {};
        result['protocolVersion'] = '2024-11-05';
        result['capabilities'] = caps;
        result['serverInfo'] = info;
        this.sendRpcResult(conn, idStr, result);
        return;
      }

      if (method === 'notifications/initialized') {
        // 无需响应（notification）
        this.sendHttp(conn, 202, '');
        return;
      }

      if (method === 'tools/list') {
        const tools: Record<string, Object>[] = [];
        const defs: McpToolDef[] = McpToolRegistry.tools();
        for (let i = 0; i < defs.length; i++) {
          const t: Record<string, Object> = {};
          t['name'] = defs[i].name;
          t['description'] = defs[i].description;
          // 真实参数 Schema：AI 客户端依赖它生成调用参数
          const props: Record<string, Object> = {};
          const required: string[] = [];
          for (let j = 0; j < defs[i].params.length; j++) {
            const p = defs[i].params[j];
            const prop: Record<string, Object> = {};
            prop['type'] = 'string';
            prop['description'] = p.desc;
            props[p.name] = prop;
            if (p.required) { required.push(p.name); }
          }
          const schema: Record<string, Object> = {};
          schema['type'] = 'object';
          schema['properties'] = props;
          if (required.length > 0) { schema['required'] = required; }
          t['inputSchema'] = schema;
          tools.push(t);
        }
        const result: Record<string, Object> = {};
        result['tools'] = tools;
        this.sendRpcResult(conn, idStr, result);
        return;
      }

      if (method === 'tools/call') {
        toolName = (params['name'] as string) ?? '';
        const rawArgs: Record<string, Object> = (params['arguments'] as Record<string, Object>) ?? {};
        const keys: string[] = Object.keys(rawArgs);
        for (let i = 0; i < keys.length; i++) {
          toolArgs[keys[i]] = `${rawArgs[keys[i]]}`;
        }

        const result: McpToolResult = McpToolRegistry.call(toolName, toolArgs);
        const item: Record<string, Object> = {};
        item['type'] = 'text';
        item['text'] = result.content;
        const contentArr: Record<string, Object>[] = [item];
        const callResult: Record<string, Object> = {};
        callResult['content'] = contentArr;
        callResult['isError'] = result.isError;
        this.sendRpcResult(conn, idStr, callResult);
        return;
      }

      if (method === 'ping') {
        this.sendRpcResult(conn, idStr, {});
        return;
      }

      const errObj: Record<string, Object> = {};
      errObj['code'] = -32601;
      errObj['message'] = `Method not found: ${method}`;
      this.sendRpcError(conn, idStr, errObj);
    } catch (e) {
      const errObj: Record<string, Object> = {};
      errObj['code'] = -32700;
      errObj['message'] = `Parse error: ${e}`;
      this.sendRpcError(conn, idStr, errObj);
    }
  }

  /** SSE 流（保持连接，用于旧版 MCP Client） */
  private handleSse(conn: Conn): void {
    const headers: string[] = [
      'Content-Type: text/event-stream',
      'Cache-Control: no-cache',
      'Connection: keep-alive',
    ];
    // 发送 SSE endpoint 事件
    const sseData: string = `event: endpoint\ndata: /mcp\n\n`;
    this.sendHttp(conn, 200, sseData, headers, false);
    // 保持连接（不关闭，客户端会持续读取）
  }

  /** 发送 JSON-RPC 成功响应 */
  private sendRpcResult(conn: Conn, idStr: string, result: Record<string, Object>): void {
    const resp: Record<string, Object> = {};
    resp['jsonrpc'] = '2.0';
    if (idStr !== '') { resp['id'] = JSON.parse(idStr); }
    resp['result'] = result;
    this.sendJson(conn, 200, JSON.stringify(resp));
  }

  /** 发送 JSON-RPC 错误响应 */
  private sendRpcError(conn: Conn, idStr: string, error: Record<string, Object>): void {
    const resp: Record<string, Object> = {};
    resp['jsonrpc'] = '2.0';
    if (idStr !== '') { resp['id'] = JSON.parse(idStr); }
    resp['error'] = error;
    this.sendJson(conn, 200, JSON.stringify(resp));
  }

  /** 发送 HTTP JSON 响应 */
  private sendJson(conn: Conn, status: number, body: string): void {
    this.sendHttp(conn, status, body, [
      'Content-Type: application/json',
    ]);
  }

  /** 发送 HTTP 响应 */
  private sendHttp(conn: Conn, status: number, body: string, extraHeaders: string[] = [], close: boolean = true): void {
    const statusText: string = status === 200 ? 'OK' : status === 202 ? 'Accepted' : status === 204 ? 'No Content' : status === 404 ? 'Not Found' : 'Error';
    let response: string = `HTTP/1.1 ${status} ${statusText}\r\n`;
    for (let i = 0; i < extraHeaders.length; i++) {
      response += extraHeaders[i] + '\r\n';
    }
    response += `Content-Length: ${McpServer.byteLength(body)}\r\n`;
    if (close) { response += 'Connection: close\r\n'; }
    response += '\r\n';
    response += body;

    try {
      conn.send({ data: response });
      if (close && status !== 200) {
        setTimeout(() => { conn.close(); }, 100);
      } else if (close && status === 200) {
        setTimeout(() => { conn.close(); }, 500);
      }
    } catch (_) {
    }
  }

  private static byteLength(str: string): number {
    let len: number = 0;
    for (let i = 0; i < str.length; i++) {
      const code: number = str.charCodeAt(i);
      if (code < 0x80) { len += 1; }
      else if (code < 0x800) { len += 2; }
      else { len += 3; }
    }
    return len;
  }

  private static decode(data: ArrayBuffer): string {
    const bytes: Uint8Array = new Uint8Array(data);
    let out: string = '';
    for (let i = 0; i < bytes.length; i++) {
      out += String.fromCharCode(bytes[i]);
    }
    return out;
  }
}
