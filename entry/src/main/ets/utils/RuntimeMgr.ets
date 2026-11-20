/**
 * RuntimeMgr —— 语言运行时页共享控制器（live 模式）
 *
 * 协议对齐：PolarisTerm DEVENV-SPEC §6（多版本装/切/卸 + <name>-registry.json 共用）
 * 与 §8（GUI 任务协议：单任务、相位进度、装卸落账）。
 * 已装检测：~/usr/local/<name>/<ver> 目录扫描 + current 链接目标
 * 可装列表：ArtifactsRepo manifest（category=runtime：BiShengJDK/lua/node/perl/php/python/rust）
 * 装卸切换：DevEnvInstall 六步 / DevEnvUninstall 三步 / DevEnvSwitch，成功后落账 DevEnvRegistry
 */
import { ArtifactsRepo, RepoVersion } from './ArtifactsRepo';
import { DevEnvInstall, InstallOp, InstallProgress, DevEnvUninstall, DevEnvSwitch, RecipeParser, Recipe, ActivateSpec, UninstallSpec } from './DevEnvInstall';
import { TaskQueue } from './TaskQueue';
import hilog from '@ohos.hilog';
import { DevEnvRegistry } from './DevEnvRegistry';
import { DevEnvPaths } from './DevEnvPaths';
import { DiscoveryService } from './DiscoveryService';
import { DevTask } from './DevTask';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { EnvStore } from './EnvStore';










const HOME: string = '/storage/Users/currentUser';

export interface RuntimeInstalled {
  vers: string[];    // 已装版本（降序）
  active: string;    // current 指向的版本（可为空）
}

export class RuntimeMgr {

  /** §8 单任务队列（全局）：形如 'lua|5.4.8'，空串=空闲 */
  static busyTask: string = '';

  /** 任务完成纪元：AppStorage 'runtime_epoch'，任何存活页面实例 @Watch 后自刷新 */
  private static bump(): void {
    const cur: number = Number(AppStorage.get<number>('runtime_epoch') ?? 0) + 1;
    AppStorage.setOrCreate('runtime_epoch', cur);
  }

  /** 跨进程任务锁（filesDir 主/托盘进程共享：UI 与 MCP 同时安装的文件层冲突防线——
   *  claim 写锁+心跳，release 清锁；MCP 侧执行前调 crossProcessBusy 判断） */
  private static LOCK_FILE: string = '';

  private static lockPath(): string {
    if (RuntimeMgr.LOCK_FILE === '') {
      const ctx = AppStorage.get<common.UIAbilityContext>('ui_context_ctx');
      RuntimeMgr.LOCK_FILE = ctx !== undefined && ctx !== null ? `${ctx.filesDir}/busy.lock` : '';
    }
    return RuntimeMgr.LOCK_FILE;
  }

