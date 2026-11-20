/**
 * BrewCatalogService —— 双固定源 brew 目录客户端（官方核心 + OHPCD 社区）
 *
 * 两源同构（发现服务 v2 对接指南）：都是 JWS 签名目录，payload 为明文
 * JSON 数组（signatures 段无需处理），同一份解析代码，仅 URL/缓存不同：
 *   官方源 core：discovery.core_packages_api（~12MB，磁盘缓存+ETag+24hTTL）
 *   社区源 ohpcd：discovery.tap_packages_api（平台上线后自动接管）
 *              → 种子兜底（https://ohpcd.atomgit.com/api/ohpcd-brew/
 *                 formula.jws.json，几十KB；两级读取——发现字段永远优先，
 *                 种子仅发现服务不可达时降级）
 *
 * 缓存策略（对齐官方 BrewUI）：磁盘缓存 + ETag 条件请求 + 24h TTL +
 * stale-while-revalidate（网络失败/404 保留旧数据，页面不空窗）。
 * 服务器实测（2026-11-12）：core 端点支持 ETag/304（刷新零流量）、
 * 不支持 gzip（首次全量 12MB）；社区端点上线前 404（优雅空态，每次
 * 启动重试，成功后落缓存）。
 *
 * JWS 双层解析：body["payload"] 是字符串需二次 parse。12MB 双层 parse
 * 为 V8 原生（<1s，仅 24h 一次的刷新回调里发生，不触碰 6s 看门狗）。
 */
import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import { common } from '@kit.AbilityKit';
import { DiscoveryService } from './DiscoveryService';
import Logger from './Logger';

const TAG = 'BrewCatalog';
const TTL_MS: number = 24 * 60 * 60 * 1000;

export interface BrewFormulaInfo {
  name: string;
  desc: string;
  version: string;   // versions.stable
  tap: string;       // harmonybrew/core | openharmonypcdeveloper/ohos
  homepage: string;
  license: string;
  executables: string[];      // 提供的命令（详情页"文件"区免 shell 数据源）
  dependencies: string[];
  caveats: string;            // 安装提示（可能多行）
  kegOnly: boolean;
  deprecated: boolean;
}

/** 单源目录仓（core/ohpcd 各一实例；行模型与解析同构） */
class CatalogStore {
  private tag: string = '';
  private cachePath: string = '';
  private metaPath: string = '';
  rows: BrewFormulaInfo[] = [];
  loaded: boolean = false;    // 磁盘缓存已读入
  fetching: boolean = false;  // 网络刷新在途
  private etag: string = '';
  private ts: number = 0;
  private filesDir: string = '';

  constructor(tag: string, cacheFile: string, metaFile: string) {
    this.tag = tag;
    this.cacheName = cacheFile;
    this.metaName = metaFile;
  }

  private cacheName: string = '';
  private metaName: string = '';

  bindDir(filesDir: string): void {
    this.filesDir = filesDir;
    this.cachePath = `${filesDir}/${this.cacheName}`;
    this.metaPath = `${filesDir}/${this.metaName}`;
  }

  readCache(): void {
    if (this.filesDir === '') { return; }
    try {
      if (!fs.accessSync(this.metaPath) || !fs.accessSync(this.cachePath)) { return; }
      const m: Record<string, Object> = JSON.parse(fs.readTextSync(this.metaPath)) as Record<string, Object>;
      this.etag = (m['etag'] as string) ?? '';
      this.ts = (m['ts'] as number) ?? 0;
      this.rows = CatalogStore.parse(fs.readTextSync(this.cachePath));
      this.loaded = true;
      Logger.info(TAG, `[${this.tag}] cache loaded: ${this.rows.length} formulas, etag=${this.etag}`);
    } catch (e) {
      Logger.warn(TAG, `[${this.tag}] readCache failed: ${e}`);
      this.rows = [];
      this.loaded = false;
    }
  }

