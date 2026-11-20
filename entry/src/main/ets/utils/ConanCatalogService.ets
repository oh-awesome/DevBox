/**
 * ConanCatalogService —— Conan 包目录（conan-packages.json.gz，CDN 发现服务驱动）
 * 作用：无 conan/python 本体时也能浏览包目录（10125 包 name/version 对）。
 * 安装/下载仍走 PkgRepository 的 conan 代理链路；本目录仅负责"看"。
 * 缓存协议与 Py/NpmCatalogService 一致（磁盘 + CDN .gz 拉取）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { DiscoveryService, DiscoveryConfig } from './DiscoveryService';
import { GunzipUtil } from './GunzipUtil';



import fs from '@ohos.file.fs';



const TAG = 'ConanCatalog';
const CACHE_FILE = 'conan_catalog_cache.json';

export interface ConanCatalogEntry {
  name: string;
  version: string;
}

export class ConanCatalogService {
  private static entries: ConanCatalogEntry[] = [];
  private static loaded: boolean = false;
  private static loading: boolean = false;
  private static filesDir: string = '';

  static ready(): boolean {
    return ConanCatalogService.loaded && ConanCatalogService.entries.length > 0;
  }

  static count(): number {
    return ConanCatalogService.entries.length;
  }

  static init(ctx: common.Context): void {
    if (ConanCatalogService.filesDir === '') {
      ConanCatalogService.filesDir = ctx.filesDir;
    }
  }


  /** 强制刷新（⟳ 联动：跳过 loaded 守卫重拉并落盘；loading 并发守卫保留） */
  static refresh(): void {
    if (ConanCatalogService.loading) { return; }
    ConanCatalogService.loading = true;
    ConanCatalogService.fetchRemote();
  }

  static ensure(): void {
    if (ConanCatalogService.loaded || ConanCatalogService.loading) { return; }
    ConanCatalogService.loading = true;
    if (ConanCatalogService.loadDisk()) {
      ConanCatalogService.loading = false;
      ConanCatalogService.fetchRemote();
      return;
    }
    ConanCatalogService.fetchRemote();
  }

  /** 同步取目录（未就绪返回空数组并触发后台加载） */
  static all(): ConanCatalogEntry[] {
    if (!ConanCatalogService.loaded) { ConanCatalogService.ensure(); }
    return ConanCatalogService.entries;
  }

  static search(keyword: string, limit: number = 50): ConanCatalogEntry[] {
    if (!ConanCatalogService.ready()) { return []; }
    const kw: string = keyword.toLowerCase().trim();
    const out: ConanCatalogEntry[] = [];
    for (let i = 0; i < ConanCatalogService.entries.length && out.length < limit; i++) {
      const e: ConanCatalogEntry = ConanCatalogService.entries[i];
      if (kw === '' || e.name.toLowerCase().indexOf(kw) >= 0) {
        out.push(e);
      }
    }
    return out;
  }

  private static loadDisk(): boolean {
    if (ConanCatalogService.filesDir === '') { return false; }
    try {
      const path: string = `${ConanCatalogService.filesDir}/${CACHE_FILE}`;
      if (!fs.accessSync(path)) { return false; }
      ConanCatalogService.parse(fs.readTextSync(path));
      return true;
    } catch (_) {
      return false;
    }
  }

  private static fetchRemote(): void {
    const cachePath: string = `${ConanCatalogService.filesDir}/${CACHE_FILE}`;
    const tmpGz: string = `${ConanCatalogService.filesDir}/conan_catalog.tmp.gz`;

    // 2026-11-19：原直接读 DiscoveryService.latest()（同步）——冷启动窗口
    // resolve 在途时 cfg 为种子值、blobShas 空 → resolveCatalogUrl 返回空串
    // → 下载必败 → loaded 永不置位 → 目录死锁"加载中"且无重试（设备重置后
    // conan_search 永远空、conan_install_package 全部 Unknown component 实证）。
    // 改走 resolve() 回调：解析完成（或降级到缓存/种子）后再取 URL 拉目录
    const ctx: common.Context | null =
      (AppStorage.get<common.Context>('ui_context_ctx') as common.Context | undefined) ?? null;
    DiscoveryService.resolve(ctx, (cfg: DiscoveryConfig): void => {
      const url: string = cfg.resolveCatalogUrl('conan-packages.json', 'conan-packages.json.gz');
      GunzipUtil.downloadAndGunzip(url, tmpGz).then((text: string) => {
        ConanCatalogService.loading = false;
        if (text === '') { return; }
        ConanCatalogService.parse(text);
        try {
          const cf = fs.openSync(cachePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
          fs.writeSync(cf.fd, text);
          fs.closeSync(cf.fd);
        } catch (_) {
        }
        hilog.info(0x0000, TAG, 'conan catalog loaded: %{public}d entries', ConanCatalogService.entries.length);
      }).catch((_e: Object) => {
        ConanCatalogService.loading = false;
      });
    });
  }

  private static parse(text: string): void {
    try {
      const json: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const arr: Object[] = (json['packages'] as Object[]) ?? [];
      const out: ConanCatalogEntry[] = [];
      for (let i = 0; i < arr.length; i++) {
        const p: Record<string, Object> = arr[i] as Record<string, Object>;
        if (p === undefined || p === null) { continue; }
        const name: string = (p['name'] as string) ?? '';
        const ver: string = (p['version'] as string) ?? '';
        // H-2 安全白名单（审计 S-P2-4：name/ver 进 shell 拼接和 REST URL
        // 路径——恶意目录可注入。对照 PyCatalogService/NpmCatalogService
        // 已有同款校验，此处补齐）
        if (name !== '' && ver !== ''
          && /^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(name)
          && /^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(ver)) {
          out.push({ name: name, version: ver });
        }
      }
      if (out.length > 0) {
        ConanCatalogService.entries = out;
        ConanCatalogService.loaded = true;
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'parse failed: %{public}s', `${e}`);
    }
  }
}
