/**
 * PyVersionsService —— Python 包多版本数据（python-packages.json.gz）
 * 数据源：制品仓 catalog/python-packages.json.gz（~6790 包 / ~9926 版本行）
 * 格式：每行 {"name": "numpy", "version": "1.26.4"}，同名多行 = 该包多个可选版本
 * 缓存：磁盘 + 内存（与 PyCatalogService 同协议）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { DiscoveryService } from './DiscoveryService';
import { GunzipUtil } from './GunzipUtil';


import fs from '@ohos.file.fs';




const TAG = 'PyVersions';
const CACHE_FILE = 'py_versions_cache.json';

export class PyVersionsService {
  private static versions: Record<string, string[]> = {}; // name → 版本列表（降序）
  private static loaded: boolean = false;
  private static loading: boolean = false;
  private static filesDir: string = '';

  static ready(): boolean { return PyVersionsService.loaded; }
  static count(): number { return Object.keys(PyVersionsService.versions).length; }

  static init(ctx: common.Context): void {
    if (PyVersionsService.filesDir === '') { PyVersionsService.filesDir = ctx.filesDir; }
  }


  /** 强制刷新（⟳ 联动：跳过 loaded 守卫重拉并落盘；loading 并发守卫保留） */
  static refresh(): void {
    if (PyVersionsService.loading) { return; }
    PyVersionsService.loading = true;
    PyVersionsService.fetch();
  }

  static ensure(): void {
    if (PyVersionsService.loaded || PyVersionsService.loading) { return; }
    PyVersionsService.loading = true;
    if (PyVersionsService.loadDisk()) {
      PyVersionsService.loading = false;
      return; // 磁盘缓存就绪，不强制刷新
    }
    PyVersionsService.fetch();
  }

  private static loadDisk(): boolean {
    if (PyVersionsService.filesDir === '') { return false; }
    try {
      const path = `${PyVersionsService.filesDir}/${CACHE_FILE}`;
      if (!fs.accessSync(path)) { return false; }
      const text = fs.readTextSync(path);
      PyVersionsService.parse(text);
      hilog.info(0x0000, TAG, 'disk cache: %{public}d packages', Object.keys(PyVersionsService.versions).length);
      return true;
    } catch (_) { return false; }
  }

  private static fetch(): void {
    const url = DiscoveryService.latest().resolveCatalogUrl('python-packages.json', 'python-packages.json.gz');
    const cachePath = `${PyVersionsService.filesDir}/${CACHE_FILE}`;
    const tmpGz = `${PyVersionsService.filesDir}/py_versions.tmp.gz`;

    GunzipUtil.downloadAndGunzip(url, tmpGz).then((text: string) => {
      PyVersionsService.loading = false;
      if (text === '') { hilog.error(0x0000, TAG, 'download failed'); return; }
      PyVersionsService.parse(text);
      try {
        const cf = fs.openSync(cachePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(cf.fd, text);
        fs.closeSync(cf.fd);
      } catch (_) {}
      hilog.info(0x0000, TAG, 'loaded: %{public}d packages', Object.keys(PyVersionsService.versions).length);
      AppStorage.setOrCreate('pyversions_epoch', Date.now());
    });
  }

  private static parse(text: string): void {
    try {
      const json: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const arr: Object[] = (json['packages'] as Object[]) ?? [];
      const map: Record<string, string[]> = {};
      for (let i = 0; i < arr.length; i++) {
        const p: Record<string, Object> = arr[i] as Record<string, Object>;
        if (p === undefined || p === null) { continue; }
        const name = (p['name'] as string) ?? '';
        const ver = (p['version'] as string) ?? '';
        if (name === '' || ver === '') { continue; }
        // H-2 安全白名单（审计 S-P2-3：name/ver 进 shell 拼 `${PIP_CMD}
        // install ${name}==${ver}`——恶意目录可注入。对照 PyCatalogService
        // /NpmCatalogService 已有同款校验，此处补齐）
        if (!/^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(name)
          || !/^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(ver)) { continue; }
        if (map[name] === undefined) { map[name] = []; }
        map[name].push(ver);
      }
      // 按版本号降序排序（确保 [0] = latest）
      const pkgNames: string[] = Object.keys(map);
      for (let i = 0; i < pkgNames.length; i++) {
        map[pkgNames[i]].sort((a: string, b: string): number => {
          return PyVersionsService.verCmpDesc(a, b);
        });
      }
      PyVersionsService.versions = map;
      PyVersionsService.loaded = true;
    } catch (_) {}
  }

  /** 语义版本降序比较（b > a 返回正数） */
  private static verCmpDesc(a: string, b: string): number {
    const pa: string[] = a.replace(/[^0-9.].*$/, '').split('.');
    const pb: string[] = b.replace(/[^0-9.].*$/, '').split('.');
    const n: number = Math.max(pa.length, pb.length);
    for (let i = 0; i < n; i++) {
      const x: number = Number(pa[i]) || 0;
      const y: number = Number(pb[i]) || 0;
      if (x !== y) { return y - x; }
    }
    return 0;
  }

  /** 获取某包的全部可选版本（降序，[0] = latest） */
  static versionsOf(name: string): string[] {
    return PyVersionsService.versions[name] ?? [];
  }

  /** 某包的 latest 版本号 */
  static latestOf(name: string): string {
    const list = PyVersionsService.versions[name];
    return list !== undefined && list.length > 0 ? list[0] : '';
  }
}