  needRefresh(): boolean {
    if (!this.loaded || this.rows.length === 0) { return true; }
    return Date.now() - this.ts > TTL_MS;
  }

  refresh(url: string, onDone?: () => void): void {
    if (this.fetching || this.filesDir === '') {
      if (onDone !== undefined) { onDone(); }
      return;
    }
    this.fetching = true;
    try {
      const req = http.createHttp();
      const header: Record<string, string> = { 'Accept': 'application/json' };
      if (this.etag !== '') { header['If-None-Match'] = this.etag; }
      req.request(url, {
        method: http.RequestMethod.GET,
        header: header,
        connectTimeout: 8000,
        readTimeout: 90000,   // core 全量 12MB
        expectDataType: http.HttpDataType.STRING,
      }).then((data: http.HttpResponse) => {
        req.destroy();
        this.fetching = false;
        if (data.responseCode === 304) {
          this.ts = Date.now();
          this.writeMeta();
          Logger.info(TAG, `[${this.tag}] unchanged (304)`);
        } else if (data.responseCode === 200) {
          const raw: string = data.result as string;
          const rows: BrewFormulaInfo[] = CatalogStore.parse(raw);
          if (rows.length > 0) {
            this.rows = rows;
            this.loaded = true;
            const headers: Record<string, string> = (data.header as Record<string, string>) ?? {};
            const etag: string = (headers['etag'] ?? headers['ETag'] ?? '').trim();
            if (etag !== '') { this.etag = etag; }
            this.saveCache(raw);
          } else {
            Logger.warn(TAG, `[${this.tag}] parse produced 0 rows, keep stale data`);
          }
        } else {
          // 社区端点上线前 404——保留旧数据（通常为空），下次启动重试
          Logger.warn(TAG, `[${this.tag}] refresh http ${data.responseCode}, keep stale data`);
        }
        if (onDone !== undefined) { onDone(); }
      }).catch(() => {
        req.destroy();
        this.fetching = false;
        Logger.warn(TAG, `[${this.tag}] refresh failed（保留旧缓存）`);
        if (onDone !== undefined) { onDone(); }
      });
    } catch (e) {
      this.fetching = false;
      Logger.warn(TAG, `[${this.tag}] refresh throw: ${e}`);
      if (onDone !== undefined) { onDone(); }
    }
  }

  /** 双层解析：JWS 外层 → payload 字符串 → formula 数组 → 精简行模型 */
  static parse(raw: string): BrewFormulaInfo[] {
    try {
      const outer: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const payload: string = (outer['payload'] as string) ?? '';
      if (payload === '') { return []; }
      const arr: Object[] = JSON.parse(payload) as Object[];
      const out: BrewFormulaInfo[] = [];
      for (let i = 0; i < arr.length; i++) {
        const f: Record<string, Object> = arr[i] as Record<string, Object>;
        if (f === undefined || f === null) { continue; }
        const name: string = (f['name'] as string) ?? '';
        if (name === '') { continue; }
        const versions: Record<string, Object> = (f['versions'] as Record<string, Object>) ?? {};
        out.push({
          name: name,
          desc: (f['desc'] as string) ?? '',
          version: (versions['stable'] as string) ?? '',
          tap: (f['tap'] as string) ?? '',
          homepage: (f['homepage'] as string) ?? '',
          license: (f['license'] as string) ?? '',
          executables: (f['executables'] as string[]) ?? [],
          dependencies: (f['dependencies'] as string[]) ?? [],
          caveats: (f['caveats'] as string) ?? '',
          kegOnly: (f['keg_only'] as boolean) === true,
          deprecated: (f['deprecated'] as boolean) === true,
        });
      }
      return out;
    } catch (e) {
      Logger.warn(TAG, `parse failed: ${e}`);
      return [];
    }
  }

