/**
 * DevEnvInstall —— 安装协议通用步骤执行器
 *
 * 协议：docs/安装协议与制品规范.md（唯一协议，无兼容层）
 * - manifest 每版本条目提供 install / activate / uninstall 声明式步骤
 * - 执行器按 action 词表实现，零语言特判、零推测；配方缺失即失败（责任方修配方）
 * - 占位符封闭词表：{name} {version} {kernel} {prefix} {home} {major_minor}
 *
 * action 词表：download / verify_sha256 / normalize / extract / chmod_bin /
 *   symlink(condition) / link_bin(links) / ensurepip / shell_rc(block_id) /
 *   exec_check(expect_stdout_prefix) / file_check(expect: exists|executable|elf,
 *   distro dec4f52 协议第 16 词——文件系统级探测，沙箱免疫) / provision / remove_dir
 */
import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { execSync, execAsync, cancel } from 'libdevbox_native.so';
import { DevEnvPaths } from './DevEnvPaths';
import { DevEnvHeal } from './DevEnvHeal';
import { DevEnvRegistry } from './DevEnvRegistry';
import { EnvStore } from './EnvStore';
import { DevTask } from './DevTask';
import Logger from './Logger';
import { DevDownload } from './DevDownload';
import statfs from '@ohos.file.statvfs';
import { DiscoveryService } from './DiscoveryService';
import { NativeExtract } from './NativeExtract';

const HOME = '/storage/Users/currentUser';
const TMP_DIR = `${HOME}/tmp`;

// ─── 协议类型 ─────────────────────────────────────────────

export interface StepSpec {
  id: string;
  action: string;
  title: string;
  weight: number;
  optional?: boolean;
  params: Record<string, Object>;
}

export interface Recipe {
  prefix: string;      // 已解析占位符
  steps: StepSpec[];
}

/** activate 段（仅 steps） */
export interface ActivateSpec {
  steps: StepSpec[];
}

/** uninstall 段 */
export interface UninstallSpec {
  steps: StepSpec[];
  autoActivate: string;      // 'highest_remaining' | 'none'
  onLastRemoved: string;     // 'clear_current_and_block' | 'none'
}

export interface InstallOp {
  kind: 'install';
  name: string;
  ver: string;
  url: string;
  sha256: string;
  size: number;
  recipe: Recipe;
}

export interface UninstallOp {
  kind: 'uninstall';
  name: string;
  ver: string;
  remaining: string[];
  spec: UninstallSpec;
  activateOf: (ver: string) => ActivateSpec | null;  // 剩余版本 → 其 activate 配方（auto_activate 用）
}

export interface InstallProgress {
  step: number;         // 1-based
  totalSteps: number;
  text: string;
  percent: number;      // 0-100 全局（按 weight 归一；下载步内细分）
}

export type ProgressCallback = (p: InstallProgress) => void;
export type DoneCallback = (success: boolean, message: string) => void;

// ─── 配方解析（manifest JSON → Recipe） ────────────────────

export class RecipeParser {

  /** manifest 条目 install/activate/uninstall 原文 → Recipe；不合规返回 null */
  static parse(kind: 'install' | 'activate' | 'uninstall', raw: string,
    name: string, ver: string, kernel: string): Recipe | ActivateSpec | UninstallSpec | null {
    if (raw === '') { return null; }
    let json: Record<string, Object> = {};
    try {
      json = JSON.parse(raw) as Record<string, Object>;
    } catch (_) {
      return null;
    }
    const prefixTpl: string = (json['prefix'] as string) ?? `{home}/usr/local/{name}/{version}`;
    const prefix: string = RecipeParser.resolve(prefixTpl, name, ver, kernel, '');
    const stepsArr: Object[] = (json['steps'] as Object[]) ?? [];
    const steps: StepSpec[] = [];
    for (let i = 0; i < stepsArr.length; i++) {
      const s: Record<string, Object> = stepsArr[i] as Record<string, Object>;
      if (s === undefined || s === null) { continue; }
      const step: StepSpec = {
        id: (s['id'] as string) ?? `step${i + 1}`,
        action: (s['action'] as string) ?? '',
        title: (s['title'] as string) ?? (s['action'] as string) ?? '',
        weight: (s['weight'] as number) ?? 5,
        optional: s['optional'] === true,
        params: (s['params'] as Record<string, Object>) ?? {},
      };
      if (step.action === '') { return null; }  // action 必填
      steps.push(step);
    }
    if (steps.length === 0) { return null; }
    if (kind === 'install') {
      return { prefix: prefix, steps: steps } as Recipe;
    }
    if (kind === 'activate') {
      return { steps: steps } as ActivateSpec;
    }
    return {
      steps: steps,
      autoActivate: (json['auto_activate'] as string) ?? 'none',
      onLastRemoved: (json['on_last_removed'] as string) ?? 'none',
    } as UninstallSpec;
  }

  /** 占位符解析（封闭词表 + ~/ 前缀展开——Unix 标准语义） */
  static resolve(tpl: string, name: string, ver: string, kernel: string, prefix: string): string {
    const segs: string[] = ver.split('.');
    const mm: string = segs.length >= 2 ? `${segs[0]}.${segs[1]}` : ver;
    let out: string = tpl
      .replace(/\{name\}/g, name)
      .replace(/\{version\}/g, ver)
      .replace(/\{kernel\}/g, kernel)
      .replace(/\{prefix\}/g, prefix)
      .replace(/\{home\}/g, HOME)
      .replace(/\{major_minor\}/g, mm);
    // 路径起始 ~/ 展开为主目录（平台部分条目用 ~ 替代 {home}，标准 Unix 语义）
    if (out.startsWith('~/')) {
      out = HOME + out.substring(1);
    }
    return out;
  }
}

// ─── 安装执行器 ───────────────────────────────────────────

export class DevEnvInstall {

