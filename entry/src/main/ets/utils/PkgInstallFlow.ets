/**
 * PkgInstallFlow —— 语言包安装流引擎（pip/npm 收敛，审查②）
 *
 * 背景：python_manager 与 node_manager 的包安装编排曾是 ~200 行复制粘贴双胞胎
 * （两页仅命令模板/净化正则/阶段文案表/队列组不同，且已互相漂移过两次）。
 * 本类收编单份机制实现，页面经构造参数注入差异：
 *  - 命令工厂（command）：pip 的版本参数/适配源 vs npm 的 -g --no-fund 等
 *  - 输出净化（cleanLine）：pip 白名单法 vs npm 盲文 spinner 剥除
 *  - 里程碑/阶段文案表（phasePct/stageLabel）：各包管理器关键字不同
 *  - 队列组（queueGroup）+ 取消 tag 前缀（tagPrefix）：'pip'/'npm' 互斥组
 *  - 状态回调（get/setInstalling、onEnqueued、onLogAppend、refreshInstalled）
 *
 * 机制（两页等价、单份实现）：
 *  - 去重（同名在装拒绝）→ 行占位（8% 排队中…）→ TaskQueue 互斥组入队
 *    （组空闲直跑；排队位次文案入队时写一次，epoch 变化时刷新）
 *  - creep 时间爬升：里程碑之间 +2%/2.2s 封顶 88%（进度条始终在动）
 *  - 完成补间 setFrame：cur→95→100 两段各 150ms，停留 1200ms 移除行
 *  - 三分支收尾：成功 / 用户取消（cancelledPkgs 标记区分于失败）/ 失败
 *    （fail loud：带出净化输出最后一条诊断行，截 44 字）
 *  - 取消双路：排队中 TaskQueue.dequeue；running cancelTag 杀进程 →
 *    onDone code≠0 → cancelledPkgs 分支显示「已取消」
 *  - 收尾 TaskQueue.done(group) 调度队首；refreshInstalled 重查已装列表
 *    （node 侧注入 2s 延迟包装——npm 落盘有延迟，语义差异保留）
 */
import { DevTask } from './DevTask';
import { TaskQueue } from './TaskQueue';
import { DevToast } from '../common/component';

/** 安装中行（页面 @State installingList 元素；引擎经回调读写） */
export interface InstallingPkg {
  name: string;
  progress: number;
  phase: string;    // 行文案（排队中/已取消/失败诊断；空串=按 stageLabel(progress) 渲染）
}

/** 引擎构造参数（差异注入 + 状态回调） */
export interface PkgInstallFlowConfig {
  /** 互斥组名（'pip'/'npm'）——同时用于队列展示名「安装 x（pip）」 */
  queueGroup: string;
  /** 取消/登记 tag 前缀（'pip_install_'/'npm_install_'，队列 id = 前缀+包名） */
  tagPrefix: string;
  /** 命令工厂（入队时冻结快照；adapted=走适配源，npm 侧忽略） */
  command: (name: string, adapted: boolean) => string;
  /** 原始输出行净化（乱码根因治理：pip 白名单法 / npm 盲文剥除，各自注入） */
  cleanLine: (raw: string) => string;
  /** 净化行 → 进度里程碑（0=不识别不推进；无全局百分比包管理器的关键字映射） */
  phasePct: (line: string) => number;
  /** 进度档位 → 阶段文案（页面行渲染兜底也走引擎这里取） */
  stageLabel: (p: number) => string;
  /** 读页面 @State installingList（引擎重建列表的输入） */
  getInstalling: () => InstallingPkg[];
  /** 写回页面 @State installingList（整表替换触发重渲染） */
  setInstalling: (list: InstallingPkg[]) => void;
  /** 行占位完成（页切「安装中」tab） */
  onEnqueued: () => void;
  /** 净化行追加（pip 日志窗实时查看；npm 无日志窗不注入） */
  onLogAppend?: (name: string, logs: string[]) => void;
  /** 三分支收尾后的已装列表重查（pip 立即 / npm 延迟 2s——注入差异保留） */
  refreshInstalled: () => void;
}