  private saveCache(raw: string): void {
    if (this.filesDir === '') { return; }
    try {
      CatalogStore.writeText(this.cachePath, raw);
      const meta: Record<string, Object> = {};
      meta['etag'] = this.etag;
      meta['ts'] = Date.now();
      meta['count'] = this.rows.length;
      CatalogStore.writeText(this.metaPath, JSON.stringify(meta));
      Logger.info(TAG, `[${this.tag}] cache saved: ${this.rows.length} formulas`);
    } catch (e) {
      Logger.warn(TAG, `[${this.tag}] saveCache failed: ${e}`);
    }
  }

  private writeMeta(): void {
    if (this.filesDir === '') { return; }
    try {
      const meta: Record<string, Object> = {};
      meta['etag'] = this.etag;
      meta['ts'] = this.ts;
      meta['count'] = this.rows.length;
      CatalogStore.writeText(this.metaPath, JSON.stringify(meta));
    } catch (_) {
    }
  }

  /** 仓库统一写文件模式：openSync(CREATE|TRUNC|WRITE_ONLY) + writeSync */
  private static writeText(path: string, text: string): void {
    const f = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    try {
      fs.writeSync(f.fd, text);
    } finally {
      fs.closeSync(f.fd);
    }
  }
}

export class BrewCatalogService {
  private static coreStore: CatalogStore = new CatalogStore('core', 'brew_core_catalog.json', 'brew_core_catalog_meta.json');
  private static tapStore: CatalogStore = new CatalogStore('ohpcd', 'brew_tap_catalog.json', 'brew_tap_catalog_meta.json');
  private static inited: boolean = false;

  /**
   * 装载双源磁盘缓存（秒显）+ TTL 过期则各自后台刷新。
   * onReady 多次回调（缓存读毕 + 各源刷新毕），页面每次重读即可。
   */
  static init(ctx: common.Context | null | undefined, onReady?: () => void): void {
    if (ctx === null || ctx === undefined) { return; }
    BrewCatalogService.coreStore.bindDir(ctx.filesDir);
    BrewCatalogService.tapStore.bindDir(ctx.filesDir);
    if (BrewCatalogService.inited) {
      if (onReady !== undefined) { onReady(); }
      // 已初始化过（页面重建）：仅对过期源做条件刷新
      BrewCatalogService.kickRefreshes(onReady);
      return;
    }
    BrewCatalogService.inited = true;
    BrewCatalogService.coreStore.readCache();
    BrewCatalogService.tapStore.readCache();
    if (onReady !== undefined) { onReady(); }
    BrewCatalogService.kickRefreshes(onReady);
  }

  private static kickRefreshes(onReady?: () => void): void {
    const cfg = DiscoveryService.latest();
    // 官方源：core_packages_api（发现服务下发，默认值兜底）
    if (BrewCatalogService.coreStore.needRefresh()) {
      BrewCatalogService.coreStore.refresh(cfg.brewCoreApi, onReady);
    }
    // 社区源：两级读取——发现字段 tap_packages_api 优先，种子降级兜底
    const tapUrl: string = cfg.tapPackagesApi !== '' ? cfg.tapPackagesApi : cfg.tapPackagesSeed;
    if (BrewCatalogService.tapStore.needRefresh()) {
      BrewCatalogService.tapStore.refresh(tapUrl, onReady);
    }
  }

  /** 官方核心全部 formula */
  static core(): BrewFormulaInfo[] {
    return BrewCatalogService.coreStore.rows;
  }

  /** OHPCD 社区源全部 formula（平台端点上线前为空） */
  static tap(): BrewFormulaInfo[] {
    return BrewCatalogService.tapStore.rows;
  }

  /** 官方源刷新在途（首拉 12MB 期间的加载态） */
  static coreFetching(): boolean {
    return BrewCatalogService.coreStore.fetching;
  }

  /** 社区源刷新在途 */
  static tapFetching(): boolean {
    return BrewCatalogService.tapStore.fetching;
  }
}
