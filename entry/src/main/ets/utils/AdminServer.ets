/**
 * AdminServer / AdminClient — 托盘进程本地管理通道
 *
 * 问题背景：主进程在窗口关闭（隐藏）状态下通过 startAbility 向 TrayAbility
 * 发送 action 命令会被系统后台启动限制拦截，命令无法送达，造成
 * 「托盘菜单显示已关闭但服务实际在跑、偏好未写入」的假象。
 *
 * 方案：TrayAbility 进程常驻一个仅监听 127.0.0.1:18766 的迷你 HTTP 服务，
 * 主进程（任何状态）通过本地 HTTP POST 下发命令，不再依赖 startAbility。
 *
 * 协议：
 * - POST /admin  body {"cmd":"..."}，header X-Admin-Token 必须匹配 → {"ok":...}
 * - GET  /status                                    → {"mcp":bool}
 *
 * 认证：启动时 initToken(filesDir) 生成/读取随机 token（应用沙箱内
 * admin_token 文件，本应用两进程共享、第三方进程不可见），POST /admin
 * 必须 header 携带——裸 TCP 客户端（本机任意进程）无 token 一律拒绝
 * （审计：无认证通道可抢先批准确认/关停服务）。
 */
import { socket } from '@kit.NetworkKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

type Conn = socket.TCPSocketConnection;

const TAG = 'AdminServer';

/** 托盘进程侧：命令回调（返回 JSON 响应体） */
export interface AdminHandler {
  onCommand(cmd: string): string;
}

export class AdminServer {

  private server: socket.TCPSocketServer | null = null;
  private readonly port: number;
  private readonly handler: AdminHandler;
  private running: boolean = false;
  /** 通道认证 token：托盘进程首次启动生成并落沙箱文件，本应用两进程共享 */
  private static token: string = '';

  constructor(port: number, handler: AdminHandler) {
    this.port = port;
    this.handler = handler;
  }

  /** 生成/读取通道 token（幂等：文件已存在直接读取） */
  static initToken(filesDir: string): void {
    const path: string = `${filesDir}/admin_token`;
    try {
      const existing: string = fs.readTextSync(path).trim();
      if (existing !== '') {
        AdminServer.token = existing;
        return;
      }
    } catch (_) {
    }
    try {
      const t: string = util.generateRandomUUID(true);
      const f = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(f.fd, t);
      fs.closeSync(f.fd);
      AdminServer.token = t;
      hilog.info(0x0000, TAG, 'admin token generated');
    } catch (e) {
      hilog.error(0x0000, TAG, 'admin token init failed: %{public}s', `${e}`);
    }
  }

