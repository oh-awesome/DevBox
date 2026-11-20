/**
 * BrewTapService —— OHPCD 社区 tap 装机器（唯一职责）
 *
 * 双固定源模型（2026-11-12 定案）：官方源（harmonybrew/core，brew 从
 * formula.jws.json API 直装）+ 社区源（harmony/ohos tap）。用户不可在
 * GUI 添加 tap——社区 tap 由本服务在 brew 装机后自动补上（发现服务下发
 * tap_name + tap_repo）。
 *
 * ⚠️ trust 机制（2026-11-13 终版·沙箱割据）：
 * - brew 7 写 trust store 有 stat.uid==euid 严格检查；/storage FUSE 卷
 *   stat uid 恒为 file_manager(20001006)，app 在 FUSE 路径上的写必被拒
 *   （卸载路径实测报 "Refusing to write insecure trust store"）
 * - hishell 给本 app 注入的 XDG_CONFIG_HOME 指向本 app 沙箱（属主=app
 *   uid）——BrewEnv 不再 unset XDG，brew 的 trust 落沙箱，读写都过
 * - 终端侧同理（其 XDG 指终端沙箱）——per-app 割据，双方自足
 * - 本服务预写 trust.json 双落点（沙箱主 + ~/.homebrew 兜底），免去
 *   tap 时的交互确认；终端用户首次在终端装社区包时由界面提示引导
 *   `brew trust harmony/ohos`（写终端沙箱，幂等）——页面 buildManagerTab
 *
 * 命令统一密封环境（BrewEnv：绝对路径 + 固定 PATH + XDG 钉死）；幂等：
 * ensureApplied() 可反复调用（已落成跳过，失败下次 refresh 重试）。
 */
import dataPreferences from '@ohos.data.preferences';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { DevTask } from './DevTask';
import { DiscoveryService } from './DiscoveryService';
import { BrewEnv } from './BrewEnv';
import Logger from './Logger';

const TAG = 'BrewTap';
const PREF_FILE = 'brew_taps_prefs';
const PREF_KEY_BUILTIN = 'builtin_tap_trusted3'; // 社区 tap 信任已落成（v3 键：沙箱双落点改造后强制重放一次预写）

export class BrewTapService {
  private static filesCtx: common.Context | null = null;
  private static loaded: boolean = false;
  private static builtinApplied: boolean = false;
  private static builtinApplying: boolean = false;

  /**
   * 初始化（加载信任落成标记）。preferences 读取异步——onLoaded 回调后
   * 状态就绪；已加载时同步回调。
   */
  static init(ctx: common.Context | null | undefined, onLoaded?: () => void): void {
    if (ctx === null || ctx === undefined) { return; }
    BrewTapService.filesCtx = ctx;
    if (BrewTapService.loaded) {
      if (onLoaded !== undefined) { onLoaded(); }
      return;
    }
    try {
      dataPreferences.getPreferences(ctx, PREF_FILE).then((pref: dataPreferences.Preferences) => {
        BrewTapService.builtinApplied = (pref.getSync(PREF_KEY_BUILTIN, false) as boolean) === true;
        BrewTapService.loaded = true;
        Logger.info(TAG, `init, builtinApplied=${BrewTapService.builtinApplied}`);
        if (onLoaded !== undefined) { onLoaded(); }
      }).catch(() => {
        BrewTapService.loaded = true;
        if (onLoaded !== undefined) { onLoaded(); }
      });
    } catch (_) {
      BrewTapService.loaded = true;
      if (onLoaded !== undefined) { onLoaded(); }
    }
  }

  /** brew 本体是否就位（fs 探测，应用侧可见 /storage 路径） */
  private static brewReady(): boolean {
    try { return fs.accessSync(BrewEnv.brew()); } catch (_) { return false; }
  }

  /**
   * 装机/启动后补社区 tap 并落信任（幂等，内部防并发）。页面 refresh()/
   * 装机成功回调调用即可，brew 未装时自动跳过。
   * 流程：brew tap（git clone，已存在报错不阻断）→ 直接写 trust.json
   * → 标记落成。信任落成失败（tap 命令外的意外）下次 refresh 重试。
   */
  static ensureApplied(): void {
    if (!BrewTapService.brewReady()) { return; }
    if (BrewTapService.builtinApplied || BrewTapService.builtinApplying) { return; }
    const cfg = DiscoveryService.latest();
    if (cfg.brewTapName === '' || cfg.brewTapRepo === '') { return; }
    BrewTapService.builtinApplying = true;
    Logger.info(TAG, `tapping community tap ${cfg.brewTapName}`);
    const lines: string[] = [];
    DevTask.shell(`${BrewEnv.env()} '${BrewEnv.brew()}' tap ${cfg.brewTapName} '${cfg.brewTapRepo}' 2>&1`,
      (t: string, _e: boolean) => { if (t.trim() !== '') { lines.push(t.trim()); } },
      (_ok: boolean, _detail: string) => {
        // tap 就位（新建或已存在均继续）→ app 侧直接落信任文件
        const trusted: boolean = BrewTapService.writeTrustFile(cfg.brewTapName, cfg.brewTapRepo);
        if (trusted) {
          BrewTapService.builtinApplied = true;
          BrewTapService.putBuiltinFlag();
        } else {
          Logger.warn(TAG, `trust file write failed（tap 输出：${lines.length > 0 ? lines[lines.length - 1] : '无'}），下次 refresh 重试`);
        }
        BrewTapService.builtinApplying = false;
      });
  }