  private static writeLock(): void {
    const p: string = RuntimeMgr.lockPath();
    if (p === '') { return; }
    try {
      const f = fs.openSync(p, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(f.fd, `${RuntimeMgr.busyTask}|${Date.now()}`);
      fs.closeSync(f.fd);
    } catch (_) {
    }
  }

  private static clearLock(): void {
    const p: string = RuntimeMgr.lockPath();
    if (p === '') { return; }
    try {
      fs.unlinkSync(p);
    } catch (_) {
    }
  }

  /** 跨进程任务判断（MCP 侧用）：锁存在且心跳新鲜（90s 内——长下载 progress 更新心跳）即忙 */
  static crossProcessBusy(): string {
    const p: string = RuntimeMgr.lockPath();
    if (p === '') { return ''; }
    try {
      fs.accessSync(p);
      const text: string = fs.readTextSync(p);
      const seg: string[] = text.split('|');
      const at: number = Number(seg[2] ?? '0');
      if (Date.now() - at < 90000) {
        return seg.length >= 2 ? `${seg[0]} ${seg[1]}` : '未知任务';
      }
    } catch (_) {
    }
    return '';
  }

  // ── 准备超时看门狗（P5：卡"准备中"60s 自动取消——用户实证疑似网络不佳场景） ──
  // 任务 claim 后到首个进度回调之间卡死（下载 create 挂起/预检挂起等）无任何兜底，
  // 用户只能重启应用。60s 无进展 → 自动取消（断点保留）+ toast 说明。
  private static stageTimer: number = -1;
  private static stageGen: number = 0;

  private static armStageWatch(): void {
    RuntimeMgr.stageGen += 1;
    const myGen: number = RuntimeMgr.stageGen;
    if (RuntimeMgr.stageTimer >= 0) { clearTimeout(RuntimeMgr.stageTimer); }
    RuntimeMgr.stageTimer = setTimeout(() => {
      RuntimeMgr.stageTimer = -1;
      if (myGen !== RuntimeMgr.stageGen) { return; }   // 已被新任务/进度接管
      RuntimeMgr.onStageTimeout();
    }, 60000);
  }

  private static disarmStageWatch(): void {
    RuntimeMgr.stageGen += 1;   // 作废在途超时
    if (RuntimeMgr.stageTimer >= 0) {
      clearTimeout(RuntimeMgr.stageTimer);
      RuntimeMgr.stageTimer = -1;
    }
  }

  private static onStageTimeout(): void {
    if (RuntimeMgr.busyTask === '') { return; }
    DevEnvInstall.cancelWith('准备超时（60 秒无进展，疑似网络异常），已自动取消——断点保留可重试');
  }

  private static claim(pkg: string, ver: string): boolean {
    if (RuntimeMgr.busyTask !== '') {
      return false;
    }
    // 跨进程双向防线（审查 P1-1）：托盘进程（MCP）正在安装时本进程内存 busyTask 为空——
    // 原实现直接 claim → 双进程并发写 ~/usr/local。查锁文件，命中则失败走排队路径
    const cross: string = RuntimeMgr.crossProcessBusy();
    if (cross !== '') {
      hilog.warn(0x0000, 'testTag', 'claim blocked by cross-process task: %{public}s', cross);
      return false;
    }
    RuntimeMgr.busyTask = `${pkg}|${ver}`;
    AppStorage.setOrCreate('runtime_busy', RuntimeMgr.busyTask);
    RuntimeMgr.writeLock();
    return true;
  }

  private static release(): void {
    RuntimeMgr.busyTask = '';
    AppStorage.setOrCreate('runtime_busy', '');
    RuntimeMgr.clearLock();
    // 任务完成 → 统一数据层本地纠正（ensureLocal 内部 DevTask.shell 异步扫描）
    EnvStore.ensureLocal(true);
    // bump 必须等异步扫描完成后再触发——否则 epoch→refresh→detectInstalled 拿到旧数据
    setTimeout(() => { RuntimeMgr.bump(); }, 800);
  }

  /** 手动失效已装缓存（外部变更后调用；release 内部也会失效） */
  static invalidateDetect(): void {
    EnvStore.ensureLocal(true);
  }

  /**
   * 检测某运行时的已装版本与活跃版本。
   * 数据源 = EnvStore 统一数据层（安装账本为源 + shell 异步纠正），切页零 shell；
   * 纠正完成 / 任务完成会 bump epoch，页面 @Watch 自动刷新。
   */
  static detectInstalled(name: string): RuntimeInstalled {
    EnvStore.ensureLocal();
    const snap = EnvStore.installed(name);
    const vers: string[] = snap.vers.slice();
    vers.sort((a: string, b: string) => RuntimeMgr.verCmp(b, a));
    return { vers: vers, active: snap.active };
  }

  /** 语义化版本比较（降序用 b-a；数字段逐位比） */
  static verCmp(a: string, b: string): number {
    const pa: string[] = a.replace(/[^0-9.].*$/, '').split('.');
    const pb: string[] = b.replace(/[^0-9.].*$/, '').split('.');
    const n: number = Math.max(pa.length, pb.length);
    for (let i = 0; i < n; i++) {
      const x: number = Number(pa[i]) || 0;
      const y: number = Number(pb[i]) || 0;
      if (x !== y) {
        return x - y;
      }
    }
    return 0;
  }

  /** 拉取可装版本（EnvStore 统一远程目录：manifest 一次全量拉取按包切片） */
  static fetchAvailable(pkgName: string, onDone: (list: RepoVersion[]) => void): void {
    EnvStore.ensureRemote();
    const cached: RepoVersion[] = EnvStore.available(pkgName);
    if (cached.length > 0) {
      onDone(cached);
      return;
    }
    // 远程未就绪：等一个 epoch 再取（manifest 加载完成会 bump envstore_epoch）
    let tries: number = 0;
    const timer: number = setInterval(() => {
      tries++;
      const list: RepoVersion[] = EnvStore.available(pkgName);
      if (list.length > 0 || EnvStore.remoteReady()) {
        clearInterval(timer);
        onDone(EnvStore.available(pkgName));
      }
      // 上限 20 次（10s）：离线/慢网时 remoteReady 永不真 → 原实现永久轮询 +
      // 闭包持已销毁页面（审查 P0-1，stallAbort 风暴同族）
      if (tries >= 20) {
        clearInterval(timer);
        onDone(EnvStore.available(pkgName));
      }
    }, 500);
  }

  /**
   * 配方解析（陈旧缓存兜底）：内存快照解析失败 → 强制刷新 manifest 重试一次（最多 6s）→ 仍失败回 null。
   * 场景：启动后台指纹对比未完成时用户已操作，磁盘缓存旧 manifest 缺协议段（fail loud 前的最后自救）。
   */
  private static recipeOf(kind: string, pkgName: string, ver: string,
    pick: (rv: RepoVersion) => Object | null, onReady: (spec: Object | null) => void): void {
    const tryPick = (): Object | null => {
      const list: RepoVersion[] = EnvStore.available(pkgName);
      for (let i = 0; i < list.length; i++) {
        if (list[i].ver === ver) {
          const s: Object | null = pick(list[i]);
          if (s !== null) {
            return s;
          }
        }
      }
      return null;
    };
    const first: Object | null = tryPick();
    if (first !== null) {
      onReady(first);
      return;
    }
    // 缺失 → 强制刷新（discovery 指纹对比 + 必要时拉新 manifest），轮询至多 6s
    EnvStore.ensureRemote(true);
    let waited = 0;
    const timer: number = setInterval(() => {
      waited += 400;
      const s: Object | null = tryPick();
      if (s !== null || waited >= 6000) {
        clearInterval(timer);
        onReady(s);
      }
    }, 400);
  }

  /** 安装某版本（六步 + 相位进度 0-100 + 成功落账） */
  /** 包名/版本白名单（UI 与 MCP 双入口共用）——远程 manifest 值会拼入 shell
   *  脚本（回滚/链接链），白名单是最外层防线（审计维度 5：拒绝引号/分号/
   *  反引号/$() 等元字符）。首字符限字母或 @（scope 包名）。 */
  static safeNameVer(t: string): boolean {
    return /^[A-Za-z0-9@][A-Za-z0-9@\/._+\-]*$/.test(t);
  }

  static install(pkgName: string, rv: RepoVersion,
    onProgress: (pct: number, text: string) => void,
    onDone: (ok: boolean, msg: string) => void): void {
    // 白名单闸门：任一不合法即拒绝（fail-loud，防 shell 注入下游）
    if (!RuntimeMgr.safeNameVer(pkgName) || !RuntimeMgr.safeNameVer(rv.ver)) {
      onDone(false, `非法的包名或版本号：${pkgName} ${rv.ver}`);
      return;
    }
    let provides: string[] = [];
    try {
      provides = JSON.parse(rv.provides) as string[];
    } catch (_) {
      provides = [];
    }
    // 安装协议：install 配方驱动（缺失即失败——manifest 侧责任；陈旧缓存兜底刷一次）
    RuntimeMgr.recipeOf('install', pkgName, rv.ver, (cur: RepoVersion): Object | null =>
      RecipeParser.parse('install', cur.installRaw, pkgName, cur.ver, cur.kernel), (spec: Object | null) => {
      if (spec === null) {
        onDone(false, `manifest 未提供 ${pkgName} ${rv.ver} 的 install 配方（已刷新重试）`);
        return;
      }
      const recipe = spec as Recipe;
      const op: InstallOp = {
        kind: 'install',
        name: pkgName,
        ver: rv.ver,
        url: ArtifactsRepo.resolveUrl(rv),
        sha256: rv.sha256,
        size: rv.sizeBytes,
        recipe: recipe,
      };
      // P1 分队列：G1 忙时入队（排队提示）而非拒绝；完成时 TaskQueue.done 调度队首
      const pos: number = TaskQueue.enqueue({
        id: `install_${pkgName}_${rv.ver}`,
        label: `安装 ${pkgName} ${rv.ver}`,
        group: 'runtime',
        run: (): void => {
          if (!RuntimeMgr.claim(pkgName, rv.ver)) {
            TaskQueue.done('runtime');
            onDone(false, '已有任务进行中（本页或 AI/MCP 通道），请稍候重试');
            return;
          }
          RuntimeMgr.armStageWatch();   // claim 后无首个进度 60s → 自动取消（网络挂起兜底）
          DevEnvInstall.install(op, (p: InstallProgress) => {
            RuntimeMgr.disarmStageWatch();   // 首个进度到达：看门狗退役（幂等）
            onProgress(Math.max(2, p.percent), p.text);
          }, (ok: boolean, msg: string) => {
            if (ok) {
              const snap: Record<string, Object> = {};
              snap['path'] = rv.path;
              snap['sha256'] = rv.sha256;
              snap['size'] = rv.sizeBytes;
              snap['provides'] = JSON.stringify(provides);
              DevEnvRegistry.put(pkgName, rv.ver, snap);
            }
            RuntimeMgr.disarmStageWatch();   // 任务终态：清在途看门狗
            RuntimeMgr.release();
            TaskQueue.done('runtime');
            onDone(ok, msg);
          });
        },
      });
      if (pos === -1) {
        onDone(false, '已在队列中，请勿重复添加');
        return;
      }
      if (pos > 0) {
        onProgress(2, `已加入队列（第 ${pos} 位）`);
      }
    });
  }

  /**
   * 通用工具安装（manifest tool 类）。
   * 审计 C-P1-B1：与 install() 66 行逐字节相同（行为差异完全由 manifest
   * 配方决定——installTool 注释声称的"无 current 链接"差异不存在）。
   * 合并为直接委托。
   */
  static installTool(pkgName: string, rv: RepoVersion,
    onProgress: (pct: number, text: string) => void,
    onDone: (ok: boolean, msg: string) => void): void {
    RuntimeMgr.install(pkgName, rv, onProgress, onDone);
  }

  /** 已装工具版本探测（经统一数据层：账本 + 纠正，无独立通道） */

  /**
   * 装完运行时自动配对包源（pip/npm/maven；全部两段异步命令，零 shell 控制结构）。
   * 仅当用户尚未配置时写入（不覆盖任何已有配置）。
   */

  /** 切换活跃版本（activate 配方驱动；缺失时强制刷新重试一次） */
  static setActive(name: string, ver: string, onDone: (ok: boolean, msg: string) => void): void {
    RuntimeMgr.recipeOf('activate', name, ver, (cur: RepoVersion): Object | null =>
      RecipeParser.parse('activate', cur.activateRaw, name, cur.ver, cur.kernel), (spec: Object | null) => {
      if (spec === null) {
        onDone(false, `manifest 未提供 ${name} ${ver} 的 activate 配方（已刷新重试）`);
        return;
      }
      const pos: number = TaskQueue.enqueue({
        id: `activate_${name}_${ver}`,
        label: `切换 ${name} ${ver}`,
        group: 'runtime',
        run: (): void => {
          if (!RuntimeMgr.claim(name, ver)) {
            TaskQueue.done('runtime');
            onDone(false, '已有任务进行中（本页或 AI/MCP 通道），请稍候重试');
            return;
          }
          DevEnvSwitch.switch(name, ver, spec as ActivateSpec, () => {
          }, (ok: boolean, msg: string) => {
            if (ok) {
              DevEnvRegistry.updateVer(name, ver);
            }
            RuntimeMgr.release();
            TaskQueue.done('runtime');
            onDone(ok, msg);
          });
        },
      });
      if (pos === -1) {
        onDone(false, '已在队列中，请勿重复添加');
        return;
      }
      if (pos > 0) {
        onDone(false, `已加入队列（第 ${pos} 位）`);
      }
    });
  }

  /** 从 manifest 可用清单取某版本 activate 配方（同步读缓存；activate 时清单必已就绪） */
  private static activateRecipeOf(name: string, ver: string): ActivateSpec | null {
    const list: RepoVersion[] = EnvStore.available(name);
    for (const rv of list) {
      if (rv.ver === ver) {
        return RecipeParser.parse('activate', rv.activateRaw, name, ver, rv.kernel) as ActivateSpec | null;
      }
    }
    return null;
  }

  /** 卸载某版本（三步：删目录→清理链接/PATH→自愈链；剩余版本自动顶替 current） */
  static uninstall(pkgName: string, ver: string, available: RepoVersion[],
    onProgress: (pct: number, text: string) => void,
    onDone: (ok: boolean, msg: string) => void): void {
    const st: RuntimeInstalled = RuntimeMgr.detectInstalled(pkgName);
    const remaining: string[] = st.vers.filter(v => v !== ver);
    // uninstall 配方（取该版本条目；缺失时强制刷新重试一次）
    RuntimeMgr.recipeOf('uninstall', pkgName, ver, (cur: RepoVersion): Object | null =>
      RecipeParser.parse('uninstall', cur.uninstallRaw, pkgName, cur.ver, cur.kernel), (spec: Object | null) => {
      if (spec === null) {
        onDone(false, `manifest 未提供 ${pkgName} ${ver} 的 uninstall 配方（已刷新重试）`);
        return;
      }
      const pos: number = TaskQueue.enqueue({
        id: `uninstall_${pkgName}_${ver}`,
        label: `卸载 ${pkgName} ${ver}`,
        group: 'runtime',
        run: (): void => {
          if (!RuntimeMgr.claim(pkgName, ver)) {
            TaskQueue.done('runtime');
            onDone(false, '已有任务进行中（本页或 AI/MCP 通道），请稍候重试');
            return;
          }
          DevEnvUninstall.uninstall({
            kind: 'uninstall',
            name: pkgName,
            ver: ver,
            remaining: remaining,
            spec: spec as UninstallSpec,
            activateOf: (v: string): ActivateSpec | null => RuntimeMgr.activateRecipeOf(pkgName, v),
          }, (p: InstallProgress) => {
            onProgress(Math.max(3, Math.round(p.step / (p.totalSteps + 1) * 100)), p.text);
          }, (ok: boolean, msg: string) => {
            RuntimeMgr.release();
            TaskQueue.done('runtime');
            onDone(ok, msg);
          });
        },
      });
      if (pos === -1) {
        onDone(false, '已在队列中，请勿重复添加');
        return;
      }
      if (pos > 0) {
        onProgress(3, `已加入队列（第 ${pos} 位）`);
      }
    });
  }

  /** 取消进行中的安装 */
  static cancel(): void {
    DevEnvInstall.cancel();
  }
}
