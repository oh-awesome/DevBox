/**
 * NpmCatalogService —— npm 包适配目录（npm-packages.json.gz，48K 包两类）
 * 类型：adapted（@ohos-ports 适配）/ compatible（无需适配）
 * 缓存协议与 PyCatalogService 一致（磁盘 + CDN .gz 拉取）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { DiscoveryService } from './DiscoveryService';
import { GunzipUtil } from './GunzipUtil';



import fs from '@ohos.file.fs';




const TAG = 'NpmCatalog';
const CACHE_FILE = 'npm_catalog_cache.json';

export interface NpmCatalogEntry {
  name: string;
  type: string;       // 'adapted' | 'compatible'
  version: string;
  scope: string;      // 如 '@ohos-ports'
}

export class NpmCatalogService {
  /** 包名/版本合法字符（npm 生态含 @scope/name） */
  private static safeToken(t: string): boolean {
    return /^[A-Za-z0-9@][A-Za-z0-9@\/._+\-]*$/.test(t);
  }

  private static entries: NpmCatalogEntry[] = [];
  private static loaded: boolean = false;
  private static loading: boolean = false;
  private static filesDir: string = '';

  static ready(): boolean {
    return NpmCatalogService.loaded && NpmCatalogService.entries.length > 0;
  }

  static count(): number {
    return NpmCatalogService.entries.length;
  }

  static init(ctx: common.Context): void {
    if (NpmCatalogService.filesDir === '') {
      NpmCatalogService.filesDir = ctx.filesDir;
    }
  }


  /** 强制刷新（⟳ 联动：跳过 loaded 守卫重拉并落盘；loading 并发守卫保留） */
  static refresh(): void {
    if (NpmCatalogService.loading) { return; }
    NpmCatalogService.loading = true;
    NpmCatalogService.fetchRemote();
  }

  static ensure(): void {
    if (NpmCatalogService.loaded || NpmCatalogService.loading) { return; }
    NpmCatalogService.loading = true;
    if (NpmCatalogService.loadDisk()) {
      NpmCatalogService.loading = false;
      NpmCatalogService.fetchRemote();
      return;
    }
    NpmCatalogService.fetchRemote();
  }

  private static loadDisk(): boolean {
    if (NpmCatalogService.filesDir === '') { return false; }
    try {
      const path = `${NpmCatalogService.filesDir}/${CACHE_FILE}`;
      if (!fs.accessSync(path)) { return false; }
      const text = fs.readTextSync(path);
      NpmCatalogService.parse(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  private static fetchRemote(): void {
    const url = DiscoveryService.latest().resolveCatalogUrl('npm-packages.json', 'npm-packages.json.gz');
    const cachePath = `${NpmCatalogService.filesDir}/${CACHE_FILE}`;
    const tmpGz = `${NpmCatalogService.filesDir}/npm_catalog.tmp.gz`;

    GunzipUtil.downloadAndGunzip(url, tmpGz).then((text: string) => {
      NpmCatalogService.loading = false;
      if (text === '') { return; }
      NpmCatalogService.parse(text);
      try {
        const cf = fs.openSync(cachePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(cf.fd, text);
        fs.closeSync(cf.fd);
      } catch (_) {}
      hilog.info(0x0000, TAG, 'npm catalog loaded: %{public}d entries', NpmCatalogService.entries.length);
    });
  }

  private static parse(text: string): void {
    try {
      const json: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const arr: Object[] = (json['packages'] as Object[]) ?? [];
      const out: NpmCatalogEntry[] = [];
      for (let i = 0; i < arr.length; i++) {
        const p: Record<string, Object> = arr[i] as Record<string, Object>;
        if (p === undefined || p === null) { continue; }
        // 白名单同 PyCatalogService（安全审查 H-2：远程值进 npm install 命令）
        const nm: string = (p['name'] as string) ?? '';
        const vs: string = (p['version'] as string) ?? '';
        if (!NpmCatalogService.safeToken(nm) || !NpmCatalogService.safeToken(vs)) { continue; }
        out.push({
          name: nm,
          type: (p['type'] as string) ?? '',
          version: vs,
          scope: (p['scope'] as string) ?? '',
        });
      }
      NpmCatalogService.entries = out;
      NpmCatalogService.loaded = true;
      AppStorage.setOrCreate('npmcatalog_epoch', Date.now());
    } catch (_) {
    }
  }

  static search(keyword: string, limit: number = 50): NpmCatalogEntry[] {
    if (!NpmCatalogService.ready()) { return []; }
    const kw = keyword.toLowerCase().trim();
    const out: NpmCatalogEntry[] = [];
    for (let i = 0; i < NpmCatalogService.entries.length && out.length < limit; i++) {
      const e = NpmCatalogService.entries[i];
      if (kw === '' || e.name.toLowerCase().indexOf(kw) >= 0) {
        out.push(e);
      }
    }
    return out;
  }

  static searchByType(keyword: string, type: string, limit: number = 50): NpmCatalogEntry[] {
    if (!NpmCatalogService.ready()) { return []; }
    const kw = keyword.toLowerCase().trim();
    const out: NpmCatalogEntry[] = [];
    for (let i = 0; i < NpmCatalogService.entries.length && out.length < limit; i++) {
      const e = NpmCatalogService.entries[i];
      if (e.type !== type) { continue; }
      if (kw === '' || e.name.toLowerCase().indexOf(kw) >= 0) {
        out.push(e);
      }
    }
    return out;
  }
}
