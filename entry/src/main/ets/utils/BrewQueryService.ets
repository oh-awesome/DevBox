/**
 * BrewQueryService —— 设备侧 brew 真值查询（已安装/可升级/诊断）
 *
 * 命令统一密封环境（绝对路径+固定 PATH，DevTask shell 是 mksh 不读
 * .zshrc；无管道——退出码真实）：
 *   list --json=v2   → 已装包结构化（版本/安装时间/是否依赖引入/linked）
 *                      ⚠ OHOS fork 报 "needless argument: --json=v2" 不支持
 *                      → 页面侧 fallbackListPlain 裸名列式解析兜底
 *   outdated --json  → 可升级集合（同因不支持 → listOutdatedPlain 裸输出兜底）
 *   doctor           → 诊断原始输出（lite：不做结构化解析）
 * 解析防御：stdout 混入非 JSON 前导行时用 indexOf('[') 截取兜底。
 */
import { DevTask } from './DevTask';
import { BrewEnv } from './BrewEnv';
import { AnsiClean } from './AnsiClean';
import Logger from './Logger';

const TAG = 'BrewQuery';

export interface InstalledPackage {
  name: string;
  version: string;        // 已装版本
  installedOn: number;    // 安装时间（epoch ms；0=未知）
  asDependency: boolean;  // 作为依赖被引入
  linked: boolean;
}

export interface OutdatedEntry {
  name: string;
  installedVersion: string;
  currentVersion: string;
}

export class BrewQueryService {

  /** 已装包列表：`brew list --versions --formulae`（每行 "name version"）
   *  fork 事实（2026-11-13 真机参数普查）：--json=v2 报 needless argument；
   *  --json 官方 help 原文 "Requires --versions ... and jq"——app 密封 PATH
   *  永远没有 jq，JSON 路线死透 → 文本解析是唯一正道。
   *  --versions 单用会扫 Caskroom 报 dir_initialize 错（stderr，已 2>/dev/null
   *  挡掉，exit 码可能非 0——只要 stdout 解析出包就按成功算）；
   *  组合 --formulae 限定公式段（真机实测单用无 Caskroom 报错）。
   *  无 TTY 时 fork 默认一包一行（help：-1 is the default when output is
   *  not to a terminal）——app 侧必然逐行。失败/未装返回 null（页面退裸名兜底） */
  static listInstalled(onDone: (pkgs: InstalledPackage[] | null) => void): void {
    const lines: string[] = [];
    DevTask.shell(`${BrewEnv.env()} '${BrewEnv.brew()}' list --versions --formulae 2>/dev/null`,
      (t: string, _e: boolean) => {
        const clean: string = AnsiClean.clean(t).trim();
        if (clean !== '') { lines.push(clean); }
      },
      (ok: boolean, detail: string) => {
        const out: InstalledPackage[] = [];
        for (let i = 0; i < lines.length; i++) {
          const line: string = lines[i];
          if (line.indexOf('==>') === 0) { continue; }
          const toks: string[] = line.split(/\s+/);
          const name: string = toks.length > 0 ? toks[0] : '';
          if (name === '' || !/^[A-Za-z0-9][A-Za-z0-9@._+-]*$/.test(name)) { continue; }
          const ver: string = toks.length > 1 ? toks[1] : '';
          out.push({ name: name, version: ver, installedOn: 0, asDependency: false, linked: false });
        }
        if (out.length > 0) { onDone(out); return; }
        if (ok) { onDone([]); return; }   // exit 0 + 无输出 = 0 个已装（合法空态）
        Logger.warn(TAG, `list --versions failed: ${detail}`);
        onDone(null);                     // 命令失败 → 页面退裸名兜底
      });
  }

  /** 可升级集合（--json 优先——fork 不认 --json=v2 的 =v2 后缀，outdated 的
   *  --json 走 Ruby 直出不依赖 jq；失败 → 裸 outdated 兜底） */
  static listOutdated(onDone: (entries: OutdatedEntry[] | null) => void): void {
    const lines: string[] = [];
    DevTask.shell(`${BrewEnv.env()} '${BrewEnv.brew()}' outdated --json 2>/dev/null`,
      (t: string, _e: boolean) => { lines.push(AnsiClean.clean(t)); },
      (ok: boolean, detail: string) => {
        const raw: string = lines.join('\n');
        // fork 实测（2026-11-13 真机）：outdated --json 输出
        // {"formulae": [...], "casks": [...]} 对象而非官方裸数组——取
        // formulae 数组解析（cask 不在管理范围）
        const start: number = raw.indexOf('{');
        if (ok && start >= 0) {
          try {
            const obj: Record<string, Object> = JSON.parse(raw.substring(start)) as Record<string, Object>;
            const arr: Object[] = (obj['formulae'] as Object[]) ?? [];
            const out: OutdatedEntry[] = [];
            for (let i = 0; i < arr.length; i++) {
              const f: Record<string, Object> = arr[i] as Record<string, Object>;
              const name: string = (f['name'] as string) ?? '';
              if (name === '') { continue; }
              const instVers: string[] = (f['installed_versions'] as string[]) ?? [];
              out.push({
                name: name,
                installedVersion: instVers.length > 0 ? instVers[0] : '',
                currentVersion: (f['current_version'] as string) ?? '',
              });
            }
            onDone(out);
            return;
          } catch (e) {
            Logger.warn(TAG, `outdated --json parse failed: ${e}`);
          }
        }
        Logger.warn(TAG, `outdated --json failed: ${detail} → 裸 outdated 兜底`);
        BrewQueryService.listOutdatedPlain(onDone);
      });
  }

  /** 兜底：裸 brew outdated（fork 无 JSON 模式；每行首 token=包名，版本留空） */
  private static listOutdatedPlain(onDone: (entries: OutdatedEntry[] | null) => void): void {
    const lines: string[] = [];
    DevTask.shell(`${BrewEnv.env()} '${BrewEnv.brew()}' outdated 2>/dev/null`,
      (t: string, _e: boolean) => {
        const clean: string = AnsiClean.clean(t).trim();
        if (clean !== '') { lines.push(clean); }
      },
      (ok: boolean, _detail: string) => {
        if (!ok) { onDone(null); return; }   // brew 本体不可用
        const out: OutdatedEntry[] = [];
        for (let i = 0; i < lines.length; i++) {
          const line: string = lines[i];
          if (line.indexOf('==>') === 0) { continue; }
          const toks: string[] = line.split(/\s+/);
          const name: string = toks.length > 0 ? toks[0] : '';
          if (name === '' || !/^[A-Za-z0-9][A-Za-z0-9@._+-]*$/.test(name)) { continue; }
          out.push({ name: name, installedVersion: '', currentVersion: '' });
        }
        onDone(out);
      });
  }

  /** 诊断原始输出（brew doctor；lite 模式不做结构化解析；剥 ANSI 色码） */
}