  /** 语义化版本比较（降序；RuntimeMgr.verCmp 同款本地实现——避免循环依赖；跨类调用故非 private） */
  static verCmpDesc(a: string, b: string): number {
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

  private static op: InstallOp | null = null;
  private static progressCb: ProgressCallback | null = null;
  private static doneCb: DoneCallback | null = null;
  private static cancelled: boolean = false;
  private static asyncHandle: object | null = null;
  private static stepIdx: number = 0;          // 当前步骤下标（0-based）
  private static totalWeight: number = 0;
  private static doneWeight: number = 0;

  static install(op: InstallOp, onProgress: ProgressCallback, onDone: DoneCallback): void {
    if (op.recipe.steps.length === 0) {
      onDone(false, 'manifest 未提供 install 配方');
      return;
    }
    DevEnvInstall.op = op;
    DevEnvInstall.progressCb = onProgress;
    DevEnvInstall.doneCb = onDone;
    DevEnvInstall.cancelled = false;
    DevEnvInstall.stepIdx = -1;
    DevEnvInstall.totalWeight = 0;
    DevEnvInstall.doneWeight = 0;
    for (const s of op.recipe.steps) { DevEnvInstall.totalWeight += Math.max(1, s.weight); }
    DevEnvInstall.next();
  }

  static cancel(): void {
    DevEnvInstall.cancelWith('已取消');
  }

  /** 带自定义消息的取消（准备超时自动取消等场景；消息经 onDone toast 直达用户） */
  static cancelWith(message: string): void {
    DevEnvInstall.cancelled = true;
    hilog.info(0x0000, 'testTag', 'DevEnvInstall.cancel(%{public}s)', message.substring(0, 20));
    if (DevEnvInstall.asyncHandle !== null) {
      try { cancel(DevEnvInstall.asyncHandle); } catch (_) {
      }
      DevEnvInstall.asyncHandle = null;
    }
    // 下载中取消：remove agent 任务（防后台继续占带宽）
    // agent remove 后 completed/failed 都不回调——attempt 的 finish 永不触发（真机实证：
    // busy 卡死+后续安装直接闪退）。cancel 不依赖下载回调链，直接 finish 走取消收尾
    DevDownload.cancelCurrent();
    DevEnvInstall.finish(false, message);
  }

  private static next(): void {
    if (DevEnvInstall.cancelled || DevEnvInstall.op === null) { return; }
    DevEnvInstall.stepIdx += 1;
    const steps: StepSpec[] = DevEnvInstall.op.recipe.steps;
    if (DevEnvInstall.stepIdx >= steps.length) {
      // 假绿兜底（2026-11-19）：manifest 无 exec_check 的包，link_bin 声明的命令
      // 链可能从未生效（go/lua/psmisc/unzip 型——六步全绿账本 active，命令敲不了）。
      // 对声明的 bin 链逐个探测「存在 + 执行位」，MISSING/NOEXEC 判失败走回滚。
      // 不执行命令本体（--version 非 0 的正常差异不误伤），动态库加载类失败仍由
      // manifest exec_check 把关（python 3.13.16 实证路径）。
      const badLink: string = DevEnvInstall.verifyLinkedBins();
      hilog.info(0x0000, 'testTag', '[verify-install] linkedBins=%{public}s pkg=%{public}s', badLink === '' ? 'OK' : badLink, DevEnvInstall.op.name);
      if (badLink !== '') {
        DevEnvInstall.finish(false, `[verify-install] ${badLink}`);
        return;
      }
      // 快照登记：装完立即 install 同版本应被 already-installed 短路
      EnvStore.noteInstalled(DevEnvInstall.op.name, DevEnvInstall.op.ver);
      DevEnvInstall.finish(true, `${DevEnvInstall.op.name} ${DevEnvInstall.op.ver} 安装完成`);
      return;
    }
    const step: StepSpec = steps[DevEnvInstall.stepIdx];
    DevEnvInstall.report(`${step.title}…`);
    DevEnvInstall.dispatch(step);
  }

  /** 探测全部 link_bin 声明链 + 语言运行时主命令：MISSING=链未建立 /
   *  NOEXEC=不可执行；空串=全部通过。语言运行时必须探主命令——go/lua 型假绿
   *  的 manifest 无 link_bin 步骤，只探声明链对它们无效 */
  private static verifyLinkedBins(): string {
    const op = DevEnvInstall.op!;
    for (const s of op.recipe.steps) {
      if (s.action !== 'link_bin') { continue; }
      const links: Object[] = (s.params['links'] as Object[]) ?? [];
      for (const l of links) {
        const pair: Record<string, Object> = l as Record<string, Object>;
        const to: string = RecipeParser.resolve((pair['to'] as string) ?? '', op.name, op.ver, '', op.recipe.prefix);
        if (to === '') { continue; }
        let verdict = '';
        try {
          verdict = (execSync(
            `if [ ! -e '${to}' ]; then echo MISSING; elif [ ! -x '${to}' ]; then echo NOEXEC; else echo OK; fi`) ?? '').trim();
        } catch (_) {
          verdict = 'MISSING';
        }
        if (verdict === 'MISSING') {
          return `命令链未建立：${to}（manifest link_bin 声明与制品不符，请核查制品 bin 布局）`;
        }
        if (verdict === 'NOEXEC') {
          return `命令不可执行：${to}（缺执行位或动态加载器不匹配）`;
        }
      }
    }
    // 语言运行时主命令兜底：链存在且**运行输出含版本数字**（go/lua 型假绿 =
    // 链在但跑起来静默失败/报错——文件级 -e/-x 拦不住；"有输出"也不可靠，
    // PATH 畸形时 not found 的错误文本同样是输出——判定锚定版本数字本身）
    const mainProbe: Record<string, string> = {
      'python': 'python3 --version', 'BiShengJDK': 'java -version', 'rust': 'rustc --version',
      'node': 'node --version', 'lua': 'lua -v', 'perl': 'perl -v', 'php': 'php --version',
      'go': 'go version',
    };
    const probeSpec: string | undefined = mainProbe[op.name];
    if (probeSpec !== undefined) {
      const cmdName: string = probeSpec.split(' ')[0];
      const probeArgs: string = probeSpec.substring(cmdName.length);
      const to: string = `${HOME}/usr/local/bin/${cmdName}`;
      let linkVerdict = '';
      try {
        linkVerdict = (execSync(
          `if [ ! -e '${to}' ]; then echo MISSING; elif [ ! -x '${to}' ]; then echo NOEXEC; fi`) ?? '').trim();
      } catch (_) {
        linkVerdict = 'MISSING';
      }
      if (linkVerdict === 'MISSING') {
        return `运行时主命令链未建立：${to}（manifest 缺 link_bin 步骤，请核查制品 manifest）`;
      }
      if (linkVerdict === 'NOEXEC') {
        return `运行时主命令不可执行：${to}（缺执行位或动态加载器不匹配）`;
      }
      // 绝对路径执行（不依赖 PATH——PATH 构造畸形时 not found 文本也会被
      // "有输出"误判为通过，唯一可靠锚点是版本数字）
      let probeOut = '';
      try {
        probeOut = (execSync(
          `'${to}' ${probeArgs} 2>&1 | head -c 120`) ?? '').trim();
      } catch (_) {
        probeOut = '';
      }
      hilog.info(0x0000, 'testTag', '[verify-install] probe %{public}s %{public}s -> %{public}s',
        to, probeArgs, probeOut === '' ? '(empty)' : probeOut.substring(0, 60));
      if (!/\d+\.\d+/.test(probeOut)) {
        return `运行时主命令验证失败：${to} ${probeArgs} 输出异常（${probeOut.slice(0, 60) || '无输出'}）`;
      }
    }
    return '';
  }

  private static report(text: string, stepInnerPct: number = -1): void {
    // 跨进程锁心跳（progress 持续更新 mtime——2GB 下载>90s 时 MCP 不误判空闲；
    // 不调 RuntimeMgr（循环依赖）——锁文件直写）
    try {
      const ctx: common.UIAbilityContext | undefined = AppStorage.get<common.UIAbilityContext>('ui_context_ctx');
      if (ctx !== undefined && ctx !== null && DevEnvInstall.op !== null) {
        const f = fs.openSync(`${ctx.filesDir}/busy.lock`, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(f.fd, `${DevEnvInstall.op.name}|${DevEnvInstall.op.ver}|${Date.now()}`);
        fs.closeSync(f.fd);
      }
    } catch (_) {
    }
    if (DevEnvInstall.progressCb === null || DevEnvInstall.op === null) { return; }
    const steps: StepSpec[] = DevEnvInstall.op.recipe.steps;
    const step: StepSpec = steps[DevEnvInstall.stepIdx];
    const w: number = Math.max(1, step.weight);
    const inner: number = stepInnerPct >= 0 ? Math.min(1, Math.max(0, stepInnerPct / 100)) : 0;
    const pct: number = Math.min(100,
      Math.round((DevEnvInstall.doneWeight + w * inner) / DevEnvInstall.totalWeight * 100));
    DevEnvInstall.progressCb({
      step: DevEnvInstall.stepIdx + 1,
      totalSteps: steps.length,
      text: text,
      percent: pct,
    });
  }

  private static stepDone(skipped: boolean = false): void {
    // 迟到回调：op 已被 finish 清（取消或正常完成后）→ 无活跃安装 → 跳过
    // （原 guard 要求 cancelled 才拦——正常完成后的迟到 cp 回调穿透 crash，faultlog 实证）
    if (DevEnvInstall.op === null) { return; }
    const steps: StepSpec[] = DevEnvInstall.op!.recipe.steps;
    if (!skipped) {
      DevEnvInstall.doneWeight += Math.max(1, steps[DevEnvInstall.stepIdx].weight);
    }
    DevEnvInstall.next();
  }

  private static stepFail(step: StepSpec, msg: string): void {
    // 迟到回调：op 已被 finish 清 → 无活跃安装 → 跳过（不管 cancelled——
    // 正常完成后的迟到失败回调同样需要拦截）
    if (DevEnvInstall.op === null) { return; }
    if (step.optional) {
      DevEnvInstall.report(`（可选步骤跳过：${msg}）`);
      DevEnvInstall.stepDone();
      return;
    }
    DevEnvInstall.finish(false, `[${step.id}] ${msg}`);
  }

  private static finish(success: boolean, message: string): void {
    hilog.info(0x0000, 'testTag', 'DevEnvInstall.finish(%{public}s, %{public}s)',
      `${success}`, message.substring(0, 30));
    // 失败回滚：不留半拉子残骸（目录+current 链残留会被目录扫描误判"已安装+活跃"——
    // 真机实证：3.12.9 失败于第5步，前4步产物残留致界面假已装）。
    // 2026-11-13 追补（autoconf exec_check 失败实证）：① 空父目录 rmdir
    // （残骸父目录被 probeAll 目录名探测误判"已装"）；② current 断链后经
    // current 的 bin 软链必悬空，一并收走（直指他版的链不动）
    // 审计 C-P0-3：失败回滚改异步（此前同步 execSync rm -rf 2GB 级目录
    // 冻结 UI 数秒——违反"耗时操作必须异步"铁律）。回滚完成不阻塞
    // doneCb（用户已看到失败提示，回滚是后台清理）
    if (!success && DevEnvInstall.op !== null && DevEnvInstall.op.kind === 'install') {
      const prefix: string = DevEnvInstall.op.recipe.prefix;
      const base: string = prefix.substring(0, prefix.lastIndexOf('/'));
      const name: string = DevEnvInstall.op.name;
      const ver: string = DevEnvInstall.op.ver;
      // 异步执行全部回滚步骤（不阻塞回调链）。
      // current 目标三形态全覆盖（2026-11-17 bash 实证修复）：绝对 {prefix}、
      // 相对纯版本号 "{version}"（manifest to 写法）、绝对 */name/ver——此前只认
      // 绝对形态，相对 "5.3" 判定失败 → current 与 bin 链全残留。
      // bin 命令链同样两形态：经 current 跟随链（*/name/current/*）与直指版本
      // 目录的绝对链（*/name/ver/*，bash 的 from="{prefix}/bin/bash" 即此）。
      // 他版本在装时（current 指向别的 ver）guard 不中 → 误伤为零。
      // zshrc 共享 PATH 块不回滚（多包共用，指向的 bin 目录仍在）。
      DevTask.shell(
        `rm -rf '${prefix}' 2>/dev/null; ` +
        `rmdir '${base}' 2>/dev/null; ` +
        `CURRENT='${base}/current'; TARGET=$(readlink "$CURRENT" 2>/dev/null); ` +
        `if [ "$TARGET" = "${prefix}" ] || [ "$TARGET" = "${ver}" ] || ` +
        `[[ "$TARGET" == */"${name}"/"${ver}" ]]; then ` +
        `rm -f "$CURRENT"; ` +
        `for L in ${HOME}/usr/local/bin/*; do T=$(readlink "$L" 2>/dev/null); ` +
        `[[ "$T" == */"${name}"/current/* || "$T" == */"${name}"/"${ver}"/* ]] && rm -f "$L"; done; fi; ` +
        `rm -f '${TMP_DIR}/${name}-${ver}.tar.gz' 2>/dev/null`,
        (_t: string, _e: boolean) => {},
        (_ok: boolean, _d: string) => {
          Logger.info('DevEnvInstall', 'rollback completed (async)');
        });
    }
    // 状态必须先清再回调：doneCb → TaskQueue.done → 下一任务 run() → install()
    // 会同步重设 op/cb（重入）——先回调后清会把下一任务的状态抹掉，
    // 下一任务所有步骤回调被 op===null 守卫吞掉 → 队列卡死（真机实证：工具队列不前进）
    const cb = DevEnvInstall.doneCb;
    DevEnvInstall.op = null;
    DevEnvInstall.progressCb = null;
    DevEnvInstall.doneCb = null;
    if (cb !== null) {
      cb(success, message);
    }
  }

  private static P(key: string): string {
    // 当前步骤参数解析占位符
    const op = DevEnvInstall.op!;
    const step = op.recipe.steps[DevEnvInstall.stepIdx];
    const v: Object = step.params[key];
    if (typeof v === 'string') {
      return RecipeParser.resolve(v as string, op.name, op.ver, '', op.recipe.prefix);
    }
    return '';
  }

  // ─── action 分派 ─────────────────────────────────────────

  private static dispatch(step: StepSpec): void {
    switch (step.action) {
      case 'download':
        DevEnvInstall.actDownload();
        break;
      case 'verify_sha256':
        DevEnvInstall.actVerify();
        break;
      case 'normalize':
        DevEnvInstall.actNormalize();
        break;
      case 'extract':
        DevEnvInstall.actExtract();
        break;
      case 'chmod_bin':
        DevEnvInstall.actChmod();
        break;
      case 'symlink':
        DevEnvInstall.actSymlink();
        break;
      case 'link_bin':
        DevEnvInstall.actLinkBin();
        break;
      case 'ensurepip':
        DevEnvInstall.actEnsurepip();
        break;
      case 'shell_rc':
        DevEnvInstall.actShellRc();
        break;
      case 'exec_check':
        DevEnvInstall.actExecCheck();
        break;
      case 'provision':
        DevEnvInstall.actProvision();
        break;
      case 'shim':
        DevEnvInstall.actShim();
        break;
      case 'shebang_fix':
        DevEnvInstall.actShebangFix();
        break;
      case 'file_check':
        DevEnvInstall.actFileCheck();
        break;
      default:
        DevEnvInstall.stepFail(step, `未知 action「${step.action}」（manifest 协议违规）`);
    }
  }

  // download：url 来自条目级；dest 默认 {home}/tmp/{name}-{version}.tar.gz
  private static actDownload(): void {
    const op = DevEnvInstall.op!;
    // P2 磁盘预检：大包（2GB 级）装到解压步才失败太伤——下载前查工具链卷剩余
    // （需求≈压缩包+解压体 = size×2.5 保守；预检不过 fail fast 不浪费下载流量）
    try {
      const free: number = statfs.getFreeSizeSync(HOME);
      const need: number = (op.size > 0 ? op.size : 0) * 2.5 + 1048576 * 50;   // +50MB 系统余量
      if (op.size > 0 && free < need) {
        DevEnvInstall.stepFail(DevEnvInstall.curStep(),
          `磁盘空间不足（剩余 ${(free / 1073741824).toFixed(1)}G，需约 ${(need / 1073741824).toFixed(1)}G——压缩包+解压体）`);
        return;
      }
    } catch (_) {
      // statfs 失败不阻断（探测性预检）
    }
    if (op.url === '') {
      DevEnvInstall.stepFail(DevEnvInstall.curStep(),
        '条目缺 url 字段（制品下载唯一取法 = url 直连）');
      return;
    }
    const tmpFile: string = DevEnvInstall.P('dest') !== ''
      ? DevEnvInstall.P('dest')
      : `${TMP_DIR}/${op.name}-${op.ver}.tar.gz`;
    // 缓存名掺 sha 前 8 位：制品重传（同版本号换内容）时缓存自动失效重新下载——
    // 否则 request.agent 复用旧文件（overwrite:false 断点续传）+ verify 新 sha 比对
    // 旧文件必失败，且失败不清缓存源 → 同版本重装永远失败（用户抓到的真缺陷）
    const shaTag: string = op.sha256 !== '' ? `-${op.sha256.substring(0, 8)}` : '';
    const cacheName = `${op.name}-${op.ver}${shaTag}.tar.gz`;
    DevDownload.download(op.url, cacheName,
      (processed: number, _agentTotal: number, etaSec: number) => {
        const total: number = op.size > 0 ? op.size : _agentTotal;
        if (total > 0) {
          const pct: number = Math.min(100, Math.round(processed / total * 100));
          // P2 ETA：>20s 才显示（短下载不值得闪；大包 2GB 用户最关心）
          let eta: string = '';
          if (etaSec > 20) {
            const m: number = Math.floor(etaSec / 60);
            eta = m >= 1 ? ` 预计还需 ${m} 分 ${etaSec % 60} 秒` : ` 预计还需 ${etaSec} 秒`;
          }
          DevEnvInstall.report(
            `下载中 ${pct}% ${(processed / 1048576).toFixed(1)}M/${(total / 1048576).toFixed(0)}M${eta}`, pct);
        }
      },
      (ok: boolean, msg: string) => {
        if (DevEnvInstall.cancelled) { DevEnvInstall.finish(false, '已取消'); return; }
        if (!ok) { DevEnvInstall.stepFail(DevEnvInstall.curStep(), `下载失败：${msg}`); return; }
        DevTask.shell(
          `mkdir -p '${TMP_DIR}' && cp -f '${msg}' '${tmpFile}' && rm -f '${msg}' && echo DEVBOX_OK || echo DEVBOX_FAIL`,
          (_t: string, _e: boolean) => {
          }, (cpOk: boolean, _d: string) => {
            if (cpOk) { DevEnvInstall.stepDone(); } else { DevEnvInstall.stepFail(DevEnvInstall.curStep(), '文件落盘失败'); }
          });
      });
  }

  private static curStep(): StepSpec {
    // 取消后迟到回调（子进程被杀 code≠0→stepFail 参数求值先调 curStep）
    // → op 已 null → null 断言 crash（两个 faultlog 栈 410 行实证）。
    // 返回哑 step：stepFail 只取 id 做文案不 crash
    if (DevEnvInstall.op === null) {
      const stub: StepSpec = {
        id: 'cancelled', title: '已取消', action: '', weight: 1,
        optional: false, params: {} as Record<string, Object>
      };
      return stub;
    }
    return DevEnvInstall.op!.recipe.steps[DevEnvInstall.stepIdx];
  }

  /** request.agent saveas 缓存名（与 actDownload 一致；verify 失败清理用） */
  private static downloadCacheName(op: InstallOp): string {
    const shaTag: string = op.sha256 !== '' ? `-${op.sha256.substring(0, 8)}` : '';
    return `${op.name}-${op.ver}${shaTag}.tar.gz`;
  }

  // verify_sha256：比对条目级 sha256
  private static actVerify(): void {
    const op = DevEnvInstall.op!;
    const tmpFile: string = `${TMP_DIR}/${op.name}-${op.ver}.tar.gz`;
    let hashOut: string = '';
    DevEnvInstall.asyncHandle = execAsync(
      `sha256sum '${tmpFile}' 2>/dev/null | cut -d' ' -f1`,
      (t: string, _e: boolean) => { hashOut += t; },
      (code: number) => {
        DevEnvInstall.asyncHandle = null;
        const actual: string = hashOut.trim();
        if (code === 0 && actual === op.sha256) {
          DevEnvInstall.stepDone();
        } else {
          try { fs.unlinkSync(tmpFile); } catch (_) {
          }
          // 同步清理 cacheDir 源缓存（request.agent saveas——失败不清则断点续传
          // 复用同坏文件，重装永远失败）；op.url 为空的旧场景无 saveas 可清
          if (op.url !== '') {
            try {
              const ctx = AppStorage.get<common.UIAbilityContext>('ui_context_ctx');
              if (ctx !== undefined && ctx !== null) {
                const cachedName = DevEnvInstall.downloadCacheName(op);
                const stale = `${ctx.cacheDir}/${cachedName}`;
                if (fs.accessSync(stale)) { fs.unlinkSync(stale); }
              }
            } catch (_) {
            }
          }
          DevEnvInstall.stepFail(DevEnvInstall.curStep(),
            `SHA256 不匹配（期望 ${op.sha256.substring(0, 12)}…，实际 ${actual.substring(0, 12)}…）`);
        }
      },
    );
  }

  // normalize：dest 下唯一子目录上提到 dest
  private static actNormalize(): void {
    const dest: string = DevEnvInstall.P('dest') !== '' ? DevEnvInstall.P('dest') : DevEnvInstall.op!.recipe.prefix;
    DevEnvInstall.normalizeLayout(dest);
    DevEnvInstall.stepDone();
  }

  // extract：解压到 dest，随后自动 normalize（协议：extract 内含 normalize）
  private static actExtract(): void {
    const op = DevEnvInstall.op!;
    const tmpFile = `${TMP_DIR}/${op.name}-${op.ver}.tar.gz`;
    const dest: string = DevEnvInstall.P('dest') !== '' ? DevEnvInstall.P('dest') : op.recipe.prefix;
    const phase = (p: string): string => `[extract@${p}]`;   // 细粒度定位
    try {
      try {
        if (fs.accessSync(dest)) { execSync(`rm -rf '${dest}'`); }
      } catch (e) {
        DevEnvInstall.stepFail(DevEnvInstall.curStep(), `${phase('rm旧目录')} ${e}`);
        return;
      }
      const parent = dest.substring(0, dest.lastIndexOf('/'));
      try {
        if (!fs.accessSync(parent)) { fs.mkdirSync(parent, true); }
      } catch (e) {
        DevEnvInstall.stepFail(DevEnvInstall.curStep(), `${phase('mkdir父')} ${parent}: ${e}`);
        return;
      }
      try {
        fs.mkdirSync(dest, true);
      } catch (e) {
        DevEnvInstall.stepFail(DevEnvInstall.curStep(), `${phase('mkdir')} ${dest}: ${e}`);
        return;
      }
      try {
        fs.accessSync(tmpFile);
      } catch (e) {
        DevEnvInstall.stepFail(DevEnvInstall.curStep(), `${phase('包缺失')} ${tmpFile}`);
        return;
      }
      // 格式分发（2026-11-19）：原写死 extractTarGz——xz 制品（commandline-tools
      // 26.0.0.201 为 .tar.xz）被按 gzip 流解压 → rc=7 decompression stream error。
      // 改用通用入口 'auto'（native 按 magic 识别 tar.gz/tar.xz/tar），对既有
      // gzip 制品行为不变
      NativeExtract.extract(tmpFile, dest, 'auto').then((code: number) => {
        try { fs.unlinkSync(tmpFile); } catch (_) {
        }
        if (code !== 0) { DevEnvInstall.stepFail(DevEnvInstall.curStep(), `${phase('native')} 解压失败 rc=${code}`); return; }
        setTimeout(() => {
          DevEnvInstall.normalizeLayout(dest);
          DevEnvInstall.stepDone();
        }, 50);
      }).catch((e: Object) => {
        DevEnvInstall.stepFail(DevEnvInstall.curStep(), `${phase('promise')} ${e}`);
      });
    } catch (e) {
      DevEnvInstall.stepFail(DevEnvInstall.curStep(), `${phase('外层')} ${e}`);
    }
  }

  /** 外壳目录上提 + usr/ 前缀上提（两种历史 tarball 布局兼容；协议 A1 兜底） */
  private static normalizeLayout(destDir: string): void {
    try {
      const entries = fs.listFileSync(destDir);
      if (entries.length === 1) {
        const only = entries[0];
        const onlyPath = `${destDir}/${only}`;
        if (fs.statSync(onlyPath).isDirectory()) {
          // 协议语义（SPEC 2.2）：外壳上提=把 <dest>/<外壳>/* 移入 <dest>，缺省
          // 自动探测单根目录——无内容前置条件。原 hasBin/hasUsr/hasLib 防御是
          // python 型布局的历史兜底，挡住了 commandline-tools 型多组件根
          // （顶层 hvigor/ohpm/node/sdk 无 bin|usr|lib → 上提被跳过 →
          // {version}/command-line-tools/hvigor/... 多一层外壳，manifest 声明
          // {prefix}/hvigor/... 落空，linkbin 报源不存在——第五轮实测实证）
          const subEntries = fs.listFileSync(onlyPath);
          for (const se of subEntries) {
            try { fs.renameSync(`${onlyPath}/${se}`, `${destDir}/${se}`); } catch (_) {
            }
          }
          try { fs.rmdirSync(onlyPath); } catch (_) {
          }
        }
      }
      const usrPath = `${destDir}/usr`;
      try {
        if (fs.accessSync(usrPath)) {
          const usrEntries = fs.listFileSync(usrPath);
          for (const ue of usrEntries) {
            try { fs.renameSync(`${usrPath}/${ue}`, `${destDir}/${ue}`); } catch (_) {
            }
          }
          try { fs.rmdirSync(usrPath); } catch (_) {
          }
        }
      } catch (_) {
      }
    } catch (_) {
    }
  }

  // chmod_bin：目录内实体加执行位（fs 无 chmod，shell 实现）
  private static actChmod(): void {
    const dir: string = DevEnvInstall.P('dir') !== '' ? DevEnvInstall.P('dir') : `${DevEnvInstall.op!.recipe.prefix}/bin`;
    try {
      execSync(`find '${dir}' -type f -exec chmod +x {} + 2>/dev/null; echo OK`) ?? '';
    } catch (_) {
    }
    DevEnvInstall.stepDone();
  }

  // symlink：link/to/relative/condition(always|if_no_valid)
  private static actSymlink(): void {
    const op = DevEnvInstall.op!;
    const step = DevEnvInstall.curStep();
    const linkPath: string = DevEnvInstall.P('link');
    let target: string = DevEnvInstall.P('to');
    const relative: boolean = step.params['relative'] !== false;   // 默认相对
    const condition: string = (step.params['condition'] as string) ?? 'always';
    if (linkPath === '' || target === '') {
      DevEnvInstall.stepFail(step, 'symlink 缺 params.link/to（协议违规）');
      return;
    }
    if (!relative) {
      target = `${DevEnvInstall.op!.recipe.prefix}/${target}`;
    }
    // if_no_valid：链接有效（存在且目标可达）则跳过——首版设活跃语义
    if (condition === 'if_no_valid') {
      try {
        fs.lstatSync(linkPath);
        fs.statSync(linkPath);   // 悬空会抛
        DevEnvInstall.report('（已有有效链接，跳过）');
        DevEnvInstall.stepDone(true);
        return;
      } catch (_) {
      }
    }
    // 清旧（含悬空/实体目录残留）→ 建链
    try {
      fs.lstatSync(linkPath);
      execSync(`rm -rf '${linkPath}' 2>/dev/null`);
    } catch (_) {
    }
    try {
      fs.symlinkSync(target, linkPath);
    } catch (e) {
      DevEnvInstall.stepFail(step, `建链失败 ${linkPath} → ${target}：${e}`);
      return;
    }
    // 校验回读（fs 无 readLink，shell）
    const back: string = execSync(`readlink '${linkPath}' 2>/dev/null`) ?? '';
    if (back.trim() !== target) {
      DevEnvInstall.stepFail(step, `链接校验不符：${back}`);
      return;
    }
    void op;
    DevEnvInstall.stepDone();
  }

  // link_bin：links 数组逐对建链（from 为相对文本原样写入）
  private static actLinkBin(): void {
    const step = DevEnvInstall.curStep();
    const links: Object[] = (step.params['links'] as Object[]) ?? [];
    if (links.length === 0) {
      DevEnvInstall.stepFail(step, 'link_bin 缺 params.links（协议违规）');
      return;
    }
    for (let i = 0; i < links.length; i++) {
      const pair: Record<string, Object> = links[i] as Record<string, Object>;
      const fromRaw: string = (pair['from'] as string) ?? '';
      const toRaw: string = (pair['to'] as string) ?? '';
      const from: string = RecipeParser.resolve(fromRaw, DevEnvInstall.op!.name, DevEnvInstall.op!.ver, '', DevEnvInstall.op!.recipe.prefix);
      const to: string = RecipeParser.resolve(toRaw, DevEnvInstall.op!.name, DevEnvInstall.op!.ver, '', DevEnvInstall.op!.recipe.prefix);
      if (from === '' || to === '') {
        DevEnvInstall.stepFail(step, `links[${i}] 缺 from/to`);
        return;
      }
      const parent = to.substring(0, to.lastIndexOf('/'));
      try {
        if (!fs.accessSync(parent)) { fs.mkdirSync(parent, true); }
      } catch (_) {
      }
      // 1) to 已存在且不悬空 → 保留（旧活跃版本的链有效；多版本共存 install 不抢链，
      //    切换由 activate 配方重建——真机实证：probe 走 current 会在异版本系追加时错位）
      let keep = false;
      try {
        fs.statSync(to);   // 悬空会抛（lstat 存在但 stat 不可达）
        keep = true;
      } catch (_) {
      }
      if (keep) { continue; }
      // 2) probe 探测本次 prefix：验证「声明的实体在本制品有效」。
      //    - from 为相对 dir 的链文本（../pkg/current/bin/x）→ 与 parent 拼 + current 段
      //      替换为本次版本目录（探测瞬态 current 会在异版本系活跃时误判）
      //    - from 为绝对路径（{prefix}/bin/x，协议 6cdf8a36 起平台新形态）→ 原样探测，
      //      不可与 parent 拼接（拼出废路径必 fail——真机实证「链接源不存在」）
      const op = DevEnvInstall.op!;
      const joined: string = from.startsWith('/') ? from : `${parent}/${from}`;
      const probePath: string = joined
        .replace(`/${op.name}/current/`, `/${op.name}/${op.ver}/`);
      try {
        const probe: string = execSync(`test -e '${probePath}' && echo OK || echo MISSING`) ?? '';
        if (probe.indexOf('MISSING') >= 0) {
          DevEnvInstall.stepFail(step, `链接源不存在：${from}（制品/前置步骤未提供，协议违例）`);
          return;
        }
      } catch (_) {
      }
      // 3) 清旧（含悬空）→ 建链
      try {
        try { fs.lstatSync(to); fs.unlinkSync(to); } catch (_) {
        }
        fs.symlinkSync(from, to);
      } catch (e) {
        DevEnvInstall.stepFail(step, `建链失败 ${to}：${e}`);
        return;
      }
    }
    DevEnvInstall.stepDone();
  }

  // ensurepip：bin（版本化实体）-m ensurepip --upgrade
  private static actEnsurepip(): void {
    const step = DevEnvInstall.curStep();
    const bin: string = DevEnvInstall.P('bin');
    if (bin === '') {
      DevEnvInstall.stepFail(step, 'ensurepip 缺 params.bin');
      return;
    }
    // 异步执行（解 wheel 数十秒，execSync 会冻结 UI——耗时操作必须异步铁律）
    DevEnvInstall.report('正在引导 pip（ensurepip，可能需要一分钟）…');
    DevEnvInstall.asyncHandle = execAsync(
      `'${bin}' -m ensurepip --upgrade 2>&1 | tail -2`,
      (_t: string, _e: boolean) => {
      },
      (code: number) => {
        DevEnvInstall.asyncHandle = null;
        if (code === 0) {
          DevEnvInstall.stepDone();
        } else {
          DevEnvInstall.stepFail(DevEnvInstall.curStep(), `ensurepip 失败（exit ${code}）`);
        }
      },
    );
  }

  // shell_rc：file/block_id/lines —— 标记块整块替换（幂等）
  private static actShellRc(): void {
    const step = DevEnvInstall.curStep();
    const file: string = DevEnvInstall.P('file') !== '' ? DevEnvInstall.P('file') : `${HOME}/.zshrc`;
    const blockId: string = (step.params['block_id'] as string) ?? '';
    if (blockId === '') {
      DevEnvInstall.stepFail(step, 'shell_rc 缺 params.block_id（协议违规）');
      return;
    }
    const linesArr: Object[] = (step.params['lines'] as Object[]) ?? [];
    const lines: string[] = [];
    for (const l of linesArr) {
      lines.push(RecipeParser.resolve(`${l}`, DevEnvInstall.op!.name, DevEnvInstall.op!.ver, '', DevEnvInstall.op!.recipe.prefix));
    }
    const begin = `# >>> ${blockId} >>>`;
    const end = `# <<< ${blockId} <<<`;
    let content: string = '';
    try { content = fs.readTextSync(file); } catch (_) {
    }
    const out: string[] = [];
    let inBlock = false;
    let replaced = false;
    for (const raw of content.split('\n')) {
      const t: string = raw.trim();
      if (t === begin) { inBlock = true; continue; }
      if (t === end) {
        inBlock = false;
        // 原块位置写入新块
        out.push(begin);
        for (const l of lines) { out.push(l); }
        out.push(end);
        replaced = true;
        continue;
      }
      if (!inBlock) { out.push(raw); }
    }
    if (!replaced) {
      if (out.length > 0 && out[out.length - 1].trim() !== '') { out.push(''); }
      out.push(begin);
      for (const l of lines) { out.push(l); }
      out.push(end);
    }
    try {
      const f = fs.openSync(file, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(f.fd, out.join('\n') + '\n');
      fs.closeSync(f.fd);
      DevEnvInstall.stepDone();
    } catch (e) {
      DevEnvInstall.stepFail(step, `写入 ${file} 失败：${e}`);
    }
  }

  // exec_check：cmd（绝对路径/实体名）+ expect_stdout_prefix
  private static actExecCheck(): void {
    const step = DevEnvInstall.curStep();
    let cmd: string = DevEnvInstall.P('cmd');
    if (cmd === '') {
      DevEnvInstall.stepFail(step, 'exec_check 缺 params.cmd');
      return;
    }
    // install 阶段 current 段=本次版本目录（与 link_bin probe 同构语义）：
    // if_no_valid 下安装不抢活跃，cmd 写 current/bin/python{major_minor} 在
    // 多版本共存时指向旧版目录必然 not found（真机实证：3.12.15 活跃装 3.13.16）
    const op0 = DevEnvInstall.op!;
    cmd = cmd.replace(`/${op0.name}/current/`, `/${op0.name}/${op0.ver}/`);
    const expectPrefix: string = (step.params['expect_stdout_prefix'] as string) ?? '';
    const expectRcRaw: Object | undefined = step.params['expect_rc'];
    try {
      if (expectRcRaw !== undefined && expectRcRaw !== null) {
        // expect_rc 形态（如 node 配方）：一条命令串取真实退出码+首行输出
        const tmpOut = `${TMP_DIR}/exec_check.out`;
        const out: string = execSync(
          `${cmd} > '${tmpOut}' 2>&1; rc=$?; head -1 '${tmpOut}'; echo __RC=$rc; rm -f '${tmpOut}'`) ?? '';
        const rcMark: string = out.substring(out.lastIndexOf('__RC=') + 5).trim();
        const firstLine: string = out.substring(0, out.lastIndexOf('__RC=')).trim();
        const expectRc: number = Number(`${expectRcRaw}`) || 0;
        if (rcMark !== `${expectRc}`) {
          DevEnvInstall.stepFail(step,
            `验证不符：期望退出码 ${expectRc}，实际 ${rcMark}（${firstLine.substring(0, 30)}）`);
          return;
        }
        DevEnvInstall.report(firstLine.substring(0, 36));
        DevEnvInstall.stepDone();
        return;
      }
      const out: string = execSync(`${cmd} 2>&1 | head -1`) ?? '';
      if (expectPrefix !== '') {
        const resolved: string = RecipeParser.resolve(expectPrefix,
          DevEnvInstall.op!.name, DevEnvInstall.op!.ver, '', DevEnvInstall.op!.recipe.prefix);
        if (!out.startsWith(resolved)) {
          DevEnvInstall.stepFail(step, `验证不符：期望「${resolved}…」，实际「${out.substring(0, 30)}」`);
          return;
        }
      } else if (out.trim() === '') {
        DevEnvInstall.stepFail(step, '验证无输出');
        return;
      }
      DevEnvInstall.report(out.trim().substring(0, 36));
      DevEnvInstall.stepDone();
    } catch (e) {
      DevEnvInstall.stepFail(step, `执行失败：${e}`);
    }
  }

  // file_check（协议 v2 第 16 词，distro dec4f52 定稿）：文件系统级探测，不 exec
  // 命令本体——沙箱天然免疫（应用环境≠用户环境，协议只验部署完整性）。
  // expect 三档：exists（存在）/ executable（存在+执行位）/ elf（存在+ELF 魔数）
  // 铁律：path 用 {prefix} 本次产物、禁 current（同 exec_check——多版本共存时
  // current 指旧版目录）；缺文件 fail loud（expat 型"manifest 声明 bin 包里没有"
  // 前置暴露）；elf 档拦截"声明二进制实为脚本"的打包错误
  private static actFileCheck(): void {
    const step = DevEnvInstall.curStep();
    const op = DevEnvInstall.op!;
    const pathTpl: string = DevEnvInstall.P('path');
    const expect: string = (step.params['expect'] as string) ?? 'executable';
    if (pathTpl === '') {
      DevEnvInstall.stepFail(step, 'file_check 缺 params.path');
      return;
    }
    if (expect !== 'exists' && expect !== 'executable' && expect !== 'elf') {
      DevEnvInstall.stepFail(step, `file_check expect 非法「${expect}」（词表：exists/executable/elf）`);
      return;
    }
    // 占位符解析 + current 段替换为本次版本目录（铁律：禁 current）
    let path: string = RecipeParser.resolve(pathTpl, op.name, op.ver, '', op.recipe.prefix);
    path = path.replace(`/${op.name}/current/`, `/${op.name}/${op.ver}/`);
    if (path.includes(`/${op.name}/current/`)) {
      DevEnvInstall.stepFail(step, `file_check path 禁用 current（铁律同 exec_check）`);
      return;
    }
    try {
      // 一条探测命令出三档判定（shell 分支 + od 取魔数——execSync 无返回码形态，
      // 输出编码判定与全链既有风格一致）
      const verdict: string = (execSync(
        `if [ ! -e '${path}' ]; then echo NOT_EXISTS; ` +
        `elif [ ! -x '${path}' ]; then echo NOT_EXEC; ` +
        `elif [ "$(head -c 4 '${path}' 2>/dev/null | od -An -tx1 | tr -d ' \\n')" = "7f454c46" ]; then echo ELF; ` +
        `else echo SCRIPT; fi`) ?? '').trim();
      if (verdict === 'NOT_EXISTS') {
        DevEnvInstall.stepFail(step, `产物缺失：${path}（manifest 声明与制品不符，请核查制品布局）`);
        return;
      }
      if (expect === 'exists') {
        DevEnvInstall.report(`${path} 存在`);
        DevEnvInstall.stepDone();
        return;
      }
      if (verdict === 'NOT_EXEC') {
        DevEnvInstall.stepFail(step, `无执行位：${path}（expect=executable）`);
        return;
      }
      if (expect === 'executable') {
        DevEnvInstall.report(`${path} 可执行`);
        DevEnvInstall.stepDone();
        return;
      }
      // expect === 'elf'
      if (verdict === 'ELF') {
        DevEnvInstall.report(`${path} ELF`);
        DevEnvInstall.stepDone();
      } else {
        DevEnvInstall.stepFail(step, `非 ELF（${verdict === 'SCRIPT' ? '脚本文本' : '未知格式'}）：${path}（manifest 声明二进制，制品实为其他形态）`);
      }
    } catch (e) {
      DevEnvInstall.stepFail(step, `探测失败：${e}`);
    }
  }

  // shim：dir + entries[{name, exec}] —— 写命令包装脚本（协议化 npm/npx/corepack 包装）
  // exec 形如 "node lib/node_modules/npm/bin/npm-cli.js"：node 固定用 {prefix 所在 current}/bin/node，
  // 相对路径基于 current 目录
  private static actShim(): void {
    const step = DevEnvInstall.curStep();
    const dir: string = DevEnvInstall.P('dir');
    const entries: Object[] = (step.params['entries'] as Object[]) ?? [];
    if (dir === '' || entries.length === 0) {
      DevEnvInstall.stepFail(step, 'shim 缺 params.dir/entries');
      return;
    }
    // current 路径：prefix=…/<name>/<version> → …/<name>/current
    const prefix: string = DevEnvInstall.op!.recipe.prefix;
    const base: string = prefix.substring(0, prefix.lastIndexOf('/'));
    const currentDir: string = `${base}/current`;
    const nodeBin: string = `${currentDir}/bin/node`;
    try {
      if (!fs.accessSync(dir)) { fs.mkdirSync(dir, true); }
    } catch (_) {
    }
    for (let i = 0; i < entries.length; i++) {
      const ent: Record<string, Object> = entries[i] as Record<string, Object>;
      const name: string = (ent['name'] as string) ?? '';
      const execRaw: string = (ent['exec'] as string) ?? '';
      if (name === '' || execRaw === '') {
        DevEnvInstall.stepFail(step, `entries[${i}] 缺 name/exec`);
        return;
      }
      // exec 首 token 是解释器（node），其余为相对 current 的脚本路径
      const toks: string[] = execRaw.trim().split(/\s+/);
      const scriptRel: string = toks.length > 1 ? toks.slice(1).join(' ') : '';
      if (scriptRel === '') {
        DevEnvInstall.stepFail(step, `entries[${i}] exec 缺脚本路径：${execRaw}`);
        return;
      }
      const scriptPath = `${dir}/${name}`;
      const content = `#!/system/bin/sh\nexec "${nodeBin}" "${currentDir}/${scriptRel}" "$@"\n`;
      try { fs.lstatSync(scriptPath); fs.unlinkSync(scriptPath); } catch (_) {
      }
      try {
        const f = fs.openSync(scriptPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(f.fd, content);
        fs.closeSync(f.fd);
        execSync(`chmod +x '${scriptPath}'`);   // fs 无 chmod
      } catch (e) {
        DevEnvInstall.stepFail(step, `shim ${name} 写入失败：${e}`);
        return;
      }
    }
    DevEnvInstall.stepDone();
  }

  // shebang_fix：dir + pattern + replace —— 扫描脚本首行（shebang），匹配则替换为 "#!{replace}"
  // （用例：perl 包把 "#!.*perl" 统一改为 "#!{prefix}/bin/perl-wrapper"）
  private static actShebangFix(): void {
    const step = DevEnvInstall.curStep();
    const op = DevEnvInstall.op!;
    const dirRaw: string = (step.params['dir'] as string) ?? 'bin';
    const pattern: string = (step.params['pattern'] as string) ?? '';
    const replaceTpl: string = (step.params['replace'] as string) ?? '';
    if (pattern === '' || replaceTpl === '') {
      DevEnvInstall.stepFail(step, 'shebang_fix 缺 params.pattern/replace');
      return;
    }
    const dir: string = dirRaw.startsWith('/')
      ? RecipeParser.resolve(dirRaw, op.name, op.ver, '', op.recipe.prefix)
      : `${op.recipe.prefix}/${dirRaw}`;
    const replace: string = RecipeParser.resolve(replaceTpl, op.name, op.ver, '', op.recipe.prefix);
    const re = new RegExp(pattern);
    let files: string[] = [];
    try {
      files = fs.listFileSync(dir);
    } catch (e) {
      DevEnvInstall.stepFail(step, `shebang_fix 目录不可读 ${dir}：${e}`);
      return;
    }
    let fixed = 0;
    const decoder = util.TextDecoder.create('utf-8', { fatal: false });
    for (const f of files) {
      const path = `${dir}/${f}`;
      try {
        if (fs.statSync(path).isDirectory()) { continue; }
        // 读前 512B 判首行（避免整读大文件）
        const fh = fs.openSync(path, fs.OpenMode.READ_ONLY);
        const buf = new ArrayBuffer(512);
        fs.readSync(fh.fd, buf);
        fs.closeSync(fh.fd);
        const head: string = decoder.decodeToString(new Uint8Array(buf));
        const nl = head.indexOf('\n');
        const firstLine: string = nl >= 0 ? head.substring(0, nl) : head;
        if (!re.test(firstLine)) { continue; }
        // 匹配 → 整文件重写首行
        const text: string = fs.readTextSync(path);
        const nl2 = text.indexOf('\n');
        const rest: string = nl2 >= 0 ? text.substring(nl2 + 1) : '';
        const wf = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(wf.fd, `#!${replace}\n${rest}`);
        fs.closeSync(wf.fd);
        fixed++;
      } catch (_) {
        // 单文件失败继续（不阻断）
      }
    }
    DevEnvInstall.report(`修正 ${fixed} 个脚本 shebang`);
    DevEnvInstall.stepDone();
  }

  // provision：tool=pip/npm/maven —— 装后首配源（用户无配置才写，不覆盖）
  private static actProvision(): void {
    const tool: string = (DevEnvInstall.curStep().params['tool'] as string) ?? '';
    const cfg = DiscoveryService.latest();
    try {
      if (tool === 'pip') {
        const idx: string = cfg.recommendedPipIndex();
        const conf: string = `${HOME}/.pip/pip.conf`;
        if (idx !== '' && !fs.accessSync(conf)) {
          try {
            if (!fs.accessSync(`${HOME}/.pip`)) { fs.mkdirSync(`${HOME}/.pip`, true); }
          } catch (_) {
          }
          const f = fs.openSync(conf, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
          fs.writeSync(f.fd, `[global]\nindex-url = ${idx}\n`);
          fs.closeSync(f.fd);
        }
      } else if (tool === 'npm') {
        // 配方参数驱动（平台 6cdf8a36 形态）：prefix（全局位置——npm 推断机制在
        // 软链/多版本环境不可靠，显式指 current 随切换重指）+ registry（镜像源）
        const prefix: string = DevEnvInstall.P('prefix');
        const regRaw: string = DevEnvInstall.P('registry');
        const reg: string = regRaw !== '' ? regRaw : cfg.recommendedNpmRegistry();
        const rcPath: string = `${HOME}/.npmrc`;
        let text: string = '';
        try { text = fs.readTextSync(rcPath); } catch (_) {
        }
        // 逐项"缺才写"（用户已有配置不覆盖——provision 语义；两项独立检查）
        const lines: string[] = text === '' ? [] : text.split('\n');
        let hasPrefix = false;
        let hasReg = false;
        for (const line of lines) {
          const t: string = line.trim();
          if (t.startsWith('prefix=')) { hasPrefix = true; }
          if (t.startsWith('registry=')) { hasReg = true; }
        }
        let changed = false;
        if (prefix !== '' && !hasPrefix) { lines.push(`prefix=${prefix}`); changed = true; }
        if (reg !== '' && !hasReg) { lines.push(`registry=${reg}`); changed = true; }
        if (changed) {
          try {
            const f = fs.openSync(rcPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
            fs.writeSync(f.fd, lines.join('\n') + '\n');
            fs.closeSync(f.fd);
          } catch (_) {
          }
        }
      } else if (tool === 'maven') {
        const reg: string = cfg.mavenRegistry;
        const settings: string = `${HOME}/.m2/settings.xml`;
        if (reg !== '' && !fs.accessSync(settings)) {
          try {
            if (!fs.accessSync(`${HOME}/.m2`)) { fs.mkdirSync(`${HOME}/.m2`, true); }
          } catch (_) {
          }
          const f = fs.openSync(settings, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
          fs.writeSync(f.fd, `<settings><mirrors><mirror><id>ohpcd</id><mirrorOf>central</mirrorOf><url>${reg}</url></mirror></mirrors></settings>`);
          fs.closeSync(f.fd);
        }
      }
    } catch (_) {
    }
    DevEnvInstall.stepDone();
  }
}

// ─── 切换（activate 配方驱动） ─────────────────────────────

export class DevEnvSwitch {

  static switch(name: string, ver: string, spec: ActivateSpec | null,
    onProgress: ProgressCallback, onDone: DoneCallback): void {
    if (spec === null || spec.steps.length === 0) {
      onDone(false, 'manifest 未提供 activate 配方');
      return;
    }
    const prefix: string = `${HOME}/usr/local/${name}/${ver}`;
    const steps: StepSpec[] = spec.steps;
    const run = (i: number): void => {
      if (i >= steps.length) {
        onProgress({ step: steps.length, totalSteps: steps.length, text: '完成', percent: 100 });
        onDone(true, `已切换 ${name} → ${ver}`);
        return;
      }
      const s: StepSpec = steps[i];
      onProgress({ step: i + 1, totalSteps: steps.length, text: `${s.title}…`, percent: Math.round(i / steps.length * 100) });
      // activate 只含元数据级操作（symlink/link_bin）；逐个内联执行（与安装执行器同语义）
      const r = DevEnvSwitch.runOne(s, name, ver, prefix);
      if (r === '') { run(i + 1); } else { onDone(false, `[${s.id}] ${r}`); }
    };
    run(0);
  }

  /** 单步执行，返回空=成功，否则错误信息（仅支持元数据级 action） */
  private static runOne(s: StepSpec, name: string, ver: string, prefix: string): string {
    const res = (tpl: string): string => RecipeParser.resolve(tpl, name, ver, '', prefix);
    try {
      if (s.action === 'symlink') {
        const linkPath: string = res((s.params['link'] as string) ?? '');
        let target: string = res((s.params['to'] as string) ?? '');
        const relative: boolean = s.params['relative'] !== false;
        if (!relative) { target = `${prefix}/${target}`; }
        const condition: string = (s.params['condition'] as string) ?? 'always';
        if (condition === 'if_no_valid') {
          try { fs.lstatSync(linkPath); fs.statSync(linkPath); return ''; } catch (_) {
          }
        }
        try { fs.lstatSync(linkPath); execSync(`rm -rf '${linkPath}' 2>/dev/null`); } catch (_) {
        }
        fs.symlinkSync(target, linkPath);
        return '';
      }
      if (s.action === 'link_bin') {
        const links: Object[] = (s.params['links'] as Object[]) ?? [];
        for (let i = 0; i < links.length; i++) {
          const pair: Record<string, Object> = links[i] as Record<string, Object>;
          const from: string = res((pair['from'] as string) ?? '');
          const to: string = res((pair['to'] as string) ?? '');
          const parent = to.substring(0, to.lastIndexOf('/'));
          try {
            if (!fs.accessSync(parent)) { fs.mkdirSync(parent, true); }
          } catch (_) {
          }
          try { fs.lstatSync(to); fs.unlinkSync(to); } catch (_) {
          }
          fs.symlinkSync(from, to);
        }
        return '';
      }
      if (s.action === 'shim') {
        const dir: string = res((s.params['dir'] as string) ?? '');
        const entries: Object[] = (s.params['entries'] as Object[]) ?? [];
        const currentDir: string = `${HOME}/usr/local/${name}/current`;
        const nodeBin: string = `${currentDir}/bin/node`;
        try {
          if (!fs.accessSync(dir)) { fs.mkdirSync(dir, true); }
        } catch (_) {
        }
        for (let i = 0; i < entries.length; i++) {
          const ent: Record<string, Object> = entries[i] as Record<string, Object>;
          const nm: string = (ent['name'] as string) ?? '';
          const execRaw: string = (ent['exec'] as string) ?? '';
          const toks: string[] = execRaw.trim().split(/\s+/);
          const scriptRel: string = toks.length > 1 ? toks.slice(1).join(' ') : '';
          if (nm === '' || scriptRel === '') { return `shim entries[${i}] 不合规`; }
          const scriptPath = `${dir}/${nm}`;
          try { fs.lstatSync(scriptPath); fs.unlinkSync(scriptPath); } catch (_) {
          }
          try {
            const f = fs.openSync(scriptPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
            fs.writeSync(f.fd, `#!/system/bin/sh\nexec "${nodeBin}" "${currentDir}/${scriptRel}" "$@"\n`);
            fs.closeSync(f.fd);
            execSync(`chmod +x '${scriptPath}'`);
          } catch (e) {
            return `shim ${nm} 写入失败：${e}`;
          }
        }
        return '';
      }
      if (s.action === 'shell_rc') {
        // activate 一般不需要（块已由 install 写入且版本无关）；实现同安装执行器语义
        const file: string = res((s.params['file'] as string) ?? `${HOME}/.zshrc`);
        const blockId: string = (s.params['block_id'] as string) ?? '';
        const linesArr: Object[] = (s.params['lines'] as Object[]) ?? [];
        return DevEnvSwitch.writeBlock(file, blockId, linesArr.map((l): string => res(`${l}`)));
      }
      return `activate 不支持 action「${s.action}」（协议违规）`;
    } catch (e) {
      return `${e}`;
    }
  }

  private static writeBlock(file: string, blockId: string, lines: string[]): string {
    if (blockId === '') { return 'shell_rc 缺 block_id'; }
    const begin = `# >>> ${blockId} >>>`;
    const end = `# <<< ${blockId} <<<`;
    let content: string = '';
    try { content = fs.readTextSync(file); } catch (_) {
    }
    const out: string[] = [];
    let inBlock = false;
    let replaced = false;
    for (const raw of content.split('\n')) {
      const t: string = raw.trim();
      if (t === begin) { inBlock = true; continue; }
      if (t === end) {
        inBlock = false;
        out.push(begin);
        for (const l of lines) { out.push(l); }
        out.push(end);
        replaced = true;
        continue;
      }
      if (!inBlock) { out.push(raw); }
    }
    if (!replaced) {
      if (out.length > 0 && out[out.length - 1].trim() !== '') { out.push(''); }
      out.push(begin);
      for (const l of lines) { out.push(l); }
      out.push(end);
    }
    try {
      const f = fs.openSync(file, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(f.fd, out.join('\n') + '\n');
      fs.closeSync(f.fd);
      return '';
    } catch (e) {
      return `写入失败：${e}`;
    }
  }
}

// ─── 卸载（uninstall 配方驱动） ───────────────────────────

export class DevEnvUninstall {

  static uninstall(op: UninstallOp, onProgress: ProgressCallback, onDone: DoneCallback): void {
    if (op.spec.steps.length === 0) {
      onDone(false, 'manifest 未提供 uninstall 配方');
      return;
    }
    const steps: StepSpec[] = op.spec.steps;
    const run = (i: number): void => {
      if (i >= steps.length) {
        DevEnvUninstall.afterRemove(op, onProgress, onDone);
        return;
      }
      const s: StepSpec = steps[i];
      onProgress({ step: i + 1, totalSteps: steps.length + 1, text: `${s.title}…`, percent: -1 });
      if (s.action === 'remove_dir') {
        const tpl: string = (s.params['target'] as string) ?? '{prefix}';
        const target: string = RecipeParser.resolve(tpl, op.name, op.ver, '', `${HOME}/usr/local/${op.name}/${op.ver}`);
        DevEnvUninstall.rmAsync(target, (ok: boolean, err: string) => {
          if (!ok && !s.optional) { onDone(false, `[${s.id}] 删除失败 ${err}`); return; }
          run(i + 1);
        });
      } else {
        onDone(false, `[${s.id}] uninstall 不支持 action「${s.action}」（协议违规）`);
      }
    };
    run(0);
  }

  /** 卸后联动：auto_activate=highest_remaining / on_last_removed=clear_current_and_block */
  private static afterRemove(op: UninstallOp, onProgress: ProgressCallback, onDone: DoneCallback): void {
    const base = `${HOME}/usr/local/${op.name}`;
    if (op.remaining.length === 0) {
      if (op.spec.onLastRemoved === 'clear_current_and_block') {
        try { execSync(`rm -rf '${base}/current' 2>/dev/null`); } catch (_) {
        }
        DevEnvPaths.stripPathLine(op.name);
      }
      DevEnvRegistry.del(op.name, op.ver);
      // 快照失效：账本已删而 installedCache 残留旧版本，随后的 install
      // 会误判 already installed（MCP 卸载→安装连击实证）
      EnvStore.invalidateInstalled(op.name);
      onDone(true, `${op.name} ${op.ver} 已卸载（无剩余版本）`);
      return;
    }
    if (op.spec.autoActivate === 'highest_remaining') {
      // 语义化版本降序（数字段逐位比）——原字典序 9.9 会压过 9.10（审查 P0-2）
      const sorted: string[] = op.remaining.slice().sort((a: string, b: string): number => DevEnvInstall.verCmpDesc(a, b));
      const top: string = sorted[0];
      const spec: ActivateSpec | null = op.activateOf(top);
      DevEnvSwitch.switch(op.name, top, spec, onProgress, (ok: boolean, msg: string) => {
        DevEnvRegistry.del(op.name, op.ver);
        if (ok) { EnvStore.noteInstalled(op.name, top); }
        else { EnvStore.invalidateInstalled(op.name); }
        onDone(ok, ok ? `${op.name} ${op.ver} 已卸载，活跃已切至 ${top}` : `已卸载但切换失败：${msg}`);
      });
      return;
    }
    DevEnvRegistry.del(op.name, op.ver);
    EnvStore.invalidateInstalled(op.name);
    onDone(true, `${op.name} ${op.ver} 已卸载`);
  }

  /** 异步递归删除（子进程执行，主线程零占用；输出带诊断探针——rm exit + 落盘验证） */
  private static rmAsync(dir: string, onDone: (ok: boolean, err: string) => void): void {
    try {
      const lines: string[] = [];
      DevTask.shell(
        `rm -rf '${dir}' 2>&1; echo "EXIT=$?"; ls -d '${dir}' 2>/dev/null || echo GONE`,
        (t: string, _e: boolean) => { lines.push(t.trim()); },
        (_ok: boolean, _d: string) => {
          const out: string = lines.join('|');
          const gone: boolean = out.indexOf('GONE') >= 0;
          onDone(gone, gone ? '' : `rm诊断[${out.substring(0, 60)}]`);
        },
      );
    } catch (e) {
      onDone(false, `${e}`);
    }
  }
}