export class PkgInstallFlow {
  private cfg: PkgInstallFlowConfig;
  private cancelledPkgs: string[] = [];   // 用户主动取消的包（onDone 区分取消/失败）
  // 净化输出全量留存（失败诊断最后一条 + 页面日志窗查看）；任务启动时建数组（排队期无）
  private installLogs: Map<string, string[]> = new Map<string, string[]>();

  constructor(cfg: PkgInstallFlowConfig) {
    this.cfg = cfg;
  }

  /** 进度档位 → 阶段文案（页面行渲染兜底；表由构造注入） */
  stageLabel(p: number): string {
    return this.cfg.stageLabel(p);
  }

  /** 安装流日志（净化行全量；排队未启动/未知包 → 空数组） */
  logsOf(name: string): string[] {
    return this.installLogs.get(name) ?? [];
  }

  /** 队列变化（epoch）→ 更新所有排队行的位次文案（入队时只写一次，
   *  前面任务完成/出队后位次变化——真机实证「排队位次不变」问题） */
  onQueueEpoch(): void {
    const snap = TaskQueue.snapshot().filter((t) => t.group === this.cfg.queueGroup);
    let pos: number = 0;
    for (const t of snap) {
      if (t.id.startsWith(this.cfg.tagPrefix)) {
        pos += 1;
        const nm: string = t.id.substring(this.cfg.tagPrefix.length);
        if (pos > 1) {   // running 的 pos=1 不改（它有实时进度）
          const list: InstallingPkg[] = [];
          for (const item of this.cfg.getInstalling()) {
            list.push(item.name === nm
              ? { name: item.name, progress: item.progress, phase: `排队中（第 ${pos - 1} 位）` }
              : item);
          }
          this.cfg.setInstalling(list);
        }
      }
    }
  }

  /** 取消包安装：双路——排队中先出队（TaskQueue.dequeue）；
   *  running 中杀进程（cancelTag）+ 标记取消（onDone 区分取消/失败） */
  cancelInstall(name: string): void {
    // 排队中：直接出队（无 running 进程可杀）
    if (TaskQueue.dequeue(`${this.cfg.tagPrefix}${name}`)) {
      this.removeRow(name);
      DevToast.show(`${name} 已从队列移除`);
      return;
    }
    // running 中：杀进程 → onDone code≠0 → cancelledPkgs 分支显示「已取消」
    this.cancelledPkgs.push(name);
    DevTask.cancelTag(`${this.cfg.tagPrefix}${name}`);
  }