  /**
   * 预写 trust.json（app 侧信任落成）。
   * 双落点（2026-11-13）：① 本 app 沙箱 ${filesDir}/homebrew/trust.json
   *   ——主落点，与 BrewEnv 不 unset XDG 后 brew 的解析链一致（沙箱属主
   *   =app uid，brew 自己的写路径也能过，预写只是免去 tap 时的交互确认）；
   * ② ~/.homebrew/trust.json——兜底（万一某环境未注入 XDG 时 brew 回落
   *   此处）。读路径均无 uid 检查（源码实证），两处都读得到。
   * 幂等：读现有合法 JSON 合并 taps（保留 formulae/casks/commands 键）；
   * 损坏/缺失 → 重建。taps 条目双形态：tap 名 + 远程 URL。
   */
  private static writeTrustFile(tapName: string, tapRepo: string): boolean {
    const targets: string[] = [];
    // 沙箱主落点：app filesDir（与注入的 XDG_CONFIG_HOME 同路径）
    if (BrewTapService.filesCtx !== null) {
      const sandbox: string = `${BrewTapService.filesCtx.filesDir}/homebrew`;
      if (targets.indexOf(sandbox) < 0) { targets.push(sandbox); }
    }
    // 兜底落点：~/.homebrew（无 XDG 注入时 brew 的默认全局位）
    const legacy: string = `${BrewEnv.home()}/.homebrew`;
    if (targets.indexOf(legacy) < 0) { targets.push(legacy); }
    let written: boolean = false;
    for (let i = 0; i < targets.length; i++) {
      if (BrewTapService.writeTrustStore(`${targets[i]}/trust.json`, targets[i], tapName, tapRepo)) {
        written = true;
      }
    }
    return written;
  }

  private static writeTrustStore(file: string, dir: string, tapName: string, tapRepo: string): boolean {
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      let taps: string[] = [];
      let formulae: string[] = [];
      let casks: string[] = [];
      let commands: string[] = [];
      try {
        if (fs.accessSync(file)) {
          const raw: Record<string, Object> = JSON.parse(fs.readTextSync(file)) as Record<string, Object>;
          taps = (raw['taps'] as string[]) ?? [];
          formulae = (raw['formulae'] as string[]) ?? [];
          casks = (raw['casks'] as string[]) ?? [];
          commands = (raw['commands'] as string[]) ?? [];
        }
      } catch (_) {
        // 损坏文件 → 重建
      }
      const entries: string[] = taps.slice();
      if (entries.indexOf(tapName) < 0) { entries.push(tapName); }
      if (tapRepo !== '' && entries.indexOf(tapRepo) < 0) { entries.push(tapRepo); }
      const body: Record<string, Object> = {};
      body['taps'] = entries;
      body['formulae'] = formulae;
      body['casks'] = casks;
      body['commands'] = commands;
      const f = fs.openSync(file, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      try {
        fs.writeSync(f.fd, JSON.stringify(body));
      } finally {
        fs.closeSync(f.fd);
      }
      // 照 brew 写惯例收紧权限（读路径不查——防将来版本加检查）
      try { DevTask.shell(`chmod 600 '${file}' 2>/dev/null`, () => {}, () => {}); } catch (_) {
      }
      Logger.info(TAG, `trust file written: ${file} (${entries.length} tap entries)`);
      return true;
    } catch (e) {
      Logger.warn(TAG, `writeTrustFile: ${e}`);
      return false;
    }
  }

  private static putBuiltinFlag(): void {
    if (BrewTapService.filesCtx === null) { return; }
    try {
      dataPreferences.getPreferences(BrewTapService.filesCtx, PREF_FILE).then((pref: dataPreferences.Preferences) => {
        pref.put(PREF_KEY_BUILTIN, true).then(() => { pref.flush(); }).catch(() => {});
      }).catch(() => {});
    } catch (_) {
    }
  }

  /** 重置信任落成标记（审计 F-P0-2：卸载 brew 后调用——标记不重置则重装
   *  后 ensureApplied 早退 → 社区 tap 永不重建 → 社区源安装全灭） */
  static reset(): void {
    BrewTapService.builtinApplied = false;
    if (BrewTapService.filesCtx === null) { return; }
    try {
      dataPreferences.getPreferences(BrewTapService.filesCtx, PREF_FILE).then((pref: dataPreferences.Preferences) => {
        pref.put(PREF_KEY_BUILTIN, false).then(() => { pref.flush(); }).catch(() => {});
      }).catch(() => {});
    } catch (_) {
    }
  }
}
