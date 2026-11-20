/**
 * DevEnvRegistry —— 本地安装账本（devenvPkgRegistry put/del）
 *
 * 协议对齐：PolarisTerm DEVENV-SPEC §8（GUI 任务协议 → 本地安装账本）
 * 装/卸成功落账 manifest 快照——离网可见/卸载有据
 * 两个应用共用同一账本文件路径（协议红线：不碰对方装的包）
 */

import fs from '@ohos.file.fs';

const HOME = '/storage/Users/currentUser';
const REGISTRY_PATH = `${HOME}/usr/local/.devbox/devenv-pkg-registry.json`;

export interface PkgRecord {
  name: string;           // 'python' | 'git' | ...
  ver: string;            // '3.12.15'
  installedBy: string;    // 'DevBox' | 'PolarisTerm'（区分装方，卸载红线 #5）
  installedAt: string;    // ISO 时间
  manifestSnapshot: Record<string, Object>;  // manifest 条目快照（离网可见）
}

export class DevEnvRegistry {

  /** 读取全部记录（fs 直读——原 execSync cat 在账本增长后受命令长度/转义
   *  影响，读坏返回 [] 曾连锁清空全部记录：rust 回滚 del 读坏 → write([])） */
  static all(): PkgRecord[] {
    try {
      const raw: string = fs.readTextSync(REGISTRY_PATH);
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const records = parsed['records'] as PkgRecord[];
      return records ?? [];
    } catch (_) {
      return [];
    }
  }

  /** 查找指定包的记录 */
  static find(name: string, ver: string): PkgRecord | null {
    const records = DevEnvRegistry.all();
    for (const r of records) {
      if (r.name === name && r.ver === ver) {
        return r;
      }
    }
    return null;
  }

  /** 查找指定包的所有版本记录 */
  static findAll(name: string): PkgRecord[] {
    const records = DevEnvRegistry.all();
    return records.filter(r => r.name === name);
  }

  /** 装成功落账（put） */
  static put(name: string, ver: string, manifestSnapshot: Record<string, Object>): void {
    const records = DevEnvRegistry.all();
    // 已有同包同版本 → 更新
    const existing = records.findIndex(r => r.name === name && r.ver === ver);
    const rec: PkgRecord = {
      name: name,
      ver: ver,
      installedBy: 'DevBox',
      installedAt: new Date().toISOString(),
      manifestSnapshot: manifestSnapshot,
    };
    if (existing >= 0) {
      records[existing] = rec;
    } else {
      records.push(rec);
    }
    DevEnvRegistry.write(records);
  }

  /** 版本切换 → 更新对应 name 的 record 的 ver（先读后写，保留对方记录） */
  static updateVer(name: string, ver: string): void {
    const records = DevEnvRegistry.all();
    for (let i = 0; i < records.length; i++) {
      if (records[i].name === name) {
        records[i].ver = ver;
        records[i].installedAt = new Date().toISOString();
      }
    }
    DevEnvRegistry.write(records);
  }

  /** 卸载成功删账（del） */
  static del(name: string, ver: string): void {
    const records = DevEnvRegistry.all();
    const filtered = records.filter(r => !(r.name === name && r.ver === ver));
    DevEnvRegistry.write(filtered);
  }

  /** 仅返回本应用安装的包（卸载红线 #5：不碰对方装的） */
  static mine(): PkgRecord[] {
    return DevEnvRegistry.all().filter(r => r.installedBy === 'DevBox');
  }

  /** 仅返回对方安装的包（只读，不可卸载） */
  static theirs(): PkgRecord[] {
    return DevEnvRegistry.all().filter(r => r.installedBy !== 'DevBox');
  }

  /** 落盘（fs 直写——原 shell heredoc 受 execSync 命令长度限制，账本含完整
   *  manifest 快照增长后写坏 JSON，读侧 JSON.parse 失败退化成空账本） */
  private static write(records: PkgRecord[]): void {
    const json = JSON.stringify({ records: records }, null, 2);
    try {
      fs.mkdir(`${HOME}/usr/local/.devbox`, true);
      const f = fs.openSync(REGISTRY_PATH, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, json);
      fs.closeSync(f);
    } catch (e) {
      console.error(`[DevEnvRegistry] write failed: ${e}`);
    }
  }
}