  /** 安装入口：同名在装去重 → 行占位（8% 排队中…）→ 互斥组入队（组空闲直跑） */
  install(name: string, adapted: boolean): void {
    for (const item of this.cfg.getInstalling()) {
      if (item.name === name) { DevToast.show(`${name} 正在安装中`); return; }
    }
    // 命令在入队时冻结（与原实现一致：排队期间版本选择变化不影响已入队任务）
    const cmd: string = this.cfg.command(name, adapted);
    const row: InstallingPkg = { name: name, progress: 8, phase: '排队中…' };
    this.cfg.setInstalling([...this.cfg.getInstalling(), row]);
    this.cfg.onEnqueued();
    const startInstall: () => void = (): void => {
    // running 接棒即清占位文案（phase='' → 按 stageLabel(progress) 渲染）——
    // 此前 creepTimer/onLine 只推进 progress、phase 原样保留，running 行一直
    // 顶着「排队中…」与实时进度并存（队列面板=进行中、卡片=排队中的矛盾根源）
    const startList: InstallingPkg[] = [];
    for (const item of this.cfg.getInstalling()) {
      startList.push(item.name === name
        ? { name: item.name, progress: item.progress, phase: '' }
        : item);
    }
    this.cfg.setInstalling(startList);
    // 时间爬升：里程碑之间缓慢推进（+2%/2.2s，封顶 88%）
    let creep = 8;
    const creepTimer: number = setInterval(() => {
      creep = Math.min(creep + 2, 88);
      const list: InstallingPkg[] = [];
      for (const item of this.cfg.getInstalling()) {
        list.push(item.name === name
          ? { name: item.name, progress: Math.max(item.progress, creep), phase: item.phase }
          : item);
      }
      this.cfg.setInstalling(list);
    }, 2200);
    const diagLines: string[] = [];   // 净化输出全量留存（诊断 + 日志窗查看）
    this.installLogs.set(name, diagLines);   // 日志窗引用共享（onLine 持续推）
    DevTask.shellCancellable(`${this.cfg.tagPrefix}${name}`, cmd,
      (t: string, _e: boolean) => {
        const line: string = this.cfg.cleanLine(t);
        if (line !== '') {
          diagLines.push(line);
          if (this.cfg.onLogAppend !== undefined) { this.cfg.onLogAppend(name, diagLines); }
        }
        if (line === '') { return; }
        const pct: number = this.cfg.phasePct(line);
        if (pct === 0) { return; }   // 不识别的输出行不进文案
        const list: InstallingPkg[] = [];
        for (const item of this.cfg.getInstalling()) {
          if (item.name === name) {
            list.push({ name: item.name,
              progress: pct > item.progress ? pct : item.progress,
              phase: item.phase });
          } else {
            list.push(item);
          }
        }
        this.cfg.setInstalling(list);
      },
      (ok: boolean, _d: string) => {
        clearInterval(creepTimer);
        // 完成补间：cur→95→100 两段各 150ms；停留 1200ms 再移除
        // （避免小包场景从低档直跳 100 一闪而过——快进感而非跳变）
        const setFrame = (pct: number, phase: string): void => {
          const list: InstallingPkg[] = [];
          for (const item of this.cfg.getInstalling()) {
            list.push(item.name === name
              ? { name: item.name, progress: pct, phase: phase }
              : item);
          }
          this.cfg.setInstalling(list);
        };
        if (ok) {
          setFrame(95, '');
          setTimeout(() => { setFrame(100, ''); }, 150);
          setTimeout(() => {
            this.removeRow(name);
            DevToast.ok(`${name} 安装完成`);
            this.cfg.refreshInstalled();
            TaskQueue.done(this.cfg.queueGroup);
          }, 1200);
        } else if (this.cancelledPkgs.indexOf(name) >= 0) {
          // 用户取消（cancelTag 杀进程 code≠0）：区别于失败——pip/npm 幂等，重装自动恢复
          this.cancelledPkgs = this.cancelledPkgs.filter((n: string): boolean => n !== name);
          setFrame(100, '已取消');
          setTimeout(() => {
            this.removeRow(name);
            DevToast.show(`${name} 已取消（重装自动恢复）`);
            this.cfg.refreshInstalled();
            TaskQueue.done(this.cfg.queueGroup);
          }, 1000);
        } else {
          // fail loud：带出最后一条诊断行（ERROR/警告等，避免三字失败无从排查）
          const lastDiag: string = diagLines.length > 0
            ? diagLines[diagLines.length - 1].slice(0, 44) : '';
          setFrame(100, lastDiag !== '' ? `失败：${lastDiag}` : '安装失败，请检查镜像源与网络');
          setTimeout(() => {
            this.removeRow(name);
            DevToast.show(`${name} 安装失败${lastDiag !== '' ? `：${lastDiag}` : ''}`);
            this.cfg.refreshInstalled();
            TaskQueue.done(this.cfg.queueGroup);
          }, 1200);
        }
      });
    };
    // 互斥组入队：并发写同 site-packages / 同全局 prefix 是 bug（盘点定论）——串行排队
    const qpos: number = TaskQueue.enqueue({
      id: `${this.cfg.tagPrefix}${name}`,
      label: `安装 ${name}（${this.cfg.queueGroup}）`,
      group: this.cfg.queueGroup,
      run: startInstall,
    });
    if (qpos > 0) {
      const list: InstallingPkg[] = [];
      for (const item of this.cfg.getInstalling()) {
        list.push(item.name === name
          ? { name: item.name, progress: item.progress, phase: `排队中（第 ${qpos} 位）` }
          : item);
      }
      this.cfg.setInstalling(list);
    }
  }

  private removeRow(name: string): void {
    this.cfg.setInstalling(this.cfg.getInstalling().filter((item: InstallingPkg): boolean => item.name !== name));
  }
}