  start(): void {
    if (this.running) { return; }
    try {
      this.server = socket.constructTCPSocketServerInstance();
      this.server.listen({ address: '127.0.0.1', port: this.port, family: 1 }).then(() => {
        hilog.info(0x0000, TAG, 'Admin channel listening on 127.0.0.1:%{public}d', this.port);
        this.server?.on('connect', (conn: Conn) => {
          this.handleClient(conn);
        });
        this.server?.on('error', (err: Error) => {
          hilog.error(0x0000, TAG, 'Admin server error: %{public}s', `${err}`);
        });
      }).catch((e: object) => {
        hilog.error(0x0000, TAG, 'Admin listen failed: %{public}s', `${e}`);
      });
      this.running = true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'Admin start failed: %{public}s', `${e}`);
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
      buffer += AdminServer.decode(info.message);
      if (buffer.length > 65536) { conn.close(); return; }
      const req: AdminRequest | null = AdminServer.parse(buffer);
      if (req === null) { return; }
      buffer = '';
      // 来源校验（安全审查 L-1：任意网页 {"cmd":"exit"} 杀托盘/停 MCP）
      if (req.origin !== '' || (req.host !== '' && req.host !== '127.0.0.1:18766' && req.host !== 'localhost:18766')) {
        conn.close().catch(() => {});
        return;
      }
      const body: string = this.route(req);
      const resp: string = 'HTTP/1.1 200 OK\r\n' +
        'Content-Type: application/json\r\n' +
        'Content-Length: ' + body.length + '\r\n' +
        'Connection: close\r\n\r\n' + body;
      // P2：close 必须等 send 完成——两者并发时 close 可抢先（尤其响应较大或
      // 系统繁忙时），客户端表现为 RemoteDisconnected（连续快请求下高频复现）
      conn.send({ data: AdminServer.encode(resp) }).then(() => {
        return conn.close();
      }).catch(() => {
        conn.close().catch(() => { });
      });
    });
    conn.on('close', () => {});
    conn.on('error', () => {});
  }

  private route(req: AdminRequest): string {
    if (req.method === 'GET' && req.path === '/status') {
      return this.handler.onCommand('status');
    }
    if (req.method === 'POST' && (req.path === '/admin' || req.path === '/')) {
      // 命令通道认证（token 存应用沙箱，第三方进程不可读）——无认证通道可
      // 抢先批准确认操作/关停服务（审计 P1）
      if (AdminServer.token === '' || req.token !== AdminServer.token) {
        hilog.error(0x0000, TAG, 'admin cmd rejected: bad token');
        return '{"ok":false,"error":"unauthorized"}';
      }
      return this.handler.onCommand(AdminServer.extractCmd(req.body));
    }
    return '{"ok":false,"error":"not found"}';
  }

  private static extractCmd(body: string): string {
    try {
      const obj: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const cmd: Object | undefined = obj['cmd'];
      if (typeof cmd === 'string') {
        return cmd as string;
      }
    } catch (_) {
    }
    return '';
  }

  /** 解析完整 HTTP 请求（请求行 + headers + body），未收完返回 null */
  private static parse(raw: string): AdminRequest | null {
    const headerEnd: number = raw.indexOf('\r\n\r\n');
    if (headerEnd < 0) { return null; }
    const lines: string[] = raw.substring(0, headerEnd).split('\r\n');
    const requestLine: string[] = lines[0].split(' ');
    if (requestLine.length < 2) { return null; }
    let contentLength: number = 0;
    let origin: string = '';
    let host: string = '';
    let token: string = '';
    for (let i = 1; i < lines.length; i++) {
      const kv: string[] = lines[i].split(':');
      const key: string = kv[0].trim().toLowerCase();
      if (kv.length === 2 && key === 'content-length') {
        const n: number = parseInt(kv[1].trim());
        if (!Number.isNaN(n)) { contentLength = n; }
      } else if (kv.length >= 2 && key === 'origin') {
        origin = lines[i].substring(lines[i].indexOf(':') + 1).trim();
      } else if (kv.length >= 2 && key === 'host') {
        host = lines[i].substring(lines[i].indexOf(':') + 1).trim();
      } else if (kv.length >= 2 && key === 'x-admin-token') {
        token = lines[i].substring(lines[i].indexOf(':') + 1).trim();
      }
    }
    const body: string = raw.substring(headerEnd + 4);
    if (body.length < contentLength) { return null; }
    return { method: requestLine[0], path: requestLine[1], body: body.substring(0, contentLength), origin: origin, host: host, token: token };
  }

  private static decode(data: ArrayBuffer): string {
    const bytes: Uint8Array = new Uint8Array(data);
    let out: string = '';
    for (let i = 0; i < bytes.length; i++) {
      out += String.fromCharCode(bytes[i]);
    }
    return out;
  }

  private static encode(text: string): ArrayBuffer {
    const bytes: Uint8Array = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) {
      bytes[i] = text.charCodeAt(i) & 0xFF;
    }
    return bytes.buffer;
  }
}

interface AdminRequest {
  method: string;
  path: string;
  body: string;
  origin: string;
  host: string;
  token: string;
}

/**
 * 主进程侧：向托盘进程管理通道发送命令。
 * 返回是否送达（false = 托盘进程未运行或不可达）。
 */
export class AdminClient {

  private static readonly URL: string = 'http://127.0.0.1:18766/admin';
  /** 通道 token（应用沙箱 admin_token 文件，与 AdminServer 共享）——
   *  setTokenDir 由宿主进程 onCreate 注入 filesDir 后懒加载读取 */
  private static tokenDir: string = '';
  private static tokenCache: string = '';
  private static tokenLoaded: boolean = false;

  static setTokenDir(filesDir: string): void {
    AdminClient.tokenDir = filesDir;
    AdminClient.tokenLoaded = false;
  }

  private static token(): string {
    if (!AdminClient.tokenLoaded) {
      try {
        AdminClient.tokenCache = fs.readTextSync(`${AdminClient.tokenDir}/admin_token`).trim();
      } catch (_) {
        AdminClient.tokenCache = '';
      }
      AdminClient.tokenLoaded = true;
    }
    return AdminClient.tokenCache;
  }

  private static request(cmd: string, wantBody: boolean): Promise<string> {
    return new Promise<string>((resolve) => {
      try {
        const client: http.HttpRequest = http.createHttp();
        client.request(AdminClient.URL, {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'X-Admin-Token': AdminClient.token(),
          } as Record<string, string>,
          extraData: JSON.stringify({ 'cmd': cmd }) as string,
          connectTimeout: 1500,
          readTimeout: 1500,
        }).then((resp: http.HttpResponse) => {
          client.destroy();
          if (resp.responseCode !== 200) { resolve(''); return; }
          resolve(wantBody ? `${resp.result ?? ''}` : 'OK');
        }).catch(() => {
          client.destroy();
          resolve('');
        });
      } catch (_) {
        resolve('');
      }
    });
  }

  static post(cmd: string): Promise<boolean> {
    return AdminClient.request(cmd, false).then((r: string) => r !== '');
  }

  /** post 且返回响应体文本（{"ok":..,"result":".."} 原文；失败返回空串）——
   *  确认回传等需要把真实结果透出给 UI 的调用用这个（post 只给布尔会谎报） */
  static postText(cmd: string): Promise<string> {
    return AdminClient.request(cmd, true);
  }
}
